#!/usr/bin/env python3
import configparser
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import yaml
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

FILES = Path(__file__).resolve().parents[2] / 'roles/desktop/files'
loader = importlib.machinery.SourceFileLoader('network_migration', str(FILES / 'desktop-network-migrate'))
spec = importlib.util.spec_from_loader(loader.name, loader)
migration = importlib.util.module_from_spec(spec)
loader.exec_module(migration)


class NetworkMigrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        for name, suffix in [('NM_DIR', 'nm'), ('IWD_DIR', 'iwd'), ('SYS_NET', 'net'), ('BACKUP_ROOT', 'backups')]:
            path = root / suffix
            path.mkdir()
            patcher = patch.object(migration, name, path)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(migration, 'RESOLV', root / 'resolv.conf')
        patcher.start()
        self.addCleanup(patcher.stop)
        (migration.NM_DIR / 'system-connections').mkdir()
        (migration.NM_DIR / 'conf.d').mkdir()

    def test_detects_installed_and_instantiated_competitors_without_masking_nm_backend(self):
        names = ['iwd.service', 'connman.service', 'wicd.service', 'dhcpcd.service', 'dhcpcd@wlan0.service',
                 'netctl-auto@wlan0.service', 'netctl@.service', 'systemd-networkd.socket',
                 'systemd-networkd-wait-online.service', 'systemd-networkd-wait-online@wlan0.service', 'wpa_supplicant@wlan0.service',
                 'wpa_supplicant-nl80211@.service']
        for name in names: self.assertRegex(name, migration.CONFLICT)
        for name in ['wpa_supplicant.service', 'NetworkManager.service', 'systemd-resolved.service', 'bluetooth.service']:
            self.assertIsNone(migration.CONFLICT.fullmatch(name))
        def command(*args, **kwargs):
            if args[1] == 'list-unit-files': return 'iwd.service disabled\nwpa_supplicant@.service disabled'
            if args[1] == 'list-units': return 'wpa_supplicant@wlan0.service loaded active running'
            return 'disabled' if args[1] == 'is-enabled' else 'inactive'
        with patch.object(migration, 'command', side_effect=command):
            self.assertEqual(set(migration.competing_units()), {'iwd.service', 'wpa_supplicant@.service', 'wpa_supplicant@wlan0.service'})

    def test_iwd_import_handles_encoded_ssid_hash_keys_and_preserves_existing_profiles(self):
        ssid = 'Home: Wi-Fi'
        (migration.IWD_DIR / ('=' + ssid.encode().hex() + '.psk')).write_text('[Security]\nPassphrase= test\\password\n')
        (migration.IWD_DIR / 'Hashed.psk').write_text('[Security]\nPreSharedKey=' + 'a' * 64 + '\n')
        (migration.IWD_DIR / 'Cafe.open').write_text('[Settings]\nAutoConnect=false\n')
        (migration.IWD_DIR / 'Work.8021x').write_text('[Security]\nEAP-Method=TLS\n')
        existing = {'Hashed'}
        profiles, skipped = migration.iwd_profiles(existing)
        self.assertEqual(len(profiles), 2)
        self.assertEqual(skipped, ['Work.8021x'])
        self.assertEqual(existing, {ssid, 'Hashed', 'Cafe'})
        for path, content in profiles.items(): path.write_text(content)
        self.assertEqual(migration.existing_networks(), {ssid, 'Cafe'})
        self.assertEqual(migration.iwd_profiles(existing)[0], {})

    def test_generated_keyfile_is_accepted_by_real_libnm(self):
        try:
            import gi
            gi.require_version('NM', '1.0')
            from gi.repository import GLib, NM
        except (ImportError, ValueError):
            self.skipTest('libnm introspection required')
        (migration.IWD_DIR / 'Home.psk').write_text('[Security]\nPassphrase=pass word\\\\slash\n')
        profiles, _ = migration.iwd_profiles(set())
        keyfile = GLib.KeyFile.new()
        content = next(iter(profiles.values()))
        keyfile.load_from_data(content, len(content.encode()), GLib.KeyFileFlags.NONE)
        connection = NM.keyfile_read(keyfile, '/', NM.KeyfileHandlerFlags.NONE, None, None)
        connection.normalize()
        self.assertTrue(connection.verify())
        self.assertEqual(bytes(connection.get_setting_wireless().get_ssid().get_data()), b'Home')
        self.assertEqual(connection.get_setting_wireless_security().get_psk(), 'pass word\\slash')

    def test_active_connection_without_credentials_stops_before_mutation(self):
        (migration.SYS_NET / 'wlan0/wireless').mkdir(parents=True)
        with patch.object(migration.shutil, 'which', return_value='/usr/bin/iwctl'), patch.object(migration, 'command', side_effect=[
                '10 (unmanaged)', 'SSID: Enterprise']):
            with self.assertRaisesRegex(RuntimeError, 'needs a NetworkManager profile'):
                migration.validate_uplinks(['wlan0'], {'Home'})

    def test_static_addresses_are_not_silently_replaced_by_dhcp(self):
        with patch.object(migration.shutil, 'which', return_value='nmcli'), patch.object(migration, 'command', side_effect=[
                '10 (unmanaged)', json.dumps([{'addr_info': [{'scope': 'global', 'family': 'inet'}]}])]):
            with self.assertRaisesRegex(RuntimeError, 'static IPv4'):
                migration.validate_uplinks(['eth0'], set())

    def plan(self):
        return dict(changed=True, files={migration.NM_DIR / 'conf.d/99-archsetup-network.conf': migration.CONFIG,
                    migration.NM_DIR / 'conf.d/90-archsetup-vpn-only.conf': None},
                    services={'iwd.service': dict(enabled='enabled', active=True)},
                    nm=dict(enabled='disabled', active=False), resolved=dict(enabled='enabled', active=True),
                    devices=['wlan0'], wifi_uplinks={}, radios={}, dns_ok=False)

    def test_failure_restores_files_dns_and_original_service_states(self):
        legacy = migration.NM_DIR / 'conf.d/90-archsetup-vpn-only.conf'
        legacy.write_text('old VPN restriction')
        migration.RESOLV.symlink_to('/previous/resolv.conf')
        with patch.object(migration, 'command', return_value='') as command, patch.object(migration, 'wait_for_devices'), patch.object(migration, 'wait_for_wifi_ready'), patch.object(migration, 'wait_for_uplinks', side_effect=RuntimeError('No connection')):
            with self.assertRaisesRegex(RuntimeError, 'No connection.*Previous configuration and services restored'):
                migration.apply(self.plan())
        self.assertEqual(legacy.read_text(), 'old VPN restriction')
        self.assertFalse((migration.NM_DIR / 'conf.d/99-archsetup-network.conf').exists())
        self.assertEqual(str(migration.RESOLV.readlink()), '/previous/resolv.conf')
        calls = [call.args for call in command.call_args_list]
        self.assertIn(('systemctl', 'unmask', 'iwd.service'), calls)
        self.assertIn(('systemctl', 'start', 'iwd.service'), calls)
        self.assertIn(('systemctl', 'disable', 'NetworkManager.service'), calls)

    def test_success_removes_vpn_only_restriction_and_masks_competitors(self):
        legacy = migration.NM_DIR / 'conf.d/90-archsetup-vpn-only.conf'
        legacy.write_text('old VPN restriction')
        migration.RESOLV.write_text('nameserver 1.1.1.1')
        with patch.object(migration, 'command', return_value='') as command, patch.object(migration, 'wait_for_devices'), patch.object(migration, 'wait_for_wifi_ready'), patch.object(migration, 'wait_for_uplinks') as wait:
            migration.apply(self.plan())
        self.assertFalse(legacy.exists())
        self.assertEqual((migration.NM_DIR / 'conf.d/99-archsetup-network.conf').read_text(), migration.CONFIG)
        self.assertEqual(str(migration.RESOLV.readlink()), '/run/systemd/resolve/stub-resolv.conf')
        command.assert_any_call('systemctl', 'mask', 'iwd.service')
        wait.assert_called_once_with(['wlan0'])
        backups = list(migration.BACKUP_ROOT.iterdir())
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o700)

    def test_check_prepares_import_without_writing_and_preserves_escaped_password(self):
        (migration.IWD_DIR / 'Home.psk').write_text('[Security]\nPassphrase=pass\\sword\\\\slash\n[Settings]\nAutoConnect=false\n')
        with patch.object(migration, 'competing_units', return_value={}), patch.object(
                migration, 'unit_state', return_value=dict(enabled='enabled', active=True)), patch.object(
                migration, 'default_devices', return_value=[]):
            plan = migration.build_plan()
        self.assertTrue(plan['changed'])
        self.assertEqual(list((migration.NM_DIR / 'system-connections').iterdir()), [])
        profile = next(value for path, value in plan['files'].items() if path.suffix == '.nmconnection')
        parsed = configparser.ConfigParser(interpolation=None)
        parsed.read_string(profile)
        self.assertEqual(migration.unescape(parsed['wifi-security']['psk']), 'pass word\\slash')
        self.assertEqual(parsed['connection']['autoconnect'], 'false')
        plan['wifi_uplinks'] = {'wlan0': 'Home'}
        plan['devices'] = ['wlan0']
        with patch.object(migration, 'command', return_value='') as command, patch.object(migration, 'wait_for_devices'), patch.object(migration, 'wait_for_wifi_ready'), patch.object(migration, 'wait_for_uplinks'):
            migration.apply(plan)
        profile_path = next((migration.NM_DIR / 'system-connections').iterdir())
        self.assertEqual(profile_path.stat().st_mode & 0o777, 0o600)
        command.assert_any_call('nmcli', '--wait', '45', 'connection', 'up', 'uuid',
                                parsed['connection']['uuid'], 'ifname', 'wlan0', timeout=50)

    def test_ansible_check_and_async_apply_use_supported_modules(self):
        executable = shutil.which('ansible-playbook')
        if not executable:
            self.skipTest('Ansible is required')
        directory = Path(self.directory.name)
        helper = directory / 'fake-migration'
        marker = directory / 'applied'
        helper.write_text('#!/usr/bin/python3\nimport json, sys\nfrom pathlib import Path\n'
                          + f'if sys.argv[1] == "--apply": Path({str(marker)!r}).touch()\n'
                          + 'print(json.dumps(dict(changed=False)))\n')
        helper.chmod(0o755)
        tasks = yaml.safe_load((FILES.parent / 'tasks/network.yml').read_text())
        preview = next(task for task in tasks if 'ansible.builtin.script' in task)
        apply = next(task for task in tasks if 'ansible.builtin.command' in task)
        preview['ansible.builtin.script'] = str(helper) + ' --check'
        apply['ansible.builtin.command']['argv'][0] = str(helper)
        apply['poll'] = 1
        playbook = directory / 'test.yml'
        playbook.write_text(yaml.safe_dump([dict(hosts='localhost', gather_facts=False, become=False, tasks=[preview, apply])]))
        environment = dict(os.environ, ANSIBLE_HOME=str(directory), ANSIBLE_LOCAL_TEMP=str(directory / 'tmp'))
        for check in [True, False]:
            result = subprocess.run([executable, '-i', 'localhost,', '-c', 'local', str(playbook)] + (['--check'] if check else []),
                                    env=environment, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(marker.exists(), not check)

    def test_iwd_removed_interface_is_recreated_and_udev_rename_is_followed(self):
        def command(*args, **kwargs):
            if args[0] == 'iw':
                path = migration.SYS_NET / 'wlp2s0'
                (path / 'wireless').mkdir(parents=True)
                radio = Path(self.directory.name) / 'phy0'
                radio.mkdir()
                (path / 'phy80211').symlink_to(radio)
            return ''
        with patch.object(migration, 'command', side_effect=command) as run:
            self.assertEqual(migration.restore_wifi_interfaces({'wlan0': 'phy0'}), {'wlan0': 'wlp2s0'})
            run.assert_any_call('iw', 'phy', 'phy0', 'interface', 'add', 'wlan0', 'type', 'managed')
        with patch.object(migration, 'command', return_value='') as run:
            self.assertEqual(migration.restore_wifi_interfaces({'wlan0': 'phy0'}), {'wlan0': 'wlp2s0'})
            self.assertFalse(any(call.args[0] == 'iw' for call in run.call_args_list))

    def test_networkmanager_device_discovery_waits_for_startup(self):
        with patch.object(migration, 'command', side_effect=['lo', 'lo\nwlan0']) as run, patch.object(migration.time, 'sleep') as sleep:
            migration.wait_for_devices(['wlan0'])
        self.assertEqual(run.call_count, 2)
        sleep.assert_called_once_with(1)

    def test_wifi_activation_waits_for_supplicant_readiness(self):
        with patch.object(migration, 'command', side_effect=['10 (unmanaged)', '20 (unavailable)', '30 (disconnected)']) as run, patch.object(migration.time, 'sleep') as sleep:
            migration.wait_for_wifi_ready('wlan0')
        self.assertEqual(run.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_converged_installation_is_idempotent(self):
        (migration.NM_DIR / 'conf.d/99-archsetup-network.conf').write_text(migration.CONFIG)
        migration.RESOLV.symlink_to('/run/systemd/resolve/stub-resolv.conf')
        with patch.object(migration, 'competing_units', return_value={'iwd.service': dict(enabled='masked', active=False)}), patch.object(
                migration, 'unit_state', return_value=dict(enabled='enabled', active=True)):
            plan = migration.build_plan()
        self.assertFalse(plan['changed'])
        with patch.object(migration, 'command') as command:
            migration.apply(plan)
            command.assert_not_called()


if __name__ == '__main__': unittest.main()
