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
import socket
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path.home() / ".local/share/cmux-personal"
TRANSCRIPTS = Path.home() / ".claude/projects"
MAX_ATTACHMENT = 20 * 1024 * 1024
MAX_TRANSCRIPT = 32 * 1024 * 1024
UI_LEASE_SECONDS = 15
PERMISSION_SECONDS = 540


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


def ui_lease(sid):
    try:
        return json.loads((ROOT / (sid + ".ui.json")).read_text())["time"] + UI_LEASE_SECONDS
    except (OSError, ValueError, KeyError, TypeError):
        return 0


def permission_paths(rid):
    # Short names keep Unix socket paths below the platform limit.
    stem = uuid.UUID(rid).hex
    folder = private_dir(ROOT / "p")
    return folder / (stem + ".json"), folder / (stem + ".sock")


def pending_permissions(sid, project):
    result = []
    for path in (ROOT / "p").glob("*.json"):
        try:
            if path.is_symlink() or path.stat().st_size > 160 * 1024:
                continue
            value = json.loads(path.read_text())
            if value["sessionID"] != sid or value["project"] != str(project) or value["expires"] <= time.time():
                continue
            _, sock = permission_paths(value["id"])
            if not sock.exists() or ui_lease(sid) <= time.time():
                continue
            result.append(value)
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return sorted(result, key=lambda value: value["expires"])


def permission_frame(stream):
    data = bytearray()
    while len(data) <= 2048:
        chunk = stream.recv(2049 - len(data))
        if not chunk:
            raise ValueError("Approval connection closed")
        data.extend(chunk)
        if b"\n" in data:
            return json.loads(data.split(b"\n", 1)[0])
    raise ValueError("Approval response is too large")


def request_permission(sid, event):
    # Interactive questions, trust, passwords and oversized inputs keep the CLI UI.
    if event.get("tool_name") in (None, "AskUserQuestion", "ExitPlanMode") or not isinstance(event.get("tool_input"), dict):
        return None
    if event.get("session_id") != sid or ui_lease(sid) <= time.time():
        return None
    project = project_path(event.get("cwd"))
    if metadata(sid)["project"] != str(project):
        return None
    detail = json.dumps(event["tool_input"], ensure_ascii=False, indent=2)
    if len(detail.encode()) > 128 * 1024:
        return None
    rid = str(uuid.uuid4())
    path, socket_path = permission_paths(rid)
    expires = time.time() + PERMISSION_SECONDS
    value = {"id": rid, "sessionID": sid, "project": str(project),
             "tool": str(event["tool_name"]), "detail": detail, "expires": expires}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.bind(str(socket_path))
            socket_path.chmod(0o600)
            server.listen(4)
            with lifecycle_lock():
                if (ROOT / "deleted" / sid).exists():
                    return None
                atomic_json(path, value)
            while True:
                # Wait for a decision or the current desktop lease to expire.
                # Closing the app or switching away returns control to the CLI.
                remaining = min(expires, ui_lease(sid)) - time.time()
                if remaining <= 0 or (ROOT / "deleted" / sid).exists():
                    return None
                server.settimeout(remaining)
                try:
                    stream, _ = server.accept()
                except socket.timeout:
                    continue  # Re-evaluate the lease renewed by a UI read.
                with stream:
                    stream.settimeout(min(2, remaining))
                    try:
                        answer = permission_frame(stream)
                        if answer.get("id") != rid or answer.get("sessionID") != sid or answer.get("decision") not in ("allow", "deny", "terminal"):
                            stream.sendall(b'{"accepted":false}\n')
                            continue
                        if min(expires, ui_lease(sid)) <= time.time() or (ROOT / "deleted" / sid).exists():
                            return None
                        decision = answer["decision"]
                        # Consume before acknowledging. A duplicate/stale card can
                        # never answer another request, including after reconnect.
                        path.unlink(missing_ok=True)
                        if decision != "terminal":
                            set_status(sid, "busy")
                        try:
                            stream.sendall(b'{"accepted":true}\n')
                        except OSError:
                            pass  # The decision arrived; never ask the UI to resend it.
                        if decision == "terminal":
                            return None
                        output = {"behavior": decision}
                        if decision == "deny":
                            output["message"] = "The user declined this request in CheatCode."
                        return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": output}}
                    except (OSError, ValueError, TypeError):
                        continue
    finally:
        path.unlink(missing_ok=True)
        socket_path.unlink(missing_ok=True)


