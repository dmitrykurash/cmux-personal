#!/usr/bin/env python3
"""Personal cmux bridge. Runs as the SSH user; no listener, SDK or API keys.

JSON request on stdin, one JSON response on stdout. Interactive Claude is owned
by a dedicated tmux server. Never leave a shell behind when Claude exits.
"""
import base64
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path.home() / ".local/share/cmux-personal"
TRANSCRIPTS = Path.home() / ".claude/projects"
MAX_ATTACHMENT = 20 * 1024 * 1024
MAX_TRANSCRIPT = 32 * 1024 * 1024


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink() or path.stat().st_uid != os.getuid():
        raise ValueError("Unsafe state directory")
    path.chmod(0o700)
    return path


def atomic_json(path, value):
    temp = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream)
    os.replace(temp, path)


def session_id(value):
    return str(uuid.UUID(value))


def project_path(value):
    if not isinstance(value, str) or not value.startswith("/") or any(ord(c) < 32 for c in value):
        raise ValueError("Project must be an absolute directory")
    path = Path(value).resolve(strict=True)
    if not path.is_dir():
        raise ValueError("Project directory does not exist")
    return path


def executable(name):
    local = Path.home() / ".local/bin" / name
    return str(local) if local.is_file() else shutil.which(name)


def tmux(*args, input=None, check=True):
    binary = executable("tmux")
    if not binary:
        raise ValueError("tmux is required on the VPS")
    return subprocess.run([binary, "-L", "cmux-personal", *args], input=input,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check, timeout=15)


def target(sid):
    return "=cmp-" + session_id(sid)


def alive(sid):
    return tmux("has-session", "-t", target(sid), check=False).returncode == 0


def metadata(sid):
    return json.loads((ROOT / (session_id(sid) + ".json")).read_text())


