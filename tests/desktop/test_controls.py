#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('controls', str(Path(__file__).resolve().parents[2] / 'roles/desktop/files/desktop-controls'))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)


class ControlTests(unittest.TestCase):
    def test_nmcli_escaping_and_vpn_types(self):
        output = 'uuid1:vpn:Work\\: Europe:yes\nuuid2:wireguard:Home\\\\:no\nuuid3:ethernet:Wired:yes'
        with patch.object(controls, 'command', return_value=output):
            self.assertEqual(controls.connections(), [dict(id='uuid1', name='Work: Europe', active=True), dict(id='uuid2', name='Home\\', active=False)])

    def test_audio_volume_and_monitor_filter(self):
        data = [dict(name='mic', description='USB microphone', mute=True, volume={'left': {'value': 32768}, 'right': {'value': 65536}}),
                dict(name='sink.monitor', volume={})]
        with patch.object(controls, 'command', return_value=json.dumps(data)):
            self.assertEqual(controls.audio('sources'), [dict(id='mic', name='USB microphone', muted=True, volume=75)])

    def test_audio_device_must_still_exist(self):
        with patch.object(controls, 'audio', return_value=[]), patch.object(controls, 'command') as command:
            with self.assertRaises(ValueError): controls.apply(dict(action='output', value='disconnected'))
            command.assert_not_called()

    def test_selected_vpn_is_connected_or_disconnected_by_uuid(self):
        for active in (True, False):
            with self.subTest(active=active), patch.object(controls, 'connections', return_value=[dict(id='abc', active=active)]), patch.object(controls, 'command') as command:
                controls.apply(dict(action='vpn', value='abc'))
                command.assert_called_once_with('nmcli', '--wait', '10', 'connection', 'down' if active else 'up', 'uuid', 'abc')

    def test_actions_validate_values_before_running_commands(self):
        for request in [dict(action='volume', value=-1), dict(action='volume', value=101), dict(action='volume', value=True),
                        dict(action='wifi', value='off'), dict(action='mic', value='toggle'), dict(action='bad')]:
            with self.subTest(request=request), patch.object(controls, 'command') as command:
                with self.assertRaises(ValueError): controls.apply(request)
                command.assert_not_called()

    def test_command_failures_are_not_reported_as_success(self):
        with patch.object(controls.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'Permission denied')):
            with self.assertRaisesRegex(ValueError, 'Permission denied'): controls.apply(dict(action='wifi', value=False))
            self.assertEqual(controls.command('nmcli', optional=True), '')

    def test_missing_services_return_disabled_controls(self):
        with patch.object(controls, 'command', return_value=''), patch.object(controls.shutil, 'which', return_value=None):
            state = controls.snapshot()
        self.assertFalse(state['wifiAvailable'])
        self.assertFalse(state['bluetoothAvailable'])
        self.assertFalse(state['nightAvailable'])
        self.assertEqual(state['outputs'], [])
        self.assertEqual(state['vpns'], [])
        self.assertGreater(state['uptime'], 0)


if __name__ == '__main__': unittest.main()
