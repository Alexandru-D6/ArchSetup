#!/usr/bin/env python3
"""Settings persistence, conflict handling and production-process integration."""
import getpass
import fcntl
from datetime import datetime, timezone
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
        environment = patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': ''})
        environment.start()
        self.addCleanup(environment.stop)
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

    def change(self, changes):
        return settings.apply(self.profile, settings.snapshot(self.profile)['revision'], changes)

    def test_clock_positions_are_independent_persistent_and_validated(self):
        first = settings.snapshot(self.profile)['values']
        self.assertIsNone(first[settings.DESKTOP_FIELD])
        self.assertIsNone(first[settings.LOCK_FIELD])
        value = { 'x': 0.125, 'y': 1 }
        changed = self.change({settings.DESKTOP_FIELD: value})
        self.assertEqual(changed['values'][settings.DESKTOP_FIELD], value)
        self.assertIsNone(changed['values'][settings.LOCK_FIELD])
        self.change({settings.LOCK_FIELD: {'x': 1, 'y': 0}})
        self.change({settings.DESKTOP_FIELD: None})
        render(self.profile)
        saved = settings.snapshot(self.profile)['values']
        self.assertIsNone(saved[settings.DESKTOP_FIELD])
        self.assertEqual(saved[settings.LOCK_FIELD], {'x': 1, 'y': 0})
        before = (self.profile / 'settings.json').read_bytes()
        for invalid in [False, [], {}, {'x': 0}, {'x': True, 'y': 0}, {'x': float('nan'), 'y': 0},
                        {'x': -0.01, 'y': 0}, {'x': 0, 'y': 1.01}, {'x': 0, 'y': 0, 'z': 0}]:
            with self.subTest(invalid=invalid), self.assertRaises(settings.SettingsError):
                self.change({settings.DESKTOP_FIELD: invalid})
            self.assertEqual((self.profile / 'settings.json').read_bytes(), before)

    def test_timezone_preview_handles_dst_midnight_and_fractional_offsets(self):
        preview = settings.clock_snapshot('Asia/Kathmandu', datetime(2026, 10, 15, 18, 30, tzinfo=timezone.utc))
        self.assertEqual((preview['utcOffset'], preview['time'], preview['date']), ('UTC+05:45', '00:15', 'Friday, October 16'))
        before = settings.clock_snapshot('Europe/Madrid', datetime(2026, 10, 25, 0, 59, tzinfo=timezone.utc))
        after = settings.clock_snapshot('Europe/Madrid', datetime(2026, 10, 25, 1, 0, tzinfo=timezone.utc))
        self.assertEqual((before['time'], before['utcOffset']), ('02:59', 'UTC+02:00'))
        self.assertEqual((after['time'], after['utcOffset']), ('02:00', 'UTC+01:00'))
        negative = settings.clock_snapshot('America/St_Johns', datetime(2026, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(negative['utcOffset'], 'UTC−03:30')

    def test_timezone_uses_system_service_without_storing_a_duplicate(self):
        zone = ['Etc/UTC']
        def set_zone(value, interactive=True): zone[0] = value
        with patch.object(settings.system, 'timezone_name', side_effect=lambda: zone[0]), \
             patch.object(settings.system, 'set_timezone', side_effect=set_zone) as setter:
            result = self.change({settings.TIMEZONE_FIELD: 'Asia/Kathmandu'})
            setter.assert_called_once_with('Asia/Kathmandu')
            self.assertEqual(result['values'][settings.TIMEZONE_FIELD], 'Asia/Kathmandu')
            self.assertNotIn('timezone', json.loads((self.profile / 'settings.json').read_text())['general'])
            self.assertFalse((self.profile / '.settings-recovery.json').exists())
            revision = result['revision']
            zone[0] = 'Europe/Madrid'
            with self.assertRaises(settings.SettingsError) as caught:
                settings.apply(self.profile, revision, {settings.POWER_FIELD: False})
            self.assertEqual(caught.exception.code, 'conflict')

    def test_denied_timezone_change_keeps_saved_values_and_other_draft_fields(self):
        before = (self.profile / 'settings.json').read_bytes()
        with patch.object(settings.system, 'timezone_name', return_value='Etc/UTC'), \
             patch.object(settings.system, 'set_timezone', side_effect=RuntimeError('Authorization cancelled')):
            with self.assertRaises(settings.SettingsError) as caught:
                self.change({settings.TIMEZONE_FIELD: 'Europe/Madrid', settings.POWER_FIELD: False,
                             settings.DESKTOP_FIELD: {'x': 1, 'y': 1}})
        self.assertEqual(caught.exception.code, 'system')
        self.assertIn('cancelled', str(caught.exception))
        self.assertEqual((self.profile / 'settings.json').read_bytes(), before)
        self.assertFalse((self.profile / '.settings-recovery.json').exists())

    def test_keyboard_pairs_generate_native_validated_input_and_survive_sync(self):
        layouts = [{'layout': 'es', 'variant': ''}, {'layout': 'us', 'variant': 'altgr-intl'}]
        before = (self.profile / 'preferences.json').read_bytes()
        result = self.change({settings.LAYOUTS_FIELD: layouts})
        self.assertEqual(result['values'][settings.LAYOUTS_FIELD], layouts)
        self.assertEqual(result['preferences']['keyboardVariants'], ',altgr-intl')
        self.assertIn('kb_layout="es,us",kb_variant=",altgr-intl"', (self.profile / 'settings-input.lua').read_text())
        self.assertIn('ES', (self.profile / 'lock-identity.conf').read_text())
        self.assertEqual((self.profile / 'preferences.json').read_bytes(), before)
        self.assertFalse(settings.sync(self.profile))
        (self.profile / 'settings-input.lua').unlink()
        self.assertTrue(settings.sync(self.profile))
        self.assertFalse(settings.sync(self.profile))
        self.assertEqual(settings.snapshot(self.profile)['values'][settings.LAYOUTS_FIELD], layouts)

    def test_invalid_keyboard_pairs_never_write_generated_or_saved_files(self):
        before = (self.profile / 'settings.json').read_bytes()
        for invalid in [[], None, [{'layout': 'unknown', 'variant': ''}], [{'layout': 'us', 'variant': 'unknown'}],
                        [{'layout': 'es', 'variant': 'altgr-intl'}], [{'layout': 'us'}],
                        [{'layout': 'us', 'variant': ''}] * 2, [{'layout': 'us', 'variant': ''}] * 5]:
            with self.subTest(invalid=invalid), self.assertRaises(settings.SettingsError):
                self.change({settings.LAYOUTS_FIELD: invalid})
            self.assertEqual((self.profile / 'settings.json').read_bytes(), before)
            self.assertFalse((self.profile / 'settings-input.lua').exists())

    def test_keyboard_reload_failure_rolls_back_outputs_and_timezone(self):
        zone = ['Etc/UTC']
        old = {'layout': 'us,us', 'variant': 'euro,altgr-intl', 'file': '', 'keyboards': []}
        before = (self.profile / 'settings.json').read_bytes()
        def set_zone(value, interactive=True): zone[0] = value
        with patch.object(settings.system, 'timezone_name', side_effect=lambda: zone[0]), \
             patch.object(settings.system, 'set_timezone', side_effect=set_zone) as setter, \
             patch.object(settings.system, 'observe_keyboard', return_value=old), \
             patch.object(settings.system, 'in_session', return_value=True), \
             patch.object(settings.system, 'reload_keyboard', side_effect=[RuntimeError('Injected reload failure'), None]):
            with self.assertRaises(settings.SettingsError):
                self.change({settings.LAYOUTS_FIELD: [{'layout': 'es', 'variant': ''}], settings.TIMEZONE_FIELD: 'Europe/Madrid'})
            self.assertEqual(setter.call_args_list[-1].args, ('Etc/UTC',))
            self.assertFalse(setter.call_args_list[-1].kwargs['interactive'])
        self.assertEqual(zone[0], 'Etc/UTC')
        self.assertEqual((self.profile / 'settings.json').read_bytes(), before)
        self.assertFalse((self.profile / 'settings-input.lua').exists())
        self.assertFalse((self.profile / '.settings-recovery.json').exists())

    def test_failed_rollback_requires_explicit_recovery_and_retains_record(self):
        old = {'layout': 'us,us', 'variant': 'euro,altgr-intl', 'file': '', 'keyboards': []}
        with patch.object(settings.system, 'observe_keyboard', return_value=old), \
             patch.object(settings.system, 'in_session', return_value=True), \
             patch.object(settings.system, 'reload_keyboard', side_effect=RuntimeError('Injected failure')):
            with self.assertRaises(settings.SettingsError) as caught:
                self.change({settings.LAYOUTS_FIELD: [{'layout': 'es', 'variant': ''}]})
        self.assertEqual(caught.exception.code, 'recovery')
        with self.assertRaises(settings.SettingsError): settings.snapshot(self.profile)
        self.assertTrue((self.profile / '.settings-recovery.json').exists())
        recovered = settings.recover(self.profile)
        self.assertEqual(recovered['values'][settings.LAYOUTS_FIELD], settings.default_layouts(recovered['preferences']))
        self.assertFalse((self.profile / '.settings-recovery.json').exists())
        (self.profile / '.settings-recovery.json').write_text('{}')
        self.assertEqual(self.request({'operation': 'recover'})['code'], 'recovery')

    def test_reader_distinguishes_active_apply_from_interrupted_apply(self):
        (self.profile / '.settings-recovery.json').write_text('{}')
        with (self.profile / '.settings.lock').open('w') as guard:
            fcntl.flock(guard, fcntl.LOCK_EX)
            self.assertEqual(self.request({'operation': 'read'})['code'], 'busy')
        self.assertEqual(self.request({'operation': 'read'})['code'], 'recovery')

    def test_native_clock_positions_fit_scaled_rotated_and_small_monitors(self):
        for monitor in [dict(name='DP-1', width=1920, height=1080, scale=1, transform=0),
                        dict(name='DP-1', width=3840, height=2160, scale=2, transform=0),
                        dict(name='DP-1', width=1080, height=1920, scale=1, transform=1),
                        dict(name='DP-1', width=800, height=600, scale=1, transform=0)]:
            for position in [{'x': 0, 'y': 0}, {'x': 1, 'y': 1}, {'x': 0.5, 'y': 0.5}]:
                with self.subTest(monitor=monitor, position=position):
                    native = settings.native_clock(self.profile, {'clockPlacement': {'lockScreen': position}}, [monitor])
                    self.assertIn('monitor = DP-1', native)
                    self.assertEqual(native.count('valign = top'), 3)
                    self.assertIn('/bin/desktop-settings" date', native)
                    width, height = monitor['width'] / monitor['scale'], monitor['height'] / monitor['scale']
                    if monitor['transform'] % 2: width, height = height, width
                    size = int(native.split('size = ')[1].splitlines()[0])
                    x, y = map(int, native.split('position = ')[1].splitlines()[0].split(','))
                    self.assertGreaterEqual(x, 16)
                    self.assertGreaterEqual(-y, 64)
                    self.assertLessEqual(x + size, width - 16)
                    self.assertLessEqual(-y + size * 260 / 250 + 70, height - 140 + 2)

    def test_monitor_query_failure_uses_the_lock_launchers_existing_fallback(self):
        preferences = settings.effective_preferences(self.profile)
        preferences['clockPlacement']['lockScreen'] = {'x': 0, 'y': 0}
        with patch.object(settings.system, 'monitors', side_effect=RuntimeError('Monitor query failed')):
            with self.assertRaises(settings.SettingsError) as caught:
                settings.native_lock_configuration(self.profile, (self.profile / 'hyprlock.conf').read_text(), preferences)
        self.assertEqual(caught.exception.code, 'native-config')

    def test_catalog_and_preview_contract_never_modify_settings(self):
        before = (self.profile / 'settings.json').read_bytes()
        catalog = self.request({'operation': 'catalog'})['catalog']
        self.assertIn('Europe/Madrid', [item['id'] for item in catalog['timezones']])
        self.assertIn('us', [item['id'] for item in catalog['layouts']])
        self.assertEqual(catalog['maxLayouts'], 4)
        preview = self.request({'operation': 'preview', 'timezone': 'Asia/Kathmandu'})['clock']
        self.assertEqual(preview['utcOffset'], 'UTC+05:45')
        self.assertEqual(self.request({'operation': 'preview', 'timezone': 'Invalid/Zone'})['code'], 'validation')
        self.assertEqual((self.profile / 'settings.json').read_bytes(), before)

    def test_current_hyprland_option_values_normalize_empty_keymap(self):
        def command(arguments):
            if arguments[-1] == 'devices':
                return json.dumps({'keyboards': []})
            return json.dumps({'value': {'input:kb_file': '[[EMPTY]]', 'input:kb_layout': 'us', 'input:kb_variant': ''}[arguments[-1]]})
        with patch.object(settings.system, 'in_session', return_value=True), \
             patch.object(settings.system, 'command', side_effect=command):
            observed = settings.system.observe_keyboard()
        self.assertEqual((observed['layout'], observed['variant'], observed['file']), ('us', '', ''))

    def test_active_group_and_caps_lock_do_not_create_configuration_conflicts(self):
        preferences, saved = settings.documents(self.profile)
        keyboard = {'layout': 'us,us', 'variant': 'euro,altgr-intl', 'file': '',
                    'keyboards': [{'name': 'keyboard', 'layout': 'us,us', 'variant': 'euro,altgr-intl',
                                   'main': True, 'active_layout_index': 0, 'active_keymap': 'English (US)', 'capsLock': False}]}
        first = settings.snapshot_from(preferences, saved, {'timezone': 'Etc/UTC', 'keyboard': keyboard})
        keyboard['keyboards'][0].update(active_layout_index=1, active_keymap='English (intl.)', capsLock=True)
        second = settings.snapshot_from(preferences, saved, {'timezone': 'Etc/UTC', 'keyboard': keyboard})
        self.assertEqual(first['revision'], second['revision'])
        self.assertEqual(second['runtime']['activeLayout'], 'English (intl.)')
        keyboard['keyboards'][0]['layout'] = 'es'
        third = settings.snapshot_from(preferences, saved, {'timezone': 'Etc/UTC', 'keyboard': keyboard})
        self.assertNotEqual(first['revision'], third['revision'])

    def test_reloading_keyboard_preserves_active_pair_and_rejects_device_overrides(self):
        previous = {'layout': 'us,us', 'variant': 'euro,altgr-intl', 'file': '',
                    'keyboards': [{'name': 'keyboard', 'active_layout_index': 1}]}
        layouts = [{'layout': 'es', 'variant': ''}, {'layout': 'us', 'variant': 'altgr-intl'}]
        current = {'layout': 'es,us', 'variant': ',altgr-intl', 'file': '',
                   'keyboards': [{'name': 'keyboard', 'layout': 'es,us', 'variant': ',altgr-intl'}]}
        def command(arguments): return ''
        with patch.object(settings.system, 'in_session', return_value=True), \
             patch.object(settings.system, 'observe_keyboard', return_value=current), \
             patch.object(settings.system, 'command', side_effect=command) as runner:
            settings.system.reload_keyboard(layouts, previous)
            self.assertEqual(runner.call_args_list[-1].args[0], ['hyprctl', 'switchxkblayout', 'keyboard', '1'])
            current['keyboards'][0]['layout'] = 'de'
            with self.assertRaisesRegex(RuntimeError, 'keyboard-specific'):
                settings.system.reload_keyboard(layouts, previous)

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
            with self.assertRaises(settings.SettingsError):
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
        self.change({settings.LAYOUTS_FIELD: [{'layout': 'es', 'variant': ''}, {'layout': 'us', 'variant': 'euro'}]})
        self.apply(False)
        before = path.read_bytes(), path.stat().st_mtime_ns
        generated = (self.profile / 'settings-input.lua').read_bytes()
        tasks = yaml.safe_load((ROLE / 'tasks/configure.yml').read_text())
        initializer = next(task for task in tasks if task['name'] == 'Initialize user-owned desktop settings')
        rebuild = next(task for task in tasks if task['name'] == 'Rebuild interactive input settings from preserved user overrides')
        playbook = self.profile / 'settings-repeat.yml'
        playbook.write_text(yaml.safe_dump([{
            'hosts': 'localhost', 'gather_facts': False, 'become': False,
            'vars': {'desktop_root': str(self.profile), 'archsetup_desktop_user': getpass.getuser(),
                     'desktop_group': grp.getgrgid(os.getgid()).gr_name},
            'tasks': [initializer, rebuild, initializer, rebuild]}]))
        environment = dict(os.environ, ANSIBLE_HOME=str(self.profile / 'ansible-home'),
                           ANSIBLE_LOCAL_TEMP=str(self.profile / 'ansible-tmp'))
        result = subprocess.run([executable, '-i', 'localhost,', '-c', 'local', str(playbook)],
                                env=environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r'changed=0\s+unreachable=0\s+failed=0')
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)
        self.assertEqual((self.profile / 'settings-input.lua').read_bytes(), generated)

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