def read_status(sid):
    try:
        return json.loads((ROOT / (session_id(sid) + ".status")).read_text())["phase"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        return "starting"


def set_status(sid, phase):
    atomic_json(ROOT / (session_id(sid) + ".status"), {"phase": phase, "time": time.time()})


@contextlib.contextmanager
def session_lock(sid):
    private_dir(ROOT)
    fd = os.open(ROOT / (session_id(sid) + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def records(path):
    if path.is_symlink() or path.stat().st_size > MAX_TRANSCRIPT:
        raise ValueError("Transcript is too large for this MVP; use the terminal")
    with path.open() as stream:
        for line in stream:
            try:
                yield json.loads(line)
            except (ValueError, TypeError):
                continue  # A writer may not have completed its last JSONL line.


def transcript(sid, project):
    # Match the explicit cwd as well as UUID: never resume an unrelated project.
    for path in TRANSCRIPTS.glob("*/" + session_id(sid) + ".jsonl"):
        for record in records(path):
            if record.get("cwd"):
                if Path(record["cwd"]).resolve() == project:
                    return path
                break
    return None


def text_content(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") if c.get("type") == "text" else
                         "[image]" if c.get("type") == "image" else ""
                         for c in content if isinstance(c, dict)).strip()
    return ""


def messages(path):
    result = []
    seen = set()
    if not path:
        return result
    for i, record in enumerate(records(path)):
        role = record.get("type")
        if role not in ("user", "assistant") or record.get("isSidechain") or record.get("isMeta"):
            continue
        message = record.get("message", {})
        content = message.get("content", "")
        text = text_content(content)
        rid = str(record.get("uuid", i))
        if rid in seen:
            continue
        seen.add(rid)
        if text:
            result.append({"id": rid, "role": role, "text": text})
        if isinstance(content, list):
            for j, block in enumerate(content):
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    # Inputs may include secrets. Only expose the tool name here.
                    result.append({"id": rid + "-" + str(j), "role": "tool", "text": block.get("name", "Tool")})
    return result[-400:]


def list_sessions(project):
    found = {}
    for path in TRANSCRIPTS.glob("*/*.jsonl"):
        try:
            sid = session_id(path.stem)
            if transcript(sid, project) != path:
                continue
            title = "New chat"
            for record in records(path):
                if record.get("type") == "user" and not record.get("isMeta"):
                    value = text_content(record.get("message", {}).get("content", ""))
                    if value:
                        title = value[:80].replace("\n", " ")
                        break
            found[sid] = {"id": sid, "title": title, "updated": path.stat().st_mtime}
        except (ValueError, OSError):
            continue
    for path in ROOT.glob("*.json"):
        try:
            meta = json.loads(path.read_text())
            if meta.get("project") == str(project) and meta["id"] not in found:
                found[meta["id"]] = {"id": meta["id"], "title": "New chat", "updated": path.stat().st_mtime}
        except (ValueError, KeyError, OSError):
            continue
    return sorted(found.values(), key=lambda item: item["updated"], reverse=True)[:100]


def start(sid, project, resume):
    with session_lock(sid):
        if alive(sid):
            if metadata(sid)["project"] != str(project):
                raise ValueError("Session belongs to another project")
            return {"id": sid}
        claude = executable("claude")
        if not claude:
            raise ValueError("Claude Code is not installed on the VPS")
        if resume and not transcript(sid, project):
            raise ValueError("Cannot resume a transcript outside this project")
        # No --print, SDK, API proxy, permission bypass or secret-bearing flags.
        hook_command = "python3 " + shlex.quote(str(ROOT / "bridge.py")) + " --hook " + shlex.quote(sid)
        hooks = {event: [{"matcher": "", "hooks": [{"type": "command", "command": hook_command}]}]
                 for event in ("SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "Notification", "SessionEnd")}
        settings = ROOT / (sid + ".settings.json")
        atomic_json(settings, {"hooks": hooks})
        command = "exec " + shlex.join([claude, "--resume" if resume else "--session-id", sid,
                                         "--settings", str(settings), "--permission-mode", "default"])
        atomic_json(ROOT / (sid + ".json"), {"id": sid, "project": str(project)})
        set_status(sid, "starting")
        tmux("new-session", "-d", "-s", "cmp-" + sid, "-x", "120", "-y", "36", "-c", str(project), command)
        return {"id": sid}


def upload(sid, name, encoded):
    # Store files outside the repository with owner-only permissions; reference
    # exact remote paths in the prompt. No shell expansion or overwrite.
    metadata(sid)
    if not name or name in (".", "..") or Path(name).name != name or "\\" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Invalid attachment name")
    if len(encoded) > (MAX_ATTACHMENT * 4 // 3 + 8):
        raise ValueError("Attachment exceeds 20 MiB")
    data = base64.b64decode(encoded, validate=True)
    if len(data) > MAX_ATTACHMENT:
        raise ValueError("Attachment exceeds 20 MiB")
    folder = private_dir(private_dir(ROOT / "attachments") / sid)
    folder = private_dir(folder / uuid.uuid4().hex)
    path = folder / name
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
    return {"path": str(path)}


def send(sid, text):
    if not text.strip() or len(text.encode()) > 128 * 1024:
        raise ValueError("Message is empty or too large")
    if any(ord(c) < 32 and c not in "\n\t" for c in text) or "\x7f" in text:
        raise ValueError("Terminal control characters are not allowed")
    with session_lock(sid):
        metadata(sid)
        if not alive(sid) or read_status(sid) != "ready":
            raise ValueError("Claude is not ready. Resolve prompts in the terminal first.")
        set_status(sid, "busy")  # Reserve before injecting; never retry automatically.
        buffer = "cmp-" + uuid.uuid4().hex
        try:
            tmux("load-buffer", "-b", buffer, "-", input=text.encode())
            tmux("paste-buffer", "-d", "-p", "-b", buffer, "-t", target(sid) + ":")
            tmux("send-keys", "-t", target(sid) + ":", "Enter")
        except Exception:
            set_status(sid, "attention")  # Delivery may have happened. Never auto-resend.
            raise
    return {"sent": True}


def dispatch(request):
    op = request["op"]
    private_dir(ROOT)
    if op == "health":
        return {"user": __import__("getpass").getuser(), "claude": bool(executable("claude")), "tmux": bool(executable("tmux"))}
    if op == "install":
        source = request["source"]
        compile(source, "bridge.py", "exec")
        path = ROOT / "bridge.py"
        temp = ROOT / ("bridge-" + uuid.uuid4().hex + ".tmp")
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write(source)
        os.replace(temp, path)
        return {"installed": True}
    if op == "list":
        return {"sessions": list_sessions(project_path(request["project"]))}
    sid = session_id(request["id"])
    if op == "start":
        return start(sid, project_path(request["project"]), bool(request.get("resume")))
    if op == "read":
        project = project_path(request["project"])
        live = alive(sid)
        # Historical unmanaged sessions are read-only until explicit Resume.
        managed = (ROOT / (sid + ".json")).exists()
        if managed and metadata(sid)["project"] != str(project):
            raise ValueError("Session belongs to another project")
        return {"messages": messages(transcript(sid, project)), "phase": read_status(sid) if live and managed else "offline", "live": live and managed}
    if op == "upload":
        return upload(sid, request["name"], request["data"])
    if op == "send":
        return send(sid, request["text"])
    if op == "interrupt":
        metadata(sid)
        if alive(sid):
            tmux("send-keys", "-t", target(sid) + ":", "Escape")
        return {"interrupted": True}
    raise ValueError("Unknown operation")


def hook(sid, event):
    name = event.get("hook_event_name")
    phase = {"SessionStart": "ready", "UserPromptSubmit": "busy", "Stop": "ready",
             "PermissionRequest": "permission", "SessionEnd": "offline"}.get(name)
    if name == "Notification" and event.get("notification_type") == "permission_prompt":
        phase = "permission"
    # idle_prompt also fires for questions/pickers: it must not enable the composer.
    if phase:
        private_dir(ROOT)
        set_status(sid, phase)


def main():
    os.umask(0o077)
    if len(sys.argv) == 3 and sys.argv[1] == "--hook":
        hook(session_id(sys.argv[2]), json.load(sys.stdin))
        return  # No stdout: hooks must never approve or alter permission decisions.
    try:
        raw = sys.stdin.buffer.read(30 * 1024 * 1024 + 1)
        if len(raw) > 30 * 1024 * 1024:
            raise ValueError("Request too large")
        result = dispatch(json.loads(raw))
        print(json.dumps({"ok": True, **result}))
    except Exception as exc:
        # No stdout/stderr from subprocesses: terminal output may contain secrets.
        message = str(exc) if isinstance(exc, (ValueError, FileNotFoundError)) else type(exc).__name__
        print(json.dumps({"ok": False, "error": message}))
        sys.exit(1)


if __name__ == "__main__":
    main()
