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
import signal
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


class ProjectError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


class ImportCancelled(Exception):
    pass


def repository_url(value):
    if not isinstance(value, str) or len(value) > 2048 or any(c.isspace() or ord(c) < 32 for c in value):
        raise ProjectError('repository_url')
    host = r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?'
    # No credentials, local paths, Git helper transports, query or fragment.
    if re.fullmatch(r'git@' + host + r':[A-Za-z0-9_./~%-]+', value):
        return value
    from urllib.parse import urlsplit
    try:
        parsed = urlsplit(value)
        valid = (parsed.scheme in ('https', 'ssh') and parsed.hostname and
                 re.fullmatch(host, parsed.hostname) and parsed.path not in ('', '/') and
                 not parsed.query and not parsed.fragment and parsed.password is None and
                 (parsed.username is None if parsed.scheme == 'https' else parsed.username == 'git') and
                 (parsed.port is None or 1 <= parsed.port <= 65535))
    except ValueError:
        valid = False
    if not valid:
        raise ProjectError('repository_url')
    return value


def selected_folder(value):
    try:
        return project_path(value)
    except (ValueError, OSError):
        raise ProjectError('project_path') from None


def new_project_folder(value):
    if not isinstance(value, str) or not value.startswith('/') or any(ord(c) < 32 for c in value):
        raise ProjectError('project_path')
    path = Path(value)
    if path.name in ('', '.', '..') or '..' in path.parts:
        raise ProjectError('project_path')
    parent = selected_folder(str(path.parent))
    path = parent / path.name
    try:
        path.mkdir(mode=0o700)  # Exclusive reservation, including dangling symlinks.
    except FileExistsError:
        raise ProjectError('destination_exists') from None
    except OSError:
        raise ProjectError('project_path') from None
    return path


def folders(value=None):
    path = selected_folder(value or str(Path.home()))
    try:
        with os.scandir(path) as entries:
            names = sorted(entry.name for entry in entries if not entry.name.startswith('.')
                           and entry.is_dir(follow_symlinks=False))[:200]
    except OSError:
        raise ProjectError('project_path') from None
    return {'path': str(path), 'parent': str(path.parent), 'directories': names}


def import_folder(jid):
    return ROOT / 'imports' / session_id(jid)


def read_import(jid):
    try:
        return json.loads((import_folder(jid) / 'status.json').read_text())
    except (OSError, ValueError):
        raise ProjectError('import_failed') from None