def decide_permission(request):
    sid = session_id(request["id"])
    project = project_path(request["project"])
    rid = session_id(request["approvalID"])
    decision = request.get("decision")
    if decision not in ("allow", "deny", "terminal"):
        raise ValueError("Invalid approval decision")
    with lifecycle_lock():
        if (ROOT / "deleted" / sid).exists() or metadata(sid)["project"] != str(project) or not alive(sid):
            raise ValueError("This permission request is no longer active")
        if not any(value["id"] == rid for value in pending_permissions(sid, project)):
            raise ValueError("This permission request expired or was already answered")
        _, socket_path = permission_paths(rid)
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
                stream.settimeout(3)
                stream.connect(str(socket_path))
                stream.sendall((json.dumps({"id": rid, "sessionID": sid, "decision": decision}) + "\n").encode())
                if permission_frame(stream).get("accepted") is not True:
                    raise ValueError("This permission request is no longer active")
        except OSError:
            raise ValueError("Approval delivery could not be confirmed. Refresh before trying again.") from None
    return {"id": rid}


def remove_permission_state(sid):
    (ROOT / (sid + ".ui.json")).unlink(missing_ok=True)
    for path in (ROOT / "p").glob("*.json"):
        try:
            if path.is_symlink() or path.stat().st_size > 160 * 1024:
                continue
            value = json.loads(path.read_text())
        except FileNotFoundError:
            continue  # The hook can finish and remove its file concurrently.
        if value.get("sessionID") == sid:
            expected, sock = permission_paths(value["id"])
            if expected == path:
                path.unlink(missing_ok=True)
                sock.unlink(missing_ok=True)


def handoff_permissions(request):
    sid = session_id(request["id"])
    project = project_path(request["project"])
    with lifecycle_lock():
        if metadata(sid)["project"] != str(project) or (ROOT / "deleted" / sid).exists():
            raise ValueError("Session belongs to another project or was deleted")
        pending = pending_permissions(sid, project)
        # Revoke first, so requests arriving during this handoff also use the CLI.
        atomic_json(ROOT / (sid + ".ui.json"), {"time": 0})
        for value in pending:
            _, sock = permission_paths(value["id"])
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
                    stream.settimeout(1)
                    stream.connect(str(sock))
                    stream.sendall(b'{}\n')  # Wake the hook to observe the revoked lease.
            except OSError:
                pass  # An already-finished hook needs no handoff.
    return {"id": sid}


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
    return sorted(found.values(), key=lambda item: item["updated"], reverse=True)


def start(sid, project, resume):
    with lifecycle_lock(), session_lock(sid):
        if (ROOT/"deleted"/sid).exists():
            raise ValueError("This chat was permanently deleted")
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
        hooks["PermissionRequest"][0]["hooks"][0]["timeout"] = 600
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


def send(sid, text, approval_ui=False):
    if not text.strip() or len(text.encode()) > 128 * 1024:
        raise ValueError("Message is empty or too large")
    if any(ord(c) < 32 and c not in "\n\t" for c in text) or "\x7f" in text:
        raise ValueError("Terminal control characters are not allowed")
    with lifecycle_lock(), session_lock(sid):
        metadata(sid)
        if not alive(sid) or read_status(sid) != "ready":
            raise ValueError("Claude is not ready. Resolve prompts in the terminal first.")
        if approval_ui:
            atomic_json(ROOT / (sid + ".ui.json"), {"time": time.time()})
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


