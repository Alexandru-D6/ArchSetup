#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml

from render import render, ROLE

class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.profile = render(self.directory.name)
        loader = importlib.machinery.SourceFileLoader('actions', str(ROLE / 'files/desktop-action'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.actions = importlib.util.module_from_spec(spec)
        loader.exec_module(self.actions)
        self.actions.ROOT = self.profile

    def test_fresh_check_skips_services_not_created_by_package_preview(self):
        executable = shutil.which('ansible-playbook')
        if executable is None:
            sibling = Path(sys.executable).parent / 'ansible-playbook'
            if sibling.exists():
                executable = str(sibling)
        if executable is None:
            self.skipTest('ansible-playbook is required for the check-mode regression')
        tasks = []
        for filename in ['configure.yml', 'login.yml']:
            tasks.extend(task for task in yaml.safe_load((ROLE / 'tasks' / filename).read_text())
                         if 'ansible.builtin.systemd_service' in task)
        self.assertEqual(len(tasks), 3)
        playbook = Path(self.directory.name) / 'missing-services.yml'
        playbook.write_text(yaml.safe_dump([{
            'name': 'Fresh service preview regression',
            'hosts': 'localhost', 'gather_facts': False, 'become': False,
            'vars': {'ansible_facts': {'services': {}},
                     'archsetup_desktop_manage_network': True,
                     'desktop_bluetooth': {'stat': {'exists': True}}},
            'tasks': tasks,
        }]))
        environment = dict(os.environ, ANSIBLE_HOME=self.directory.name,
                           ANSIBLE_LOCAL_TEMP=str(Path(self.directory.name) / 'ansible-tmp'),
                           ANSIBLE_NOCOLOR='1')
        result = subprocess.run([executable, '-i', 'localhost,', '-c', 'local',
                                 '--check', str(playbook)], env=environment,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r'changed=0\s+unreachable=0\s+failed=0\s+skipped=3')

    def test_cli_boolean_strings_render_as_booleans(self):
        render(self.profile, {'archsetup_desktop_reduced_motion': 'false'})
        self.assertFalse(json.loads((self.profile / 'preferences.json').read_text())['reducedMotion'])
        self.assertIn('animations = { enabled = true }', (self.profile / 'hyprland.lua').read_text())
        render(self.profile, {'archsetup_desktop_reduced_motion': 'true'})
        self.assertTrue(json.loads((self.profile / 'preferences.json').read_text())['reducedMotion'])
        self.assertIn('animations = { enabled = false }', (self.profile / 'hyprland.lua').read_text())

    def test_all_shortcuts_unique_and_layout_switch_reserved(self):
        bindings = json.loads((self.profile / 'shortcuts.json').read_text())
        keys = [item['key'] for item in bindings]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertNotIn('SUPER + Space', keys)
        self.assertTrue(all(not item.get('locked') for item in bindings if 'action' in item))

    def test_rendered_lua_passes_real_compositor_parser(self):
        result = subprocess.run(['Hyprland', '--verify-config', '--config', str(self.profile / 'hyprland.lua')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('config ok', result.stdout)

    def test_clipboard_payload_is_stdin_not_shell(self):
        payload = b'$(touch /tmp/should-not-exist); `id`'
        with patch.object(self.actions, 'menu', return_value='42\tmalicious'), patch.object(self.actions, 'capture', return_value='42\tmalicious'), patch.object(self.actions, 'run') as run:
            run.return_value.stdout = payload
            self.actions.main('clipboard')
            self.assertEqual(run.call_args.args, ('wl-copy',))
            self.assertEqual(run.call_args.kwargs['input'], payload)
            self.assertTrue(all(not call.kwargs.get('shell') for call in run.call_args_list))

    def test_cancelled_screenshot_does_not_capture(self):
        with patch.object(self.actions.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '')), patch.object(self.actions, 'run') as run:
            self.actions.main('screenshot')
            run.assert_not_called()

    def test_power_action_requires_confirmation(self):
        for answer in [None, 'Cancel']:
            with patch.object(self.actions, 'menu', return_value=answer), patch.object(self.actions, 'run') as run:
                self.actions.main('poweroff')
                run.assert_not_called()

    def test_theme_preserves_wallpaper_and_managed_preferences(self):
        managed = (self.profile / 'preferences.json').read_bytes()
        (self.profile / 'state.json').write_text('{"wallpaper":"/tmp/picture.png"}')
        with patch.object(self.actions.subprocess, 'run'):
            self.actions.main('theme')
        state = json.loads((self.profile / 'state.json').read_text())
        self.assertTrue(state['light'])
        self.assertEqual(state['wallpaper'], '/tmp/picture.png')
        self.assertEqual((self.profile / 'preferences.json').read_bytes(), managed)

    def test_candidate_validator_rejects_invalid_lua(self):
        candidate = self.profile / 'candidate'
        candidate.write_text('error("invalid candidate")\n')
        result = subprocess.run([str(self.profile / 'bin/validate-config'), str(candidate)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        valid = subprocess.run([str(self.profile / 'bin/validate-config'), str(self.profile / 'hyprland.lua')], capture_output=True, text=True)
        self.assertEqual(valid.returncode, 0, valid.stdout + valid.stderr)

    def test_calculator_rejects_code_and_unbounded_exponents(self):
        self.assertEqual(self.actions.calculate('2 + 3 * (7 - 2)'), 17)
        for expression in ['__import__("os").system("id")', '2**1000000', 'True + 1', '[1,2]']:
            with self.assertRaises(ValueError): self.actions.calculate(expression)

    def test_deployed_sources_have_no_ai_providers(self):
        import re
        banned = re.compile(r'\b(ollama|gemini|openai|mistral|anthropic)\b|api[_-]?key|services/ai/', re.I)
        for path in self.profile.rglob('*'):
            if path.is_file(): self.assertIsNone(banned.search(path.read_text()), str(path))

if __name__ == '__main__':
    unittest.main()
