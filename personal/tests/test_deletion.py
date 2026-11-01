import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location('deletion_bridge', Path(__file__).parents[1]/'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class DeletionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()/'home'
        self.project = self.home/'projects'/'demo'
        self.project.mkdir(parents=True)
        self.root = self.home/'.local/share/cmux-personal'
        self.transcripts = self.home/'.claude/projects'
        self.transcripts.mkdir(parents=True)
        for patcher in (patch.object(bridge, 'ROOT', self.root), patch.object(bridge, 'TRANSCRIPTS', self.transcripts),
                        patch.object(bridge.Path, 'home', return_value=self.home), patch.object(bridge, 'alive', return_value=False)):
            patcher.start()
            self.addCleanup(patcher.stop)
        bridge.private_dir(self.root)
        self.sid = self.make_chat(self.project)
        self.keep = self.project/'keep.txt'
        self.keep.write_text('project data')

    def make_chat(self, project):
        sid = str(uuid.uuid4())
        bridge.atomic_json(self.root/(sid+'.json'), {'id': sid, 'project': str(project)})
        folder = self.transcripts/'fixture'
        folder.mkdir(exist_ok=True)
        (folder/(sid+'.jsonl')).write_text(json.dumps({'type':'user','uuid':'message','cwd':str(project),'message':{'content':'hello'}})+'\n')
        (folder/sid).mkdir()
        (folder/sid/'subagent.jsonl').write_text('associated history')
        bridge.private_dir(self.root/'attachments'/sid)
        (self.root/'attachments'/sid/'file.txt').write_text('attachment')
        return sid

    def prepare(self, mode='chat', project=None):
        return bridge.dispatch({'op':'deletion_prepare','mode':mode,'id':self.sid,'project':str(project or self.project)})

    def commit(self, plan, confirmation='delete'):
        return bridge.dispatch({'op':'deletion_commit','id':plan['id'],'confirmation':confirmation})

    def test_chat_delete_requires_confirmation_and_preserves_repository_and_other_chats(self):
        other = self.make_chat(self.project)
        plan = self.prepare()
        with self.assertRaises(ValueError): self.commit(plan, '')
        self.assertTrue((self.root/(self.sid+'.json')).exists())
        self.assertEqual(self.commit(plan)['phase'], 'done')
        self.assertFalse((self.root/(self.sid+'.json')).exists())
        self.assertFalse((self.transcripts/'fixture'/(self.sid+'.jsonl')).exists())
        self.assertFalse((self.transcripts/'fixture'/self.sid).exists())
        self.assertFalse((self.root/'attachments'/self.sid).exists())
        self.assertTrue(self.keep.exists())
        self.assertEqual([s['id'] for s in bridge.list_sessions(self.project)], [other])
        self.assertEqual(self.commit(plan)['phase'], 'done')
        bridge.hook(self.sid, {'hook_event_name':'Stop'})
        self.assertFalse((self.root/(self.sid+'.status')).exists())
        with self.assertRaises(ValueError): bridge.start(self.sid, self.project, False)

    def test_project_delete_removes_nested_chats_and_files_without_following_symlinks(self):
        nested = self.project/'nested'; nested.mkdir()
        child = self.make_chat(nested)
        sibling = self.home/'projects'/'sibling'; sibling.mkdir()
        other = self.make_chat(sibling)
        (sibling/'keep').write_text('safe')
        (self.project/'external').symlink_to(sibling, target_is_directory=True)
        plan = self.prepare('project')
        self.assertEqual(plan['count'], 2)
        self.commit(plan)
        self.assertFalse(self.project.exists())
        self.assertFalse((self.root/(child+'.json')).exists())
        self.assertTrue((sibling/'keep').exists())
        self.assertTrue((self.root/(other+'.json')).exists())

    def test_protected_roots_symlinks_and_wrong_project_are_rejected_before_mutation(self):
        (self.home/'.ssh').mkdir()
        link = self.home/'projects'/'link'; link.symlink_to(self.project)
        for folder in (self.home, self.home/'projects', self.home/'.ssh', link, Path('/')):
            with self.subTest(folder=folder), self.assertRaises(ValueError): self.prepare('project', folder)
        other = self.home/'projects'/'other'; other.mkdir()
        with self.assertRaises(ValueError): self.prepare('chat', other)
        self.assertTrue(self.keep.exists())

    def test_changed_target_or_new_chat_requires_a_new_preview(self):
        plan = self.prepare('project')
        self.make_chat(self.project)
        with self.assertRaises(ValueError): self.commit(plan)
        plan = self.prepare('project')
        moved = self.project.with_name('original'); self.project.rename(moved)
        self.project.mkdir()
        (self.project/'new-data').write_text('new')
        with self.assertRaises(ValueError): self.commit(plan)
        self.assertTrue((moved/'keep.txt').exists())
        self.assertTrue((self.project/'new-data').exists())

    def test_live_session_stops_only_the_exact_confirmed_target(self):
        plan = self.prepare()
        with patch.object(bridge, 'alive', return_value=True), patch.object(bridge, 'tmux') as tmux:
            self.commit(plan)
            tmux.assert_called_once_with('kill-session', '-t', '=cmp-'+self.sid)

    def test_symlinked_attachment_parent_is_rejected(self):
        original = self.root/'attachments'
        moved = self.home/'outside'; original.rename(moved)
        original.symlink_to(moved)
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue((moved/self.sid/'file.txt').exists())

    def test_large_history_is_not_silently_truncated(self):
        for _ in range(101): self.make_chat(self.project)
        self.assertEqual(len(bridge.list_sessions(self.project)), 102)