@contextlib.contextmanager
def lifecycle_lock():
    private_dir(ROOT)
    fd = os.open(ROOT/'lifecycle.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        yield


def deletion_project(value):
    path = project_path(value)
    home = Path.home().resolve()
    # Never turn a project operation into deletion of the home, project container,
    # credentials, app state or a path reached through a symlink.
    if (str(path) != value or home not in path.parents or path == home/'projects'
            or any(part.startswith('.') for part in path.relative_to(home).parts)
            or path.stat().st_uid != os.getuid()):
        raise ValueError('This folder cannot be deleted from the app. Remove it from the sidebar instead.')
    for folder, directories, _ in os.walk(path, followlinks=False):
        for name in directories:
            child = Path(folder)/name
            if not child.is_symlink() and os.path.ismount(child):
                raise ValueError('Folder contains a mounted filesystem; deletion is not available.')
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError('Safe directory deletion is unavailable on this server.')
    return path


def deletion_inventory(project, recursive=False):
    found = {}
    def belongs(value):
        cwd = Path(value).resolve()
        return cwd == project or (recursive and project in cwd.parents)
    for path in ROOT.glob('*.json'):
        try:
            sid = session_id(path.stem)
        except ValueError:
            continue
        meta = json.loads(path.read_text())
        if belongs(meta['project']):
            found[sid] = {'project': meta['project'], 'transcripts': []}
    for path in TRANSCRIPTS.glob('*/*.jsonl'):
        try:
            sid = session_id(path.stem)
        except ValueError:
            continue
        for record in records(path):
            if record.get('cwd'):
                if belongs(record['cwd']):
                    if sid in found and Path(found[sid]['project']).resolve() != Path(record['cwd']).resolve():
                        raise ValueError('Session project does not match its transcript.')
                    found.setdefault(sid, {'project': record['cwd'], 'transcripts': []})['transcripts'].append(path)
                break
    return found


def deletion_item(path):
    info = path.lstat()
    if path.is_symlink() or path.resolve() != path or info.st_uid != os.getuid():
        raise ValueError('Unsafe deletion target')
    return {'path': str(path), 'device': info.st_dev, 'inode': info.st_ino, 'directory': path.is_dir()}


def prepare_deletion(request):
    mode = request.get('mode')
    if mode not in ('chat', 'project'):
        raise ValueError('Unknown deletion type')
    with lifecycle_lock():
        project = deletion_project(request['project']) if mode == 'project' else project_path(request['project'])
        inventory = deletion_inventory(project, recursive=mode == 'project')
        if mode == 'chat':
            sid = session_id(request['id'])
            if sid not in inventory:
                raise ValueError('Chat does not belong to this project')
            inventory = {sid: inventory[sid]}
        items = []
        for sid, entry in inventory.items():
            meta_path = ROOT/(sid+'.json')
            if meta_path.exists() and metadata(sid)['project'] != entry['project']:
                raise ValueError('Session belongs to another project')
            paths = [ROOT/(sid+suffix) for suffix in ('.json', '.settings.json', '.status')]
            paths += [ROOT/'attachments'/sid]
            for path in entry['transcripts']:
                if path.parent.is_symlink():
                    raise ValueError('Unsafe transcript directory')
                paths += [path, path.parent/sid]
            for path in paths:
                if path.exists() or path.is_symlink():
                    items.append(deletion_item(path))
        if mode == 'project':
            items.append(deletion_item(project))
        plan_id = str(uuid.uuid4())
        plan = {'id': plan_id, 'mode': mode, 'project': str(project), 'sessions': sorted(inventory),
                'items': items, 'phase': 'prepared', 'created': time.time()}
        atomic_json(private_dir(ROOT/'deletions')/(plan_id+'.json'), plan)
        return {'id': plan_id, 'path': str(project), 'count': len(inventory)}


def commit_deletion(request):
    if request.get('confirmation') != 'delete':
        raise ValueError('Type delete to confirm permanent deletion')
    plan_file = ROOT/'deletions'/(session_id(request['id'])+'.json')
    with lifecycle_lock():
        plan = json.loads(plan_file.read_text())
        if plan['phase'] == 'done':
            return {'phase': 'done'}  # Lost SSH replies can be retried safely.
        if time.time() - plan['created'] > 900 and plan['phase'] == 'prepared':
            raise ValueError('Deletion preview expired. Open it again.')
        current = deletion_inventory(Path(plan['project']), recursive=plan['mode'] == 'project')
        if plan['mode'] == 'project' and set(current) - set(plan['sessions']):
            raise ValueError('Project chats changed. Review the deletion again.')
        if plan['phase'] == 'prepared' and not set(plan['sessions']).issubset(current):
            raise ValueError('Chat ownership changed. Review the deletion again.')
        # Validate the entire plan before stopping any CLI or removing any data.
        for item in plan['items']:
            path = Path(item['path'])
            if not path.exists() and not path.is_symlink():
                continue
            current = deletion_item(path)
            if any(current[key] != item[key] for key in ('device', 'inode', 'directory')):
                raise ValueError('A deletion target changed. Review the deletion again.')
        if plan['mode'] == 'project' and Path(plan['project']).exists():
            deletion_project(plan['project'])
        plan['phase'] = 'deleting'
        atomic_json(plan_file, plan)
        for sid in plan['sessions']:
            # Tombstones prevent late hooks and stale preview windows from
            # recreating a deleted conversation's state.
            (private_dir(ROOT/'deleted')/sid).touch(mode=0o600, exist_ok=True)
            if alive(sid):
                owner = Path(metadata(sid)['project']).resolve()
                project = Path(plan['project'])
                if owner != project and not (plan['mode'] == 'project' and project in owner.parents):
                    raise ValueError('Session belongs to another project')
                tmux('kill-session', '-t', target(sid))
            remove_permission_state(sid)
        for item in plan['items']:
            path = Path(item['path'])
            if not path.exists() and not path.is_symlink():
                continue
            if item['directory']:
                shutil.rmtree(path)  # FD-based implementation, never follows symlinks.
            else:
                path.unlink()
        plan['phase'] = 'done'
        atomic_json(plan_file, plan)
        return {'phase': 'done'}


def dispatch(request):
    op = request["op"]
    private_dir(ROOT)
    if op == "deletion_prepare":
        return prepare_deletion(request)
    if op == "deletion_commit":
        return commit_deletion(request)
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
    if op == "permission_decide":
        return decide_permission(request)
    if op == "permission_handoff":
        return handoff_permissions(request)
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
        approvals = []
        if live and managed:
            # Only the new UI opts in; older clients must retain terminal approval.
            if request.get("approvalUI") is True:
                with lifecycle_lock():
                    if not (ROOT / "deleted" / sid).exists():
                        atomic_json(ROOT / (sid + ".ui.json"), {"time": time.time()})
                        approvals = pending_permissions(sid, project)
        return {"messages": messages(transcript(sid, project)), "phase": "permission" if approvals else read_status(sid) if live and managed else "offline", "live": live and managed, "approvals": approvals}
    if op == "upload":
        with lifecycle_lock():
            return upload(sid, request["name"], request["data"])
    if op == "send":
        return send(sid, request["text"], request.get("approvalUI") is True)
    if op == "interrupt":
        metadata(sid)
        if alive(sid):
            tmux("send-keys", "-t", target(sid) + ":", "Escape")
        return {"interrupted": True}
    raise ValueError("Unknown operation")


def hook(sid, event):
    if (ROOT/"deleted"/sid).exists():
        return
    name = event.get("hook_event_name")
    phase = {"SessionStart": "ready", "UserPromptSubmit": "busy", "Stop": "ready",
             "PermissionRequest": "permission", "SessionEnd": "offline"}.get(name)
    if name == "Notification" and event.get("notification_type") == "permission_prompt":
        phase = "permission"
    # idle_prompt also fires for questions/pickers: it must not enable the composer.
    if phase:
        private_dir(ROOT)
        set_status(sid, phase)
    if name == "PermissionRequest":
        return request_permission(sid, event)


def main():
    os.umask(0o077)
    if len(sys.argv) == 4 and sys.argv[1] == "--project-job":
        project_worker(session_id(sys.argv[2]), int(sys.argv[3]))
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--hook":
        try:
            result = hook(session_id(sys.argv[2]), json.load(sys.stdin))
            if result is not None:
                print(json.dumps(result), flush=True)
        except (OSError, ValueError, KeyError, TypeError):
            pass  # No decision on failure: Claude presents its normal terminal UI.
        return
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
