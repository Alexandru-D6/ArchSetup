#!/usr/bin/env python3
"""Settings persistence, conflict handling and production-process integration."""
import getpass
import grp
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
from render import ROLE, render

sys.path.insert(0, str(ROLE / 'files'))
import desktop_settings as settings


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='archsetup-settings-test-')
        self.addCleanup(self.directory.cleanup)
        self.profile = render(self.directory.name)

    def request(self, request):
        result = subprocess.run([sys.executable, str(self.profile / 'bin/desktop-settings')],
                                input=json.dumps(request) + '\n', capture_output=True, text=True, timeout=5)
        response = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0 if response['ok'] else 1, result.stderr)
        return response

    def apply(self, value):
        return settings.apply(self.profile, settings.snapshot(self.profile)['revision'],
                              {settings.POWER_FIELD: value})

    def test_defaults_and_overrides_survive_reapplying_defaults(self):
        before_preferences = (self.profile / 'preferences.json').read_bytes()
        before_state = (self.profile / 'state.json').read_bytes()
        first = settings.snapshot(self.profile)
        self.assertIs(first['values'][settings.POWER_FIELD], True)
        applied = self.apply(False)
        self.assertIs(applied['preferences']['lockPowerRequiresAuth'], False)
        self.assertNotEqual(first['revision'], applied['revision'])
        saved = json.loads((self.profile / 'settings.json').read_text())
        self.assertEqual(saved, {'schemaVersion': 1, 'revision': 1, 'general': {'lockPowerRequiresAuth': False}})
        self.assertEqual((self.profile / 'preferences.json').read_bytes(), before_preferences)
        self.assertEqual((self.profile / 'state.json').read_bytes(), before_state)
        self.assertEqual((self.profile / 'settings.json').stat().st_mode & 0o777, 0o600)
        render(self.profile, {'archsetup_desktop_lock_require_auth_for_power': True})
        self.assertIs(settings.snapshot(self.profile)['values'][settings.POWER_FIELD], False)

    def test_missing_settings_migrates_on_first_apply_and_noop_does_not_write(self):
        path = self.profile / 'settings.json'
        path.unlink()
        current = settings.snapshot(self.profile)
        self.assertFalse(path.exists())
        settings.apply(self.profile, current['revision'], {settings.POWER_FIELD: False})
        before = path.read_bytes(), path.stat().st_mtime_ns
        self.apply(False)
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)

    def test_invalid_changes_do_not_write(self):
        before = (self.profile / 'settings.json').read_bytes()
        current = settings.snapshot(self.profile)
        for changes in [{}, [], None, {'timezone': 'Europe/Madrid'},
                        {settings.POWER_FIELD: 'false'}, {settings.POWER_FIELD: 0},
                        {settings.POWER_FIELD: None}, {settings.POWER_FIELD: False, 'unknown': True}]:
            with self.subTest(changes=changes), self.assertRaises(settings.SettingsError):
                settings.apply(self.profile, current['revision'], changes)
            self.assertEqual((self.profile / 'settings.json').read_bytes(), before)

    def test_conflict_includes_current_snapshot_and_preserves_newer_values(self):
        original = settings.snapshot(self.profile)
        new = self.apply(False)
        with self.assertRaises(settings.SettingsError) as caught:
            settings.apply(self.profile, original['revision'], {settings.POWER_FIELD: True})
        self.assertEqual(caught.exception.code, 'conflict')
        self.assertEqual(caught.exception.snapshot['revision'], new['revision'])
        self.assertIs(settings.snapshot(self.profile)['values'][settings.POWER_FIELD], False)
        preferences = self.profile / 'preferences.json'
        defaults = json.loads(preferences.read_text())
        defaults['font'] = 'Another font'
        preferences.write_text(json.dumps(defaults))
        with self.assertRaises(settings.SettingsError):
            settings.apply(self.profile, new['revision'], {settings.POWER_FIELD: True})

    def test_concurrent_processes_serialize_writes(self):
        request = json.dumps({'operation': 'apply', 'revision': settings.snapshot(self.profile)['revision'],
                              'changes': {settings.POWER_FIELD: False}}) + '\n'
        command = [sys.executable, str(self.profile / 'bin/desktop-settings')]
        with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as first, \
             subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as second:
            first.stdin.write(request)
            first.stdin.flush()
            second.stdin.write(request)
            second.stdin.flush()
            responses = [json.loads(process.communicate(timeout=5)[0]) for process in [first, second]]
        self.assertEqual(sum(response['ok'] for response in responses), 1)
        self.assertEqual(next(response['code'] for response in responses if not response['ok']), 'conflict')
        self.assertEqual(json.loads((self.profile / 'settings.json').read_text())['revision'], 1)

    def test_failed_atomic_replace_preserves_old_file_and_cleans_staging(self):
        path = self.profile / 'settings.json'
        before = path.read_bytes()
        with patch.object(settings.os, 'replace', side_effect=OSError('Injected write failure')):
            with self.assertRaises(OSError):
                self.apply(False)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(list(self.profile.glob('.settings-*')), [])
        self.assertIs(self.apply(False)['values'][settings.POWER_FIELD], False)

    def test_invalid_native_configuration_prevents_commit(self):
        path = self.profile / 'hyprlock.conf'
        path.write_text('Missing the generated power section\n')
        before = (self.profile / 'settings.json').read_bytes()
        with self.assertRaises(settings.SettingsError):
            self.apply(False)
        self.assertEqual((self.profile / 'settings.json').read_bytes(), before)

    def test_malformed_overrides_fail_closed_and_are_never_replaced(self):
        path = self.profile / 'settings.json'
        for contents in ['not json', '[]', '{"schemaVersion":2,"revision":0,"general":{}}',
                         '{"schemaVersion":true,"revision":0,"general":{}}',
                         '{"schemaVersion":1,"revision":-1,"general":{}}',
                         '{"schemaVersion":1,"revision":0,"general":{"lockPowerRequiresAuth":"false"}}',
                         '{"schemaVersion":1,"revision":0,"general":{"lockPowerRequiresAuth":false,"lockPowerRequiresAuth":true}}',
                         '{"schemaVersion":1,"revision":0,"general":{},"other":NaN}']:
            with self.subTest(contents=contents):
                path.write_text(contents)
                self.assertIs(settings.effective_preferences(self.profile)['lockPowerRequiresAuth'], True)
                response = self.request({'operation': 'read'})
                self.assertIs(response['ok'], False)
                self.assertEqual(path.read_text(), contents)

    def test_native_configuration_and_helper_use_the_effective_policy(self):
        loader = importlib.machinery.SourceFileLoader('settings_test_visuals', str(ROLE / 'files/lock-visuals'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        visuals = importlib.util.module_from_spec(spec)
        loader.exec_module(visuals)
        visuals.ROOT = self.profile
        original = (self.profile / 'hyprlock.conf').read_text()
        for required in [False, True]:
            with self.subTest(required=required):
                self.apply(required)
                native = settings.native_lock_configuration(self.profile, original)
                self.assertIs(visuals.power_requires_auth(), required)
                for action in ['poweroff', 'reboot']:
                    self.assertEqual(native.count('click-' + action), 0 if required else 1)
                self.assertIn('pam:module = archsetup-hyprlock', native)
                self.assertEqual((self.profile / 'hyprlock.conf').read_text(), original)
        # The native defaults can also allow power; an interactive true removes it.
        render(self.profile, {'archsetup_desktop_lock_require_auth_for_power': False})
        self.assertNotIn('click-poweroff', settings.native_lock_configuration(
            self.profile, (self.profile / 'hyprlock.conf').read_text()))

    def test_backend_contract_is_structured_for_success_and_failures(self):
        current = self.request({'operation': 'read'})['snapshot']
        response = self.request({'operation': 'apply', 'revision': current['revision'],
                                 'changes': {settings.POWER_FIELD: False}})
        self.assertIs(response['snapshot']['values'][settings.POWER_FIELD], False)
        response = self.request({'operation': 'apply', 'revision': current['revision'],
                                 'changes': {settings.POWER_FIELD: True}})
        self.assertEqual(response['code'], 'conflict')
        self.assertEqual(self.request({'operation': 'unknown'})['code'], 'request')
        for request in ['not JSON', '[]', '{"operation":"read","operation":"apply"}']:
            result = subprocess.run([sys.executable, str(self.profile / 'bin/desktop-settings')],
                                    input=request + '\n', capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)['code'], 'request')

    def test_ansible_initializer_preserves_saved_settings_on_repeat_runs(self):
        executable = shutil.which('ansible-playbook') or str(Path(sys.executable).parent / 'ansible-playbook')
        if not Path(executable).is_file(): self.skipTest('ansible-playbook is required')
        path = self.profile / 'settings.json'
        self.apply(False)
        before = path.read_bytes(), path.stat().st_mtime_ns
        tasks = yaml.safe_load((ROLE / 'tasks/configure.yml').read_text())
        initializer = next(task for task in tasks if task['name'] == 'Initialize user-owned desktop settings')
        playbook = self.profile / 'settings-repeat.yml'
        playbook.write_text(yaml.safe_dump([{
            'hosts': 'localhost', 'gather_facts': False, 'become': False,
            'vars': {'desktop_root': str(self.profile), 'archsetup_desktop_user': getpass.getuser(),
                     'desktop_group': grp.getgrgid(os.getgid()).gr_name},
            'tasks': [initializer, initializer]}]))
        environment = dict(os.environ, ANSIBLE_HOME=str(self.profile / 'ansible-home'),
                           ANSIBLE_LOCAL_TEMP=str(self.profile / 'ansible-tmp'))
        result = subprocess.run([executable, '-i', 'localhost,', '-c', 'local', str(playbook)],
                                env=environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r'changed=0\s+unreachable=0\s+failed=0')
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)

    def test_quickshell_settings_processes_apply_observe_conflicts_and_recover(self):
        executable = shutil.which('qs')
        if executable is None: self.skipTest('Quickshell is required')
        fixture = self.profile / 'settings-validation'
        shutil.copytree(Path(__file__).parent / 'settings', fixture)
        shutil.copytree(self.profile / 'shell', fixture / 'components')
        shell = fixture / 'shell.qml'
        shell.write_text(shell.read_text().replace('"../../../roles/desktop/files/shell"', '"components"').replace(
            '"../../../roles/desktop/files/shared"', '"components/shared"'))
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           QT_QUICK_CONTROLS_STYLE='Basic', XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'),
                           XDG_CACHE_HOME=str(self.profile / 'cache'), XDG_STATE_HOME=str(self.profile / 'qs-state'))
        environment.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run([executable, '-p', str(fixture), '--no-color'], env=environment,
                                capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('ARCHSETUP_SETTINGS_FIXTURES_PASSED', output)
        for error in ['Failed to load configuration', 'TypeError', 'ReferenceError']:
            self.assertNotIn(error, output)


if __name__ == '__main__':
    unittest.main()
