#!/usr/bin/env python3
"""Display validation and transaction confirmation/rollback regressions."""
from contextlib import ExitStack
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from render import ROLE, render
sys.path.insert(0, str(ROLE / 'files'))
import desktop_settings as settings
import desktop_screens as screens
observe_displays = screens.observe
start_recovery_guard = screens.start_guard


class ScreenTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': ''})
        environment.start()
        self.addCleanup(environment.stop)
        directory = tempfile.TemporaryDirectory(prefix='archsetup-screens-test-')
        self.addCleanup(directory.cleanup)
        self.root = render(directory.name)
        self.active = [{'name': 'DP-1', 'mode': '1920x1080@60.00', 'scale': 1, 'transform': 0, 'x': 0, 'y': 0}]
        self.catalog = [{'name': 'DP-1', 'description': 'Test monitor',
                         'modes': ['1920x1080@60.00', '1920x1080@144.00', '1280x720@60.00']}]
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(settings.system, 'in_session', return_value=True))
        self.stack.enter_context(patch.object(settings.system, 'observe_keyboard', return_value=None))
        self.stack.enter_context(patch.object(screens, 'observe', side_effect=self.observed))
        self.guard = self.stack.enter_context(patch.object(screens, 'start_guard'))
        self.reload = self.stack.enter_context(patch.object(screens, 'reload', side_effect=self.set_active))
        self.restore = self.stack.enter_context(patch.object(screens, 'restore', side_effect=self.set_active))

    def observed(self):
        return {'values': json.loads(json.dumps(self.active)), 'catalog': self.catalog, 'error': ''}

    def set_active(self, value):
        self.active = json.loads(json.dumps(value))

    def apply(self, **changes):
        value = [dict(self.active[0], **changes)]
        return settings.apply(self.root, settings.snapshot(self.root)['revision'], {screens.FIELD: value})

    def test_kept_changes_persist_and_rebuild_from_saved_overrides(self):
        with patch.object(screens, 'confirm') as confirm:
            result = self.apply(mode='1920x1080@144.00', scale=1.5, transform=1)
        confirm.assert_called_once_with(self.root)
        self.guard.assert_called_once_with(self.root)
        self.assertEqual(result['values'][screens.FIELD][0]['transform'], 1)
        saved = json.loads((self.root / 'settings.json').read_text())
        self.assertEqual(saved['screen']['monitors'], self.active)
        generated = (self.root / 'settings-screens.lua').read_text()
        self.assertIn('scale=1.5', generated)
        render(self.root)
        self.assertEqual(json.loads((self.root / 'settings.json').read_text()), saved)
        (self.root / 'settings-screens.lua').unlink()
        self.assertTrue(settings.sync(self.root))
        self.assertEqual((self.root / 'settings-screens.lua').read_text(), generated)
        self.assertFalse(settings.sync(self.root))

    def test_timeout_restores_runtime_files_and_saved_settings(self):
        before = (self.root / 'settings.json').read_bytes()
        original = self.observed()['values']
        with patch.object(screens, 'TEST_SECONDS', 0.01):
            with self.assertRaisesRegex(settings.SettingsError, 'reverted'):
                self.apply(scale=1.5)
        self.assertEqual(self.active, original)
        self.assertEqual((self.root / 'settings.json').read_bytes(), before)
        self.assertFalse((self.root / 'settings-screens.lua').exists())
        self.assertFalse((self.root / '.settings-recovery.json').exists())
        self.assertIsNone(screens.status(self.root))

    def test_compositor_rejection_rolls_back_before_confirmation(self):
        self.reload.side_effect = RuntimeError('Injected compositor rejection')
        with patch.object(screens, 'confirm') as confirm:
            with self.assertRaisesRegex(settings.SettingsError, 'compositor rejection'):
                self.apply(scale=1.5)
        confirm.assert_not_called()
        self.restore.assert_called_once()
        self.assertFalse((self.root / 'settings-screens.lua').exists())

    def test_invalid_modes_scales_positions_and_overlap_never_change_outputs(self):
        before = (self.root / 'settings.json').read_bytes()
        for changes in [{'mode': '9999x9999@60'}, {'mode': '1920x1080@60;bad'}, {'scale': 1.4},
                        {'scale': True}, {'scale': float('nan')}, {'transform': 8}, {'x': 0.5}, {'y': None}]:
            with self.subTest(changes=changes), self.assertRaises(settings.SettingsError):
                self.apply(**changes)
        second = dict(self.active[0], name='DP-2')
        observed = self.observed()
        observed['catalog'].append(dict(self.catalog[0], name='DP-2'))
        with self.assertRaisesRegex(ValueError, 'overlap'):
            screens.validate(self.active + [second], observed)
        screens.validate(self.active + [dict(second, x=1920)], observed)
        self.assertEqual((self.root / 'settings.json').read_bytes(), before)
        self.reload.assert_not_called()

    def test_hotplug_conflicts_preserve_the_saved_configuration(self):
        current = settings.snapshot(self.root)
        self.active[0]['x'] = 1920
        with self.assertRaises(settings.SettingsError) as caught:
            settings.apply(self.root, current['revision'], {screens.FIELD: [dict(self.active[0], scale=1.5)]})
        self.assertEqual(caught.exception.code, 'conflict')

    def test_disconnected_monitor_overrides_are_retained(self):
        saved = json.loads((self.root / 'settings.json').read_text())
        disconnected = dict(self.active[0], name='HDMI-A-1', x=1920)
        saved['screen'] = {'monitors': [disconnected]}
        (self.root / 'settings.json').write_text(json.dumps(saved))
        with patch.object(screens, 'confirm'):
            self.apply(scale=1.5)
        saved = json.loads((self.root / 'settings.json').read_text())
        self.assertIn(disconnected, saved['screen']['monitors'])

    def test_confirmation_requires_current_token_and_handles_keep_or_restore(self):
        for keep in (True, False):
            errors = []
            def confirm():
                try:
                    screens.confirm(self.root)
                except RuntimeError as error:
                    errors.append(str(error))
            thread = threading.Thread(target=confirm)
            thread.start()
            try:
                deadline = time.monotonic() + 2
                while screens.status(self.root) is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                pending = screens.status(self.root)
                self.assertIsNotNone(pending)
                with self.assertRaises(ValueError):
                    screens.decide(self.root, 'stale', True)
                screens.decide(self.root, pending['token'], keep)
            finally:
                thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertEqual(bool(errors), not keep)
            self.assertIsNone(screens.status(self.root))

    def test_interrupted_apply_can_recover_pre_test_geometry(self):
        with patch.object(screens, 'confirm', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.apply(scale=1.5)
        self.assertTrue((self.root / '.settings-recovery.json').exists())
        settings.recover(self.root)
        self.assertEqual(self.active[0]['scale'], 1)
        self.assertFalse((self.root / 'settings-screens.lua').exists())

    def test_detached_guard_recovers_generated_files_after_helper_exit(self):
        with patch.object(screens, 'confirm', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.apply(scale=1.5)
        # Shorten only this rendered fixture's watchdog delay. The child runs
        # the installed helper independently of this test's in-process mocks.
        module = self.root / 'bin/desktop_screens.py'
        module.write_text(module.read_text().replace('TEST_SECONDS = 20', 'TEST_SECONDS = -9.9'))
        launch = subprocess.Popen
        def capture(*args, **kwargs):
            return launch(*args, **dict(kwargs, stderr=subprocess.PIPE))
        with patch.object(screens.subprocess, 'Popen', side_effect=capture):
            child = start_recovery_guard(self.root)
        _, error = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0, error.decode())
        self.assertFalse((self.root / '.settings-recovery.json').exists())
        self.assertFalse((self.root / 'settings-screens.lua').exists())
        self.assertNotIn('screen', json.loads((self.root / 'settings.json').read_text()))

    def test_monitor_adapter_reports_supported_modes_and_runtime(self):
        monitor = dict(name='DP-1', width=1920, height=1080, refreshRate=59.9999, x=-1920, y=0,
                       scale=1, transform=0, availableModes=['1920x1080@60.00Hz', '1280x720@60.00Hz'])
        with patch.object(settings.system, 'monitors', return_value=[monitor]):
            observed = observe_displays()
        self.assertEqual(observed['values'][0]['mode'], '1920x1080@60.00')
        self.assertEqual(observed['values'][0]['x'], -1920)
        self.assertEqual(observed['catalog'][0]['modes'], ['1920x1080@60.00', '1280x720@60.00'])
        self.assertEqual(observed['error'], '')

    def test_runtime_verification_checks_mode_geometry_and_scale(self):
        self.assertTrue(screens.matches(self.active, self.observed()['values']))
        for change in [{'mode': '1280x720@60.00'}, {'mode': '1920x1080@144.00'},
                       {'x': 1920}, {'scale': 1.5}, {'transform': 1}]:
            with self.subTest(change=change):
                self.assertFalse(screens.matches([dict(self.active[0], **change)], self.active))


if __name__ == '__main__':
    unittest.main()
