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
import jinja2

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

    def test_updated_lock_template_takes_precedence_over_stale_theme(self):
        base = self.profile / 'hyprlock.conf'
        generated = self.profile / 'theme/hyprlock.conf'
        generated.parent.mkdir()
        generated.write_text('old lock configuration\n')
        os.utime(generated, ns=(1, 1))
        self.assertEqual(self.actions.themed('hyprlock.conf'), base)
        generated.write_text(base.read_text())
        os.utime(generated, ns=(base.stat().st_mtime_ns + 1, base.stat().st_mtime_ns + 1))
        self.assertEqual(self.actions.themed('hyprlock.conf'), generated)

    def test_keyring_hook_preserves_pam_authentication_result(self):
        import ctypes
        import ctypes.util
        import getpass
        source = (ROLE / 'files/archsetup-hyprlock.pam').read_text()
        self.assertIn('auth substack hyprlock', source)
        self.assertIn('auth optional pam_gnome_keyring.so auto_start', source)
        self.assertIn('pam:module = archsetup-hyprlock', (self.profile / 'hyprlock.conf').read_text())
        # Exercise real PAM control flow in a temporary confdir. Simulate a failed
        # keyring module with pam_deny; never authenticate a real user or open a keyring.
        directory = Path(self.directory.name) / 'pam'
        directory.mkdir()
        (directory / 'archsetup-hyprlock').write_text(source.replace(
            'pam_gnome_keyring.so auto_start', 'pam_deny.so'))
        pam = ctypes.CDLL(ctypes.util.find_library('pam'))
        if not hasattr(pam, 'pam_start_confdir'):
            self.skipTest('Linux PAM with pam_start_confdir is required')
        conversation_fn = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_void_p,
                                          ctypes.c_void_p, ctypes.c_void_p)
        class Conversation(ctypes.Structure):
            _fields_ = [('conv', conversation_fn), ('appdata_ptr', ctypes.c_void_p)]
        callback = conversation_fn(lambda *args: 19)  # No interactive prompts.
        conversation = Conversation(callback, None)
        pam.pam_start_confdir.argtypes = [ctypes.c_char_p, ctypes.c_char_p,
            ctypes.POINTER(Conversation), ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
        pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
        for policy, accepted in [('auth sufficient pam_permit.so\n', True),
                                 ('auth requisite pam_deny.so\n', False),
                                 ('auth required pam_deny.so\nauth sufficient pam_permit.so\n', False)]:
            (directory / 'hyprlock').write_text(policy)
            handle = ctypes.c_void_p()
            result = pam.pam_start_confdir(b'archsetup-hyprlock', getpass.getuser().encode(),
                ctypes.byref(conversation), str(directory).encode(), ctypes.byref(handle))
            self.assertEqual(result, 0)
            try:
                result = pam.pam_authenticate(handle, 0)
                self.assertEqual(result == 0, accepted, f'PAM result={result}, policy={policy}')
            finally:
                pam.pam_end(handle, result)

    def test_locked_session_uses_compositor_startup_lock(self):
        fake_bin = Path(self.directory.name) / 'fake-bin'
        fake_bin.mkdir()
        launcher = fake_bin / 'start-hyprland'
        launcher.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        launcher.chmod(0o755)
        config = Path(self.directory.name) / 'config'
        (config / 'archsetup').mkdir(parents=True)
        (config / 'archsetup/hyprland.lua').write_text('-- test\n')
        (config / 'archsetup/bin').mkdir()
        action = config / 'archsetup/bin/desktop-action'
        action.write_text('#!/bin/sh\ntest "$1" = refresh-theme\n')
        action.chmod(0o755)
        environment = dict(os.environ, XDG_CONFIG_HOME=str(config),
                           PATH=str(fake_bin) + os.pathsep + os.environ['PATH'])
        for locked in [False, True]:
            result = subprocess.run(['bash', str(ROLE / 'files/archsetup-session')]
                                    + (['--locked'] if locked else []),
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            args = result.stdout.splitlines()
            self.assertEqual(args[:3], ['--', '--config', str(config / 'archsetup/hyprland.lua')])
            self.assertEqual('--locked-cmd' in args, locked)
            if locked:
                self.assertEqual(args[4], str(config / 'archsetup/bin/desktop-action') + ' lock')

    def test_greetd_autologin_is_always_locked(self):
        import tomllib
        tasks = yaml.safe_load((ROLE / 'tasks/login.yml').read_text())
        source = next(task['ansible.builtin.copy']['content'] for task in tasks
                      if task.get('ansible.builtin.copy', {}).get('dest') == '/etc/greetd/config.toml')
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.filters['bool'] = lambda value: str(value).lower() == 'true'
        for enabled in ['true', 'false']:
            config = tomllib.loads(env.from_string(source).render(
                archsetup_desktop_autologin_locked=enabled, archsetup_desktop_user='tester'))
            self.assertEqual(config['default_session']['user'], 'greeter')
            if enabled == 'true':
                self.assertEqual(config['initial_session'], {
                    'command': '/usr/local/bin/archsetup-session --locked', 'user': 'tester'})
            else:
                self.assertNotIn('initial_session', config)

    def test_missing_brave_is_allowed_only_for_automatic_provisioning(self):
        executable = shutil.which('ansible-playbook') or str(Path(sys.executable).parent / 'ansible-playbook')
        if not Path(executable).exists():
            self.skipTest('ansible-playbook is required for browser preflight regression')
        tasks = yaml.safe_load((ROLE / 'tasks/preflight.yml').read_text())
        browser_check = next(task for task in tasks if task['name'] == 'Require the requested browser on fresh installs')
        environment = dict(os.environ, ANSIBLE_HOME=self.directory.name,
                           ANSIBLE_LOCAL_TEMP=str(Path(self.directory.name) / 'ansible-tmp'))
        cases = [(True, True, 'brave-browser.desktop', True),
                 (False, True, 'brave-browser.desktop', False),
                 (True, False, 'brave-browser.desktop', False),
                 (True, True, 'firefox.desktop', False)]
        for provisioning, automatic, browser, allowed in cases:
            with self.subTest(provisioning=provisioning, automatic=automatic, browser=browser):
                playbook = Path(self.directory.name) / 'browser-preflight.yml'
                playbook.write_text(yaml.safe_dump([{
                    'hosts': 'localhost', 'gather_facts': False, 'become': False,
                    'vars': {'desktop_browser_entries': {'results': [{'stat': {'exists': False}}]},
                             'desktop_browser_install_allowed': provisioning,
                             'archsetup_desktop_install_brave': automatic,
                             'archsetup_desktop_browser': browser,
                             'archsetup_desktop_require_browser': True},
                    'tasks': [browser_check]}]))
                result = subprocess.run([executable, '-i', 'localhost,', '-c', 'local',
                                         '--check', str(playbook)], env=environment,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0 if allowed else 2, result.stdout + result.stderr)

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
        for value, reduced in [('false', False), ('true', True)]:
            with self.subTest(value=value):
                render(self.profile, {'archsetup_desktop_reduced_motion': value})
                self.assertEqual(json.loads((self.profile / 'preferences.json').read_text())['reducedMotion'], reduced)
                enabled = 'false' if reduced else 'true'
                self.assertIn(f'animations = {{ enabled = {enabled} }}', (self.profile / 'hyprland.lua').read_text())
                self.assertIn(f'enabled = {enabled}', (self.profile / 'hyprlock.conf').read_text())
                timing = json.loads((self.profile / 'swaync.json').read_text())['transition-time']
                self.assertEqual(timing == 0, reduced)
                self.assertLessEqual(timing, 140)
                self.assertEqual('transition: none; animation: none;' in (self.profile / 'swaync.css').read_text(), reduced)

    def shell_refresh_fixture(self, name, runtime_exists=True):
        import getpass
        directory = Path(self.directory.name) / name
        role = directory / 'roles/refresh'
        (role / 'tasks').mkdir(parents=True)
        for folder in ['files/shell', 'templates', 'defaults', 'handlers']:
            source = ROLE / folder
            shutil.copytree(source, role / folder)
        shutil.copy2(ROLE / 'tasks/refresh-shell.yml', role / 'tasks/refresh-shell.yml')
        tasks = [task for task in yaml.safe_load((ROLE / 'tasks/configure.yml').read_text())
                 if task['name'] in ['Install original desktop shell', 'Render desktop shell preferences']]
        tasks.append({'name': 'Simulate a later validation failure',
                      'ansible.builtin.assert': {'that': [False]},
                      'when': 'refresh_test_fail | default(false) | bool'})
        (role / 'tasks/main.yml').write_text(yaml.safe_dump(tasks))
        profile = directory / 'profile'
        profile.mkdir()
        runtime = directory / 'runtime'
        if runtime_exists:
            runtime.mkdir()
        fake_bin = directory / 'fake-bin'
        fake_bin.mkdir()
        events = directory / 'events.jsonl'
        fake_qs = fake_bin / 'qs'
        fake_qs.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
from pathlib import Path
events = Path(os.environ['QS_TEST_EVENTS'])
args = sys.argv[1:]
with events.open('a') as stream:
    stream.write(json.dumps(args) + '\\n')
if os.environ.get('XDG_RUNTIME_DIR') != os.environ['QS_TEST_RUNTIME'] or '--any-display' not in args:
    print('Wrong session selection', file=sys.stderr)
    sys.exit(2)
if 'kill' in args:
    if os.environ['QS_TEST_MODE'] == 'none':
        config = Path(args[args.index('-p') + 1]) / 'shell.qml'
        print(f'No running instances for "{config}"', file=sys.stderr)
        sys.exit(255)
    if os.environ['QS_TEST_MODE'] == 'error':
        print('IPC connection denied', file=sys.stderr)
        sys.exit(3)
elif 'ipc' in args:
    if args.index('--any-display') > args.index('call'):
        print('call: The following argument was not expected: --any-display', file=sys.stderr)
        sys.exit(109)
    calls = [json.loads(line) for line in events.read_text().splitlines()]
    if sum('ipc' in call for call in calls) == 1:
        print('Shell is starting', file=sys.stderr)
        sys.exit(1)
    print('{"page":"","barVisible":true}')
else:
    sys.exit(2)
''')
        fake_qs.chmod(0o755)
        playbook = directory / 'refresh.yml'
        playbook.write_text(yaml.safe_dump([{
            'hosts': 'localhost', 'gather_facts': False, 'become': False,
            'vars': {'ansible_become': False, 'archsetup_desktop_user': getpass.getuser(),
                     'desktop_group': str(os.getgid()), 'desktop_root': str(profile),
                     'desktop_runtime_dir': str(runtime)},
            'roles': ['refresh'],
        }]))
        environment = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ['PATH'],
                           ANSIBLE_HOME=str(directory), ANSIBLE_LOCAL_TEMP=str(directory / 'ansible-tmp'),
                           ANSIBLE_NOCOLOR='1', QS_TEST_EVENTS=str(events),
                           QS_TEST_RUNTIME=str(runtime), QS_TEST_MODE='active')
        return directory, playbook, events, environment

    def run_shell_refresh(self, fixture, *options):
        executable = shutil.which('ansible-playbook') or str(Path(sys.executable).parent / 'ansible-playbook')
        if not Path(executable).exists():
            self.skipTest('ansible-playbook is required for shell refresh regression')
        _, playbook, _, environment = fixture
        return subprocess.run([executable, '-i', 'localhost,', '-c', 'local', str(playbook), *options],
                              env=environment, capture_output=True, text=True, timeout=30)

    def test_shell_refresh_runs_once_and_unchanged_apply_does_not_restart(self):
        fixture = self.shell_refresh_fixture('active')
        applied = self.run_shell_refresh(fixture)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        events = fixture[2].read_text()
        calls = [json.loads(line) for line in events.splitlines()]
        self.assertEqual(sum('kill' in call for call in calls), 1)
        self.assertEqual(sum('ipc' in call for call in calls), 2)
        repeated = self.run_shell_refresh(fixture)
        self.assertEqual(repeated.returncode, 0, repeated.stdout + repeated.stderr)
        self.assertIn('changed=0', repeated.stdout)
        self.assertEqual(fixture[2].read_text(), events)

    def test_shell_refresh_check_mode_does_not_restart(self):
        fixture = self.shell_refresh_fixture('check')
        preview = self.run_shell_refresh(fixture, '--check')
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.assertFalse(fixture[2].exists())
        self.assertFalse((fixture[0] / 'profile/preferences.json').exists())

    def test_shell_refresh_without_running_desktop_succeeds(self):
        for runtime_exists in [False, True]:
            with self.subTest(runtime_exists=runtime_exists):
                fixture = self.shell_refresh_fixture(f'idle-{runtime_exists}', runtime_exists)
                fixture[3]['QS_TEST_MODE'] = 'none'
                applied = self.run_shell_refresh(fixture)
                self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
                if runtime_exists:
                    calls = [json.loads(line) for line in fixture[2].read_text().splitlines()]
                    self.assertEqual(len(calls), 1)
                    self.assertIn('kill', calls[0])
                else:
                    self.assertFalse(fixture[2].exists())

    def test_shell_refresh_reports_unexpected_errors(self):
        fixture = self.shell_refresh_fixture('error')
        fixture[3]['QS_TEST_MODE'] = 'error'
        applied = self.run_shell_refresh(fixture)
        self.assertEqual(applied.returncode, 2, applied.stdout + applied.stderr)
        self.assertIn('IPC connection denied', applied.stdout)

    def test_shell_refresh_does_not_run_after_failed_deployment(self):
        fixture = self.shell_refresh_fixture('failed-deployment')
        applied = self.run_shell_refresh(fixture, '-e', 'refresh_test_fail=true')
        self.assertEqual(applied.returncode, 2, applied.stdout + applied.stderr)
        self.assertFalse(fixture[2].exists())

    def test_all_shortcuts_unique_and_layout_switch_reserved(self):
        bindings = json.loads((self.profile / 'shortcuts.json').read_text())
        def canonical(key):
            parts = [part.strip().lower() for part in key.split('+')]
            return tuple(sorted(parts[:-1])) + (parts[-1],)
        keys = [(canonical(item['key']), item.get('release', False)) for item in bindings]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertNotIn((canonical('SUPER + Space'), False), keys)
        self.assertNotIn((canonical('SUPER + Space'), True), keys)
        self.assertTrue(all(sum(field in item for field in ['action', 'dispatcher', 'callback']) == 1 for item in bindings))
        self.assertTrue(all(not item.get('locked') for item in bindings if 'action' in item))

    def test_cancelled_capture_aliases_do_not_run_ocr_or_save(self):
        for action in ['screenshot-region-save', 'ocr']:
            with self.subTest(action=action), patch.object(self.actions.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '')), patch.object(self.actions, 'run') as run:
                self.actions.main(action)
                run.assert_not_called()

    def test_ocr_keeps_captured_data_in_local_process_stdin(self):
        with patch.object(self.actions.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '0,0 100x100\n')), patch.object(self.actions, 'run') as run:
            run.side_effect = [subprocess.CompletedProcess([], 0, b'png-data'),
                               subprocess.CompletedProcess([], 0, b'hello world'),
                               subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0)]
            self.actions.main('ocr')
            self.assertEqual(run.call_args_list[1].args, ('tesseract', 'stdin', 'stdout', '-l', 'eng'))
            self.assertEqual(run.call_args_list[1].kwargs['input'], b'png-data')
            self.assertEqual(run.call_args_list[2].args, ('wl-copy',))
            self.assertEqual(run.call_args_list[2].kwargs['input'], b'hello world')

    def test_record_stop_cannot_signal_unrelated_or_reused_pid(self):
        import signal
        loader = importlib.machinery.SourceFileLoader('recorder', str(ROLE / 'files/desktop-record'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        recorder = importlib.util.module_from_spec(spec)
        loader.exec_module(recorder)
        recorder.PROC = self.profile / 'proc'
        process = recorder.PROC / '123'
        process.mkdir(parents=True)
        state = self.profile / 'record.json'
        for command, start, permitted in [('/usr/bin/systemd', '456', False),
                                          ('/usr/bin/wf-recorder', '789', False),
                                          ('/usr/bin/wf-recorder', '456', True)]:
            with self.subTest(command=command, start=start):
                (process / 'cmdline').write_bytes(command.encode() + b'\0')
                (process / 'stat').write_text('123 (wf-recorder) S ' + '0 ' * 18 + start + '\n')
                state.write_text('{"pid":123,"start":"456"}')
                with patch.object(recorder.os, 'kill') as kill:
                    self.assertEqual(recorder.stop_recording(state), permitted)
                    if permitted: kill.assert_called_once_with(123, signal.SIGINT)
                    else: kill.assert_not_called()

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

    def popup_fixture(self):
        runtime = self.profile / 'popup-runtime'
        runtime.mkdir()
        program = self.profile / 'fake-popup.py'
        program.write_text('import sys, time\nprint(sys.stdin.read(), flush=True)\ntime.sleep(10)\n')
        environment = {'XDG_RUNTIME_DIR': str(runtime), 'HYPRLAND_INSTANCE_SIGNATURE': 'test-popup-session'}
        return runtime, environment, [sys.executable, str(program)]

    def wait_popup(self, runtime, name, future, previous=None):
        import time
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if future.done():
                future.result()  # Surface startup errors rather than timing out.
                self.fail('Popup exited before it could be toggled')
            paths = list(runtime.glob('*.json'))
            if paths:
                state = json.loads(paths[0].read_text())
                if state['name'] == name and state['token'] != previous and paths[0].with_suffix('.sock').exists():
                    return paths[0], state
            time.sleep(0.01)
        self.fail('Popup did not register')

    def test_popup_opens_and_toggles_without_proc_access(self):
        from concurrent.futures import ThreadPoolExecutor
        runtime, environment, args = self.popup_fixture()
        with patch.dict(os.environ, environment), \
             patch.object(Path, 'read_bytes', side_effect=PermissionError('proc access denied')), \
             ThreadPoolExecutor(max_workers=1) as executor:
            opened = executor.submit(self.actions.popup, 'Shortcuts', args, input='shortcut help',
                                     text=True, stdout=subprocess.PIPE)
            path, state = self.wait_popup(runtime, 'Shortcuts', opened)
            # Disk metadata is diagnostic only, never authority to choose a process.
            state['pid'] = 2147483647
            path.write_text(json.dumps(state))
            closed = self.actions.popup('Shortcuts', args, text=True)
            self.assertEqual(closed.returncode, 2)
            self.assertEqual(closed.stdout, '')
            self.assertNotEqual(opened.result(timeout=5).returncode, 0)
        # The deliberately altered diagnostic record can remain, but its controller
        # has exited and stale records do not prevent a subsequent popup.
        with patch.dict(os.environ, environment), ThreadPoolExecutor(max_workers=1) as executor:
            reopened = executor.submit(self.actions.popup, 'Shortcuts', args, input='',
                                       text=True, stdout=subprocess.PIPE)
            self.wait_popup(runtime, 'Shortcuts', reopened, previous=state['token'])
            self.assertEqual(self.actions.close_popup(next(runtime.glob('*.sock'))), 'Shortcuts')
            reopened.result(timeout=5)
        self.assertEqual(list(runtime.glob('*.json')), [])
        self.assertEqual(list(runtime.glob('*.sock')), [])

    def test_popup_switching_preserves_the_new_controller(self):
        from concurrent.futures import ThreadPoolExecutor
        runtime, environment, args = self.popup_fixture()
        with patch.dict(os.environ, environment), ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(self.actions.popup, 'launcher', args, input='',
                                    text=True, stdout=subprocess.PIPE)
            _, initial = self.wait_popup(runtime, 'launcher', first)
            second = executor.submit(self.actions.popup, 'Shortcuts', args, input='',
                                     text=True, stdout=subprocess.PIPE)
            path, replacement = self.wait_popup(runtime, 'Shortcuts', second)
            self.assertNotEqual(initial['token'], replacement['token'])
            self.assertNotEqual(first.result(timeout=5).returncode, 0)
            self.assertEqual(json.loads(path.read_text()), replacement)
            self.assertEqual(self.actions.close_popup(next(runtime.glob('*.sock'))), 'Shortcuts')
            second.result(timeout=5)
        self.assertEqual(list(runtime.glob('*.json')), [])
        self.assertEqual(list(runtime.glob('*.sock')), [])

    def test_popup_controller_rejects_other_users_and_unknown_requests(self):
        from unittest.mock import MagicMock
        import struct
        import threading
        for uid, request, accepted in [(os.getuid() + 1, b'close\n', False),
                                       (os.getuid(), b'kill 123\n', False),
                                       (os.getuid(), b'close\n', True)]:
            with self.subTest(uid=uid, request=request):
                connection = MagicMock()
                connection.__enter__.return_value = connection
                connection.getsockopt.return_value = struct.pack('3i', 777, uid, 0)
                connection.makefile.return_value.readline.return_value = request
                listener = MagicMock()
                listener.accept.side_effect = [(connection, None), OSError()]
                with patch.object(self.actions.signal, 'pidfd_send_signal') as send, \
                     patch.object(self.actions.select, 'select', side_effect=[([], [], []), ([321], [], [])]):
                    self.actions.control_popup(listener, 321, 'Shortcuts', threading.Event())
                    if accepted:
                        send.assert_called_once_with(321, self.actions.signal.SIGTERM)
                    else:
                        send.assert_not_called()

    def test_cancelled_screenshot_does_not_capture(self):
        with patch.object(self.actions.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '')), patch.object(self.actions, 'run') as run:
            self.actions.main('screenshot')
            run.assert_not_called()

    def test_power_actions_run_directly_without_confirmation(self):
        for action in ['poweroff', 'reboot', 'suspend', 'logout']:
            with self.subTest(action=action), patch.object(self.actions, 'menu') as menu, patch.object(self.actions, 'run') as run:
                self.actions.main(action)
                menu.assert_not_called()
                if action == 'logout':
                    run.assert_called_once_with('hyprctl', 'dispatch', 'hl.dsp.exit()')
                else:
                    run.assert_called_once_with('systemctl', action)

    def test_theme_preserves_wallpaper_and_managed_preferences(self):
        managed = (self.profile / 'preferences.json').read_bytes()
        (self.profile / 'state.json').write_text('{"wallpaper":"/tmp/picture.png"}')
        with patch.object(self.actions.subprocess, 'run'):
            self.actions.main('theme')
        state = json.loads((self.profile / 'state.json').read_text())
        self.assertTrue(state['light'])
        self.assertEqual(state['wallpaper'], '/tmp/picture.png')
        self.assertEqual((self.profile / 'preferences.json').read_bytes(), managed)

    def test_default_background_and_system_font_need_no_bundled_assets(self):
        from PIL import Image
        self.actions.refresh_theme({})
        generated = self.profile / 'theme/wallpaper.png'
        with Image.open(generated) as image:
            image.load()
            self.assertNotEqual(image.getpixel((0, 0)), image.getpixel((0, image.height - 1)))
        result = subprocess.run([sys.executable, str(self.profile / 'bin/lock-visuals'), 'clock'],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with Image.open(self.profile / 'theme/clock.png') as image:
            image.load()
        personal = self.profile / 'personal wallpaper.png'
        Image.new('RGB', (20, 20), color='red').save(personal)
        state = {'wallpaper': str(personal)}
        self.actions.refresh_theme(state)
        self.assertEqual(generated.read_bytes(), personal.read_bytes())
        self.assertEqual(json.loads((self.profile / 'state.json').read_text())['wallpaper'], str(personal))

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
            if path.is_file() and path.suffix.lower() not in ('.png', '.ttf'):
                self.assertIsNone(banned.search(path.read_text()), str(path))

if __name__ == '__main__':
    unittest.main()
