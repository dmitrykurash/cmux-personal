import importlib.util
import json
from pathlib import Path
import socket
import stat
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location('permission_bridge', Path(__file__).parents[1] / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class PermissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ccp-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / 's'
        self.project = Path(self.temp.name).resolve() / 'project'
        self.project.mkdir()
        self.sid = str(uuid.uuid4())
        for p in [patch.object(bridge, 'ROOT', self.root), patch.object(bridge, 'TRANSCRIPTS', self.root / 'transcripts'), patch.object(bridge, 'alive', return_value=True)]:
            p.start(); self.addCleanup(p.stop)
        bridge.private_dir(self.root)
        bridge.atomic_json(self.root / (self.sid + '.json'), {'id': self.sid, 'project': str(self.project)})
        self.renew()
        self.event = {'hook_event_name': 'PermissionRequest', 'session_id': self.sid, 'cwd': str(self.project), 'tool_name': 'Bash', 'tool_input': {'command': "printf '%s' 'quoted; $(literal)'", 'description': 'Check the environment'}}

    def renew(self):
        bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project), 'approvalUI': True})

    def launch(self, event=None):
        ready = threading.Event()
        result = []
        original = bridge.atomic_json
        def publish(path, value):
            original(path, value)
            if path.parent.name == 'p': ready.set()
        def run():
            try: result.append(bridge.hook(self.sid, event or self.event))
            except BaseException as exc: result.append(exc); ready.set()
        with patch.object(bridge, 'atomic_json', side_effect=publish):
            thread = threading.Thread(target=run, daemon=True)
            thread.start()
            self.assertTrue(ready.wait(3), 'Hook must publish before waiting')
        def cleanup():
            if thread.is_alive():
                for item in bridge.pending_permissions(self.sid, self.project):
                    try: self.decide(item['id'], 'terminal')
                    except (OSError, ValueError): pass
            thread.join(3)
        self.addCleanup(cleanup)
        if result and isinstance(result[0], BaseException): raise result[0]
        request = bridge.pending_permissions(self.sid, self.project)[-1]
        return thread, result, request

    def decide(self, rid, decision='allow', **changes):
        request = {'op': 'permission_decide', 'id': self.sid, 'project': str(self.project), 'approvalID': rid, 'decision': decision}
        request.update(changes)
        return bridge.dispatch(request)

    def test_allow_once_returns_exact_hook_decision_without_keys_or_rules(self):
        thread, output, request = self.launch()
        self.assertEqual(json.loads(request['detail']), self.event['tool_input'])
        path, sock = bridge.permission_paths(request['id'])
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(sock.stat().st_mode), 0o600)
        with patch.object(bridge, 'tmux') as terminal:
            self.decide(request['id'])
            terminal.assert_not_called()
        thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(output, [{'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}])
        self.assertEqual(bridge.read_status(self.sid), 'busy')
        self.assertFalse(path.exists()); self.assertFalse(sock.exists())
        with self.assertRaises(ValueError): self.decide(request['id'])

    def test_deny_and_terminal_handoff(self):
        for decision in ['deny', 'terminal']:
            with self.subTest(decision=decision):
                thread, output, request = self.launch()
                self.decide(request['id'], decision)
                thread.join(3)
                if decision == 'terminal': self.assertEqual(output, [None])
                else: self.assertEqual(output[0]['hookSpecificOutput']['decision']['behavior'], 'deny')
                self.assertEqual(bridge.pending_permissions(self.sid, self.project), [])

    def test_stale_ids_wrong_project_session_and_invalid_decision_cannot_approve(self):
        thread, output, request = self.launch()
        for changes in [{'approvalID': str(uuid.uuid4())}, {'id': str(uuid.uuid4())}, {'project': str(self.project.parent)}, {'decision': 'always'}]:
            with self.subTest(changes=changes), self.assertRaises((ValueError, FileNotFoundError)):
                self.decide(request['id'], **changes)
        self.assertTrue(thread.is_alive()); self.assertEqual(output, [])
        self.decide(request['id'], 'deny'); thread.join(3)
        second, output2, new = self.launch()
        with self.assertRaises(ValueError): self.decide(request['id'])
        self.assertEqual(output2, [])
        self.decide(new['id']); second.join(3)
        self.assertEqual(output2[0]['hookSpecificOutput']['decision']['behavior'], 'allow')

    def test_no_ui_lease_questions_and_oversized_inputs_fall_back_without_decision(self):
        for change in [{'tool_name': 'AskUserQuestion'}, {'tool_name': 'ExitPlanMode'}, {'session_id': str(uuid.uuid4())}, {'tool_input': {'command': 'x' * (129 * 1024)}}]:
            self.assertIsNone(bridge.hook(self.sid, {**self.event, **change}))
        (self.root / (self.sid + '.ui.json')).unlink()
        self.assertIsNone(bridge.hook(self.sid, self.event))
        bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project)})
        self.assertIsNone(bridge.hook(self.sid, self.event), 'Older UI must not enable hooks that wait')

    def test_timeout_never_approves(self):
        with patch.object(bridge, 'PERMISSION_SECONDS', 0.1):
            thread, output, request = self.launch()
            thread.join(3)
        self.assertEqual(output, [None])
        with self.assertRaises(ValueError): self.decide(request['id'])
        self.assertEqual(bridge.pending_permissions(self.sid, self.project), [])

    def test_disconnect_invalidates_pending_request(self):
        thread, output, request = self.launch()
        _, sock = bridge.permission_paths(request['id'])
        bridge.atomic_json(self.root / (self.sid + '.ui.json'), {'time': 0})
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
            stream.connect(str(sock)); stream.sendall(b'{}\n')
        thread.join(3)
        self.assertEqual(output, [None])
        self.renew()
        with self.assertRaises(ValueError): self.decide(request['id'])

    def test_terminal_handoff_releases_unseen_request_and_send_reenables_ui(self):
        thread, output, request = self.launch()
        bridge.dispatch({'op': 'permission_handoff', 'id': self.sid, 'project': str(self.project)})
        thread.join(3)
        self.assertEqual(output, [None])
        self.assertIsNone(bridge.hook(self.sid, self.event), 'New requests during handoff must stay in the terminal')
        bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project), 'approvalUI': False})
        self.assertLess(bridge.ui_lease(self.sid), time.time())
        bridge.set_status(self.sid, 'ready')
        with patch.object(bridge, 'tmux'):
            bridge.dispatch({'op': 'send', 'id': self.sid, 'text': 'Next user message', 'approvalUI': True})
        self.assertGreater(bridge.ui_lease(self.sid), time.time())

    def test_read_scopes_permissions_and_deletion_revokes_them(self):
        thread, output, request = self.launch()
        read = bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project), 'approvalUI': True})
        self.assertEqual(read['phase'], 'permission')
        self.assertEqual([a['id'] for a in read['approvals']], [request['id']])
        bridge.private_dir(self.root / 'deleted').joinpath(self.sid).touch()
        with self.assertRaises(ValueError): self.decide(request['id'])
        _, sock = bridge.permission_paths(request['id'])
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
            stream.connect(str(sock)); stream.sendall(b'{}\n')
        thread.join(3)
        bridge.remove_permission_state(self.sid)
        self.assertEqual(output, [None]); self.assertFalse((self.root / (self.sid + '.ui.json')).exists())


if __name__ == '__main__': unittest.main()