def process_identity(pid):
    # Linux /proc start ticks prevent signaling a recycled PID after a crash.
    try:
        return (Path('/proc') / str(pid) / 'stat').read_text().rsplit(') ', 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def cancel_import(jid):
    folder = import_folder(jid)
    state = read_import(jid)
    if state['phase'] != 'cloning':
        return state
    (folder / 'cancel').touch(mode=0o600, exist_ok=True)
    pid, identity = state.get('pid'), state.get('identity')
    if pid and identity and process_identity(pid) == identity:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    return {'id': session_id(jid), 'phase': 'cancelling', 'path': state['path']}


def wait_import(jid):
    folder = import_folder(jid)
    # Long-poll the worker's inherited lock, waking on exit instead of sleeping.
    # A 30-second response deadline fits within the SSH request's 45 seconds.
    def deadline(_signum, _frame):
        raise TimeoutError()
    previous = signal.signal(signal.SIGALRM, deadline)
    try:
        with (folder / 'running.lock').open('rb') as lock:
            signal.alarm(30)
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
                state = read_import(jid)
                if state['phase'] == 'cloning':
                    state.update(phase='failed', code='import_failed')
                    atomic_json(folder/'status.json', state)
                return state
            except TimeoutError:
                return read_import(jid)
    except OSError:
        raise ProjectError('import_failed') from None
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def prepare_project(request):
    mode = request.get('mode')
    if mode == 'existing':
        return {'path': str(selected_folder(request.get('project'))), 'phase': 'done'}
    if mode == 'empty':
        return {'path': str(new_project_folder(request.get('project'))), 'phase': 'done'}
    if mode != 'clone':
        raise ProjectError('import_failed')
    url = repository_url(request.get('repository'))
    if not executable('git'):
        raise ProjectError('git_missing')
    jid = session_id(request['id'])
    folder = import_folder(jid)
    private_dir(folder.parent)
    try:
        folder.mkdir(mode=0o700)
    except FileExistsError:
        state = read_import(jid)
        if state['repository'] != url or state['requestedPath'] != request['project']:
            raise ProjectError('import_failed')
        return state  # Recovery after a lost SSH reply never starts another clone.
    try:
        destination = new_project_folder(request.get('project'))
    except Exception:
        folder.rmdir()
        raise
    state = {'id': jid, 'phase': 'cloning', 'path': str(destination), 'repository': url,
             'requestedPath': request['project'], 'device': destination.stat().st_dev, 'inode': destination.stat().st_ino}
    atomic_json(folder/'status.json', state)
    lockfd = os.open(folder/'running.lock', os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
    fcntl.flock(lockfd, fcntl.LOCK_EX)
    try:
        # A job keeps its exact helper version if another app later reconnects.
        source = request.get('source') or (ROOT/'bridge.py').read_text()
        compile(source, 'worker.py', 'exec')
        (folder/'worker.py').write_text(source)
        (folder/'worker.py').chmod(0o600)
        subprocess.Popen([sys.executable, str(folder/'worker.py'), '--project-job', jid, str(lockfd)],
                         pass_fds=(lockfd,), start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        state.update(phase='failed', code='import_failed')
        atomic_json(folder/'status.json', state)
        with contextlib.suppress(OSError):
            destination.rmdir()  # Only removes our reservation if still empty.
        raise ProjectError('import_failed') from None
    finally:
        os.close(lockfd)  # Child owns the inherited lock until job completion.
    return state


def clone_command(url, destination):
    return [executable('git'), '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
            '-c', 'protocol.ssh.allow=always', '-c', 'core.hooksPath=/dev/null',
            'clone', '--quiet', '--no-recurse-submodules', '--template=', '--', url, str(destination)]


def project_worker(jid, lockfd):
    folder = import_folder(jid)
    state = read_import(jid)
    child = None
    def cancelled(_signum, _frame):
        raise ImportCancelled()
    signal.signal(signal.SIGTERM, cancelled)
    try:
        state.update(pid=os.getpid(), identity=process_identity(os.getpid()))
        atomic_json(folder/'status.json', state)
        if (folder/'cancel').exists():
            raise ImportCancelled()
        destination = Path(state['path'])
        info = destination.lstat()
        if destination.is_symlink() or (info.st_dev, info.st_ino) != (state['device'], state['inode']):
            raise ProjectError('destination_exists')
        env = os.environ.copy()
        env.update(GIT_TERMINAL_PROMPT='0', GIT_ASKPASS='/bin/false', SSH_ASKPASS='/bin/false',
                   GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ForwardAgent=no -o ClearAllForwardings=yes -o PermitLocalCommand=no',
                   GIT_LFS_SKIP_SMUDGE='1')
        child = subprocess.Popen(clone_command(state['repository'], destination), env=env,
                                 start_new_session=True, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        _, stderr = child.communicate(timeout=600)
        if child.returncode:
            lower = stderr[-8192:].lower()
            code = 'git_access' if any(term in lower for term in (b'authentication', b'could not read username', b'permission denied', b'repository not found', b'host key verification', b'publickey')) else 'import_failed'
            raise ProjectError(code)
        state.update(phase='done')
    except ImportCancelled:
        state.update(phase='cancelled')
    except subprocess.TimeoutExpired:
        state.update(phase='failed', code='import_timeout')
    except ProjectError as exc:
        state.update(phase='failed', code=exc.code)
    except Exception:
        state.update(phase='failed', code='import_failed')
    finally:
        # Ignore repeated cancel signals while finishing our own process group.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if child is not None and child.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGTERM)
            try:
                child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
                child.communicate()
        if state['phase'] != 'done':
            # Never recursively remove anything: partial data remains recoverable.
            with contextlib.suppress(OSError):
                Path(state['path']).rmdir()
        state.pop('pid', None)
        state.pop('identity', None)
        atomic_json(folder/'status.json', state)
        os.close(lockfd)


def dispatch(request):
    op = request["op"]
    private_dir(ROOT)
    if op == "folders":
        return folders(request.get("project"))
    if op == "project_prepare":
        return prepare_project(request)
    if op == "project_wait":
        return wait_import(request["id"])
    if op == "project_cancel":
        return cancel_import(request["id"])
    if op == "health":
        return {"user": __import__("getpass").getuser(), "claude": bool(executable("claude")), "tmux": bool(executable("tmux")), "git": bool(executable("git")), "githubCLI": bool(executable("gh")), "path": str(Path.home()/"projects" if (Path.home()/"projects").is_dir() else Path.home())}
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
    if len(sys.argv) == 4 and sys.argv[1] == "--project-job":
        project_worker(session_id(sys.argv[2]), int(sys.argv[3]))
        return
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
        print(json.dumps({"ok": False, "error": message, "code": getattr(exc, "code", None)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
