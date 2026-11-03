import base64
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).parents[1] / "bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name).resolve()
        self.root = base / "state"
        self.project = base / "project 'with spaces'"
        self.project.mkdir()
        self.transcripts = base / "transcripts"
        self.transcripts.mkdir()
        self.sid = str(uuid.uuid4())
        self.patchers = [patch.object(bridge, "ROOT", self.root), patch.object(bridge, "TRANSCRIPTS", self.transcripts)]
        for p in self.patchers:
            p.start()
            self.addCleanup(p.stop)
        bridge.private_dir(self.root)
        bridge.atomic_json(self.root / (self.sid + ".json"), {"id": self.sid, "project": str(self.project)})

    def fixture(self, entries):
        folder = self.transcripts / "project"
        folder.mkdir(exist_ok=True)
        path = folder / (self.sid + ".jsonl")
        path.write_text("\n".join(json.dumps(e) for e in entries) + '\n{"unfinished":')
        return path

    def test_real_transcript_shapes_and_partial_tail(self):
        path = self.fixture([
            {"type": "user", "uuid": "u", "cwd": str(self.project), "message": {"content": "Hello"}},
            {"type": "assistant", "uuid": "a", "message": {"content": [{"type": "text", "text": "World"}, {"type": "tool_use", "name": "Read", "input": {"secret": "do-not-display"}}]}},
            {"type": "assistant", "uuid": "a", "message": {"content": "duplicate"}},
            {"type": "user", "uuid": "tool-result", "message": {"content": [{"type": "tool_result", "content": "secret-output"}]}},
            {"type": "user", "isMeta": True, "message": {"content": "internal"}}
        ])
        self.assertEqual([m["text"] for m in bridge.messages(path)], ["Hello", "World", "Read"])
        self.assertEqual(bridge.transcript(self.sid, self.project), path)
        self.assertIsNone(bridge.transcript(self.sid, self.root))
        self.assertEqual(bridge.list_sessions(self.project)[0]["title"], "Hello")

    def test_attachment_roundtrip_permissions_and_unique_names(self):
        data = b"attachment\x00payload"
        one = Path(bridge.upload(self.sid, "photo '1'.png", base64.b64encode(data).decode())["path"])
        two = Path(bridge.upload(self.sid, "photo '1'.png", base64.b64encode(data).decode())["path"])
        self.assertEqual(one.read_bytes(), data)
        self.assertNotEqual(one, two)
        self.assertEqual(stat.S_IMODE(one.stat().st_mode), 0o600)

    def test_reject_traversal_control_characters_and_invalid_base64(self):
        for name in ("../key", "/tmp/key", "..", "a\nb", "a\\b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                bridge.upload(self.sid, name, "eA==")
        with self.assertRaises(ValueError):
            bridge.upload(self.sid, "test", "!!!")
        with self.assertRaises(ValueError):
            bridge.send(self.sid, "\x1b[201~whoami")
        with self.assertRaises(ValueError):
            bridge.session_id("abc; touch /tmp/pwned")

    def test_permission_and_offline_states_never_receive_keys(self):
        for phase in ("starting", "permission", "busy", "attention", "offline"):
            bridge.set_status(self.sid, phase)
            with patch.object(bridge, "alive", return_value=True), patch.object(bridge, "tmux") as run:
                with self.assertRaises(ValueError):
                    bridge.send(self.sid, "yes")
                run.assert_not_called()

    def test_ready_send_is_reserved_and_delivered_as_bracketed_paste(self):
        bridge.set_status(self.sid, "ready")
        text = "line one\nline 'two'; $(not-a-shell-command)"
        with patch.object(bridge, "alive", return_value=True), patch.object(bridge, "tmux") as run:
            bridge.send(self.sid, text)
            self.assertEqual(run.call_args_list[0].kwargs["input"], text.encode())
            self.assertIn("-p", run.call_args_list[1].args)
            self.assertEqual(run.call_args_list[2].args[-1], "Enter")
            with self.assertRaises(ValueError):
                bridge.send(self.sid, text)
        self.assertEqual(bridge.read_status(self.sid), "busy")

    def test_usage_opens_cli_screen_instead_of_waiting_for_assistant_reply(self):
        bridge.set_status(self.sid, "ready")
        with patch.object(bridge, "alive", return_value=True), patch.object(bridge, "tmux"):
            result = bridge.send(self.sid, "/usage")
        self.assertEqual(bridge.read_status(self.sid), "console", "A CLI screen never emits a normal assistant Stop event")
        self.assertEqual(result.get("consoleCommand"), "/usage")

    def local_command_fixture(self, timestamp, command='/effort', args=''):
        stamp = datetime.fromtimestamp(timestamp, timezone.utc).isoformat()
        return self.fixture([
            {'type': 'user', 'uuid': 'command', 'cwd': str(self.project), 'timestamp': stamp,
             'message': {'content': f'<command-name>{command}</command-name>\n<command-message>{command[1:]}</command-message>\n<command-args>{args}</command-args>'}},
            {'type': 'user', 'uuid': 'output', 'timestamp': stamp,
             'message': {'content': '<local-command-stdout>Effort updated.</local-command-stdout>'}},
        ])

    def read_with_prompt(self, screen=None, cursor='2,2,1'):
        if screen is None:
            screen = 'old output\n──────────────── ultracode ─\n❯\u00a0\n────────────────\n  ? for shortcuts\n'
        def capture(*args, **kwargs):
            self.assertIn(args[0], ('capture-pane', 'display-message'), 'Status reconciliation must never send keys')
            return subprocess.CompletedProcess(args, 0, (screen if args[0] == 'capture-pane' else cursor).encode(), b'')
        with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux', side_effect=capture):
            return bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project)})

    def test_effort_is_a_local_command_and_submit_hook_preserves_that_state(self):
        bridge.set_status(self.sid, 'ready')
        with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux'):
            result = bridge.send(self.sid, '/effort high')
        self.assertEqual(result['phase'], 'console')
        self.assertEqual(result['consoleCommand'], '/effort')
        bridge.hook(self.sid, {'hook_event_name': 'UserPromptSubmit', 'prompt': '/effort high'})
        self.assertEqual(bridge.read_status(self.sid), 'console')

    def test_finished_effort_recovers_stale_busy_without_closing_terminal(self):
        with patch.object(bridge.time, 'time', return_value=100):
            bridge.set_status(self.sid, 'busy')
        self.local_command_fixture(134)
        reply = self.read_with_prompt()
        self.assertEqual(reply['phase'], 'ready', 'A completed local command has no assistant Stop hook')
        self.assertEqual([(m['role'], m['text']) for m in reply['messages']],
                         [('user', '/effort'), ('system', 'Effort updated.')], 'Command acknowledgement and output must not expose CLI markup')

    def test_completed_console_command_returns_to_chat_while_panel_stays_open(self):
        with patch.object(bridge.time, 'time', return_value=100), patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux'):
            bridge.set_status(self.sid, 'ready')
            bridge.send(self.sid, '/model')
        self.local_command_fixture(101, '/model', 'example-model')
        self.assertEqual(self.read_with_prompt()['phase'], 'ready')

    def test_old_local_output_never_clears_a_new_turn_or_protected_phase(self):
        self.local_command_fixture(100)
        for phase in ('busy', 'permission', 'attention', 'offline', 'starting'):
            with self.subTest(phase=phase), patch.object(bridge.time, 'time', return_value=101):
                bridge.set_status(self.sid, phase)
                self.assertEqual(self.read_with_prompt()['phase'], phase)
        with patch.object(bridge.time, 'time', return_value=99):
            bridge.set_status(self.sid, 'busy')
        path = self.local_command_fixture(100)
        with path.open('a') as stream:
            stream.write('\n' + json.dumps({'type': 'user', 'message': {'content': 'A new task'}}) + '\n')
        self.assertEqual(self.read_with_prompt()['phase'], 'busy')

    def test_completion_does_not_override_actual_work_draft_or_permission(self):
        self.local_command_fixture(101)
        screen = 'old output\n──────────────── high ─\n❯\u00a0\n────────────────\n'
        for phase, changed, cursor in [
            ('busy', screen + 'esc to interrupt', '2,2,1'),
            ('busy', screen.replace('❯\u00a0', '❯ draft'), '2,2,1'),
            ('busy', screen, '2,2,0'),
            ('permission', screen, '2,2,1'),
        ]:
            with self.subTest(phase=phase, cursor=cursor), patch.object(bridge.time, 'time', return_value=100):
                bridge.set_status(self.sid, phase)
                self.assertEqual(self.read_with_prompt(changed, cursor)['phase'], phase)

    def test_idle_prompt_uses_current_footer_not_old_interrupt_text(self):
        screen = 'old esc to interrupt\n──────────────── ultracode ─\n❯\u00a0\n────────────────\n  ? for shortcuts\n'
        self.assertTrue(bridge.console_prompt_is_idle(screen, '2,2,1'))
        self.assertFalse(bridge.console_prompt_is_idle(screen + 'esc to interrupt', '2,2,1'))

    def test_console_submit_keeps_active_work_and_permissions_protected(self):
        for phase in ('busy', 'permission', 'attention'):
            bridge.set_status(self.sid, phase)
            before = bridge.status_snapshot(self.sid)
            bridge.hook(self.sid, {'hook_event_name': 'UserPromptSubmit', 'prompt': '/effort high'})
            self.assertEqual(bridge.status_snapshot(self.sid), before)
        bridge.set_status(self.sid, 'ready')
        with patch.object(bridge.time, 'time', return_value=100):
            bridge.hook(self.sid, {'hook_event_name': 'UserPromptSubmit', 'prompt': '/effort high'})
        self.local_command_fixture(101)
        with patch.object(bridge.time, 'time', return_value=102):
            bridge.hook(self.sid, {'hook_event_name': 'UserPromptSubmit', 'prompt': '/effort high'})
        self.assertEqual(self.read_with_prompt()['phase'], 'console', 'Previous output cannot complete a repeated command')

    def test_local_completion_cannot_overwrite_newer_status_during_capture(self):
        with patch.object(bridge.time, 'time', return_value=100):
            bridge.set_status(self.sid, 'busy')
        self.local_command_fixture(101)
        def capture(*args, **kwargs):
            bridge.set_status(self.sid, 'permission')
            value = 'output\n────────────────\n❯\u00a0\n────────────────\n' if args[0] == 'capture-pane' else '2,2,1'
            return subprocess.CompletedProcess(args, 0, value.encode(), b'')
        with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux', side_effect=capture):
            reply = bridge.dispatch({'op': 'read', 'id': self.sid, 'project': str(self.project)})
        self.assertEqual(reply['phase'], 'permission')

    def test_incomplete_or_custom_command_records_do_not_release_busy(self):
        with patch.object(bridge.time, 'time', return_value=100):
            bridge.set_status(self.sid, 'busy')
        self.local_command_fixture(101, '/my-skill')
        self.assertEqual(self.read_with_prompt()['phase'], 'busy')
        path = self.local_command_fixture(101)
        entries = list(bridge.records(path))
        entries[-1].pop('timestamp')
        self.fixture(entries)
        self.assertEqual(self.read_with_prompt()['phase'], 'busy')
        self.fixture(entries[:1])
        self.assertEqual(self.read_with_prompt()['phase'], 'busy')

    def test_console_return_checks_actual_main_prompt_without_sending_keys(self):
        screen = "old output\n────────────────\n❯\u00a0\n────────────────\n  ? for shortcuts\n"
        def capture(*args, **kwargs):
            return subprocess.CompletedProcess(args, 0, (screen if args[0] == 'capture-pane' else '2,2,1').encode(), b'')
        with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux'):
            bridge.set_status(self.sid, 'ready'); bridge.send(self.sid, '/usage')
        with patch.object(bridge, 'tmux', side_effect=capture) as run:
            bridge.reconcile_console(self.sid)
            self.assertEqual(bridge.read_status(self.sid), 'console', 'No readiness guess before returning from the screen')
            run.assert_not_called()
            bridge.reconcile_console(self.sid, returning=True)
            self.assertEqual(bridge.read_status(self.sid), 'ready')
            self.assertTrue(all(call.args[0] in ('capture-pane', 'display-message') for call in run.call_args_list))
        for changed, cursor in [(screen.replace('❯\u00a0', '❯ 1. Yes'), '2,2,1'), (screen.replace('❯\u00a0', '❯ draft'), '2,2,1'), (screen, '2,2,0'), (screen+'esc to interrupt', '2,2,1'), ('new unknown layout', '0,0,1')]:
            self.assertFalse(bridge.console_prompt_is_idle(changed, cursor), 'Never treat a permission, draft, busy prompt or unknown layout as ready')

    def test_new_turn_or_permission_cannot_be_reset_by_console_return(self):
        for phase in ['busy', 'permission', 'offline']:
            bridge.set_status(self.sid, phase)
            with patch.object(bridge, 'tmux') as run:
                bridge.reconcile_console(self.sid, returning=True)
                run.assert_not_called()
            self.assertEqual(bridge.read_status(self.sid), phase)
        for prompt in ['/my-skill inspect this', '/compact', '/review', 'Explain /usage', '/usage\nExplain this']:
            bridge.set_status(self.sid, 'ready')
            with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux'):
                self.assertIsNone(bridge.send(self.sid, prompt).get('consoleCommand'))
            self.assertEqual(bridge.read_status(self.sid), 'busy')
        with patch.object(bridge, 'alive', return_value=True), self.assertRaises(ValueError):
            bridge.dispatch({'op': 'console_return', 'id': self.sid, 'project': str(self.root)})

    def test_uncertain_send_requires_terminal_and_never_auto_retries(self):
        bridge.set_status(self.sid, "ready")
        with patch.object(bridge, "alive", return_value=True), patch.object(bridge, "tmux", side_effect=RuntimeError("failed")) as run:
            with self.assertRaises(RuntimeError):
                bridge.send(self.sid, "hello")
            self.assertEqual(run.call_count, 1)
        self.assertEqual(bridge.read_status(self.sid), "attention")

    def test_start_uses_interactive_cli_and_no_shell_after_exit(self):
        with patch.object(bridge, "alive", return_value=False), patch.object(bridge, "executable", return_value="/home/developer/.local/bin/claude"), patch.object(bridge, "tmux") as run:
            bridge.start(self.sid, self.project, False)
            args = run.call_args.args
            command = args[-1]
            self.assertTrue(command.startswith("export PATH="))
            self.assertIn("/.local/bin:$PATH; exec ", command)
            self.assertIn("--session-id", command)
            self.assertNotIn("--print", command)
            self.assertNotIn("stream-json", command)
            self.assertNotIn("skip-permissions", command)
            self.assertEqual(args[args.index("-c") + 1], str(self.project))
        settings = json.loads((self.root / (self.sid + ".settings.json")).read_text())
        self.assertIn("PermissionRequest", settings["hooks"])

    def test_hook_does_not_treat_idle_question_as_ready(self):
        bridge.hook(self.sid, {"hook_event_name": "PermissionRequest"})
        bridge.hook(self.sid, {"hook_event_name": "Notification", "notification_type": "idle_prompt"})
        self.assertEqual(bridge.read_status(self.sid), "permission")
        bridge.hook(self.sid, {"hook_event_name": "Stop"})
        self.assertEqual(bridge.read_status(self.sid), "ready")

    def test_existing_session_rejects_different_project(self):
        with patch.object(bridge, "alive", return_value=True):
            with self.assertRaises(ValueError):
                bridge.start(self.sid, self.root, False)


if __name__ == "__main__":
    unittest.main()
