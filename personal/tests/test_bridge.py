import base64
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
