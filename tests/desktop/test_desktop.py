#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import yaml
import jinja2

from render import render, ROLE
sys.path.insert(0, str(ROLE / 'files'))

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

    def allow_lock_power(self):
        path = self.profile / 'preferences.json'
        preferences = json.loads(path.read_text())
        preferences['lockPowerRequiresAuth'] = False
        path.write_text(json.dumps(preferences))

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

    def test_code_editor_preflight_requires_installation_outside_provisioning(self):
        executable = shutil.which('ansible-playbook') or str(Path(sys.executable).parent / 'ansible-playbook')
        if not Path(executable).exists():
            self.skipTest('ansible-playbook is required for code editor preflight regression')
        tasks = yaml.safe_load((ROLE / 'tasks/preflight.yml').read_text())
        editor_check = next(task for task in tasks if task['name'] == 'Require the requested code editor')
        environment = dict(os.environ, ANSIBLE_HOME=self.directory.name,
                           ANSIBLE_LOCAL_TEMP=str(Path(self.directory.name) / 'ansible-tmp'))
        cases = [(False, True, True, 'codium.desktop', True),
                 (False, False, True, 'codium.desktop', False),
                 (False, True, False, 'codium.desktop', False),
                 (False, True, True, 'geany.desktop', False),
                 (True, False, False, 'codium.desktop', True),
                 (True, False, False, 'geany.desktop', True)]
        for installed, provisioning, automatic, editor, allowed in cases:
            with self.subTest(installed=installed, provisioning=provisioning, automatic=automatic, editor=editor):
                playbook = Path(self.directory.name) / 'editor-preflight.yml'
                variables = {
                    'desktop_code_editor_entries': {'results': [{'stat': {'exists': installed}}]},
                    'archsetup_desktop_install_vscodium': automatic,
                    'archsetup_desktop_code_editor': editor,
                }
                if provisioning:
                    variables['desktop_code_editor_install_allowed'] = True
                playbook.write_text(yaml.safe_dump([{
                    'hosts': 'localhost', 'gather_facts': False, 'become': False,
                    'vars': variables, 'tasks': [editor_check]}]))
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

    def test_shutdown_request_opens_session_menu_without_powering_off(self):
        with patch.object(self.actions, 'run') as run:
            self.actions.main('poweroff')
            run.assert_called_once_with('qs', '-p', str(self.profile / 'shell'),
                                        'ipc', 'call', 'desktop', 'shutdown')

    def test_shortcut_help_uses_shell_overlay(self):
        with patch.object(self.actions, 'run') as run, patch.object(self.actions, 'menu') as menu:
            self.actions.main('help')
            run.assert_called_once_with('qs', '-p', str(self.profile / 'shell'),
                                        'ipc', 'call', 'desktop', 'toggle', 'help')
            menu.assert_not_called()

    def test_selected_session_actions_execute_without_reopening_menu(self):
        for action in ['poweroff-confirmed', 'reboot', 'suspend', 'hibernate', 'logout']:
            with self.subTest(action=action), patch.object(self.actions, 'menu') as menu, patch.object(self.actions, 'run') as run:
                self.actions.main(action)
                menu.assert_not_called()
                if action == 'logout':
                    run.assert_called_once_with('hyprctl', 'dispatch', 'hl.dsp.exit()')
                else:
                    run.assert_called_once_with('systemctl', 'poweroff' if action == 'poweroff-confirmed' else action)

    def test_firmware_setup_only_requests_reboot_into_firmware(self):
        failure = subprocess.CalledProcessError(1, ['systemctl', 'reboot', '--firmware-setup'])
        for error in [None, failure]:
            with self.subTest(error=error), patch.object(self.actions, 'run', side_effect=error) as run:
                if error:
                    with self.assertRaises(subprocess.CalledProcessError):
                        self.actions.main('firmware-setup')
                else:
                    self.actions.main('firmware-setup')
                run.assert_called_once_with('systemctl', 'reboot', '--firmware-setup')

    def test_firmware_setup_availability_uses_logind_capabilities(self):
        import io
        for capability, available in [('yes', True), ('challenge', True), ('no', False), ('na', False), ('inhibited', False), ('', False)]:
            with self.subTest(capability=capability), patch.object(self.actions.subprocess, 'run') as probe:
                probe.return_value.stdout = f's "{capability}"'
                output = io.StringIO()
                with patch.object(sys, 'stdout', output):
                    self.actions.main('status')
                self.assertEqual(json.loads(output.getvalue())['canFirmwareSetup'], available)
                self.assertTrue(any(call.args[0][-1] == 'CanRebootToFirmwareSetup' for call in probe.call_args_list))

    def lock_visuals(self):
        loader = importlib.machinery.SourceFileLoader('lock_visuals', str(ROLE / 'files/lock-visuals'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        visuals = importlib.util.module_from_spec(spec)
        loader.exec_module(visuals)
        visuals.ROOT = self.profile
        return visuals

    def native_lock_only(self):
        # Exercise the compatibility path independently of the animated UI.
        (self.profile / 'lock/shell.qml').unlink()

    def test_qml_session_and_lock_controls(self):
        executable = Path('/usr/lib/qt6/bin/qmltestrunner')
        if not executable.is_file(): self.skipTest('Qt 6 qmltestrunner is required')
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           QT_QUICK_CONTROLS_STYLE='Basic', QML_XHR_ALLOW_FILE_READ='1',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'))
        result = subprocess.run([executable, '-input', str(Path(__file__).parent / 'qml'), '-o', '-,txt'],
                                env=environment, capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_time_center_touchpad_gestures_move_content(self):
        compiler, pkg_config = shutil.which('c++'), shutil.which('pkg-config')
        if not compiler or not pkg_config:
            self.skipTest('A C++ compiler and Qt 6 development files are required')
        flags = subprocess.run([pkg_config, '--cflags', '--libs', 'Qt6Quick', 'Qt6Test'],
                               capture_output=True, text=True)
        if flags.returncode:
            self.skipTest('Qt 6 Quick and Test development files are required')
        fixture = self.profile / 'gesture-validation'
        shutil.copytree(Path(__file__).parent / 'gestures', fixture)
        for component in ['TimeCenter.qml', 'SettingsButton.qml', 'SettingsComboBox.qml']:
            shutil.copy2(self.profile / 'shell' / component, fixture / component)
        executable = fixture / 'test-gestures'
        result = subprocess.run([compiler, '-fPIC', '-std=c++17', str(fixture / 'timecenter.cpp'),
                                 '-o', str(executable), *shlex.split(flags.stdout)],
                                capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           QT_QUICK_CONTROLS_STYLE='Basic',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'))
        result = subprocess.run([str(executable), str(fixture / 'shell.qml')], env=environment,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('ARCHSETUP_TIME_CENTER_GESTURES_PASSED', result.stdout)

    def test_animated_lock_clock_keeps_last_frame_visible_during_reload(self):
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        from io import BytesIO
        import threading
        from PIL import Image
        executable = Path('/usr/lib/qt6/bin/qmltestrunner')
        if not executable.is_file(): self.skipTest('Qt 6 qmltestrunner is required')
        frames = {}
        for index, color in enumerate(['red', 'lime', 'blue']):
            output = BytesIO()
            Image.new('RGBA', (750, 780), color).save(output, format='PNG')
            frames[f'/frame-{index}.png'] = output.getvalue()

        class ClockFrames(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != '/frame-0.png': time.sleep(0.5)
                self.send_response(200)
                self.send_header('Content-Type', 'image/png')
                self.end_headers()
                try: self.wfile.write(frames[self.path])
                except BrokenPipeError: pass  # Qt may exit early after a failed assertion.

            def log_message(self, *args): pass

        with ThreadingHTTPServer(('127.0.0.1', 0), ClockFrames) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                fixture = self.profile / 'clock-validation'
                fixture.mkdir()
                source = (Path(__file__).parent / 'clock/tst_lockscreen.qml').read_text()
                source = source.replace('"../../../roles/desktop/files/lock"', '"../lock"')
                source = source.replace('http://127.0.0.1:0', f'http://127.0.0.1:{server.server_port}')
                (fixture / 'tst_lockscreen.qml').write_text(source)
                environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                                   QT_QUICK_CONTROLS_STYLE='Basic', XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'))
                result = subprocess.run([executable, '-input', str(fixture), '-o', '-,txt'],
                                        env=environment, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            finally:
                server.shutdown()
                worker.join(timeout=5)

    def test_quickshell_pam_with_isolated_policies_and_dummy_response(self):
        executable = shutil.which('qs')
        if executable is None: self.skipTest('Quickshell is required')
        fixture = self.profile / 'pam-validation'
        shutil.copytree(Path(__file__).parent / 'pam', fixture)
        shutil.copy2(ROLE / 'files/lock/LockAuth.qml', fixture / 'LockAuth.qml')
        checker = fixture / 'check-response'
        checker.chmod(0o755)
        for policy, arguments in [('prompt-accept', ''), ('prompt-deny', ' reject')]:
            (fixture / policy).write_text(f'auth required pam_exec.so expose_authtok quiet {checker}{arguments}\n')
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'),
                           XDG_CACHE_HOME=str(self.profile / 'cache'), XDG_STATE_HOME=str(self.profile / 'qs-state'))
        environment.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run([executable, '-p', str(fixture), '--no-color'],
                                env=environment, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('ARCHSETUP_PAM_FIXTURES_PASSED', output)
        self.assertNotIn('dummy response', output)

    def test_animated_lock_configuration_loads_in_quickshell(self):
        executable = shutil.which('qs')
        if executable is None: self.skipTest('Quickshell is required')
        private = self.profile / 'lock-session'
        private.mkdir(mode=0o700)
        for power, label in [('poweroff', 'Power off'), ('reboot', 'Reboot')]:
            (private / f'lock-{power}.label').write_text(label + '\n')
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'),
                           XDG_CACHE_HOME=str(self.profile / 'cache'), XDG_STATE_HOME=str(self.profile / 'qs-state'),
                           ARCHSETUP_LOCK_DIR=str(private), WAYLAND_DISPLAY='not-a-real-display',
                           HYPRLAND_INSTANCE_SIGNATURE='archsetup-lock-configuration-check')
        # The offscreen backend cannot lock a compositor. It still loads the
        # production config and detects imports/property errors without touching
        # a real desktop or invoking authentication.
        with subprocess.Popen([executable, '-p', str(self.profile / 'lock'), '--no-color'], env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            try:
                output = process.communicate(timeout=2)[0]
            except subprocess.TimeoutExpired:
                process.terminate()
                output = process.communicate(timeout=5)[0]
        self.assertIn('Configuration Loaded', output)
        self.assertNotIn('Failed to load configuration', output)
        self.assertFalse((private / 'authenticated').exists())

    def test_world_clocks_use_system_timezone_database(self):
        executable = shutil.which('qs')
        if executable is None: self.skipTest('Quickshell is required')
        fixture = self.profile / 'worldclock-validation'
        shutil.copytree(Path(__file__).parent / 'worldclock', fixture)
        shutil.copy2(self.profile / 'shell/WorldClockSource.qml', fixture / 'WorldClockSource.qml')
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'),
                           XDG_CACHE_HOME=str(self.profile / 'cache'), XDG_STATE_HOME=str(self.profile / 'qs-state'))
        environment.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run([executable, '-p', str(fixture), '--no-color'], env=environment,
                                capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('ARCHSETUP_WORLD_CLOCKS_PASSED', output)
        for error in ['Failed to load configuration', 'TypeError', 'ReferenceError']:
            self.assertNotIn(error, output)

    def test_shortcut_help_loads_and_watches_map_in_quickshell(self):
        executable = shutil.which('qs')
        if executable is None: self.skipTest('Quickshell is required')
        fixture = self.profile / 'shortcut-validation'
        shutil.copytree(Path(__file__).parent / 'shortcuts', fixture)
        for component in ['ShortcutHelp.qml', 'ShortcutSource.qml', 'CenteredWindowFrame.qml', 'SettingsButton.qml']:
            shutil.copy2(self.profile / 'shell' / component, fixture / component)
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           XDG_RUNTIME_DIR=str(self.profile / '.runtime-validation'),
                           XDG_CACHE_HOME=str(self.profile / 'cache'), XDG_STATE_HOME=str(self.profile / 'qs-state'))
        environment.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run([executable, '-p', str(fixture), '--no-color'], env=environment,
                                capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('ARCHSETUP_SHORTCUT_FIXTURES_PASSED', output)
        for error in ['Failed to load configuration', 'TypeError', 'ReferenceError']:
            self.assertNotIn(error, output)

    def test_animated_lock_authenticates_before_normal_exit_and_cleans_up(self):
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'animated-lock', 'XDG_RUNTIME_DIR': self.directory.name}
        locker, updater = Mock(pid=123), Mock()
        locker.wait.return_value = 0
        def launch(arguments, **kwargs):
            if arguments[0] == 'qs':
                private = Path(kwargs['env']['ARCHSETUP_LOCK_DIR'])
                self.assertEqual(arguments, ['qs', '-p', str(self.profile / 'lock')])
                self.assertEqual((private / 'lock-poweroff.label').read_text(), 'Power off\n')
                self.assertFalse((self.profile / 'theme/lock-clock.png').exists())
                (private / 'authenticated').write_text('authenticated\n')
                return locker
            self.assertEqual(arguments[1], 'watch')
            return updater
        with patch.dict(os.environ, environment), patch.object(self.actions, 'run'), \
             patch.object(self.actions.subprocess, 'Popen', side_effect=launch) as spawn:
            self.actions.main('lock')
        self.assertEqual(spawn.call_count, 2)
        locker.wait.assert_called_once_with()
        updater.terminate.assert_called_once_with()
        updater.wait.assert_called_once_with(timeout=3)
        self.assertFalse(Path(spawn.call_args_list[0].kwargs['env']['ARCHSETUP_LOCK_DIR']).exists())

    def test_incomplete_settings_templates_do_not_block_lock_startup(self):
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'settings-template-failure',
                       'XDG_RUNTIME_DIR': self.directory.name}
        locker, updater = Mock(pid=123), Mock()
        locker.wait.return_value = 0
        def launch(arguments, **kwargs):
            if arguments[0] == 'qs':
                private = Path(kwargs['env']['ARCHSETUP_LOCK_DIR'])
                self.assertIn('pam:module = archsetup-hyprlock', (private / 'hyprlock.conf').read_text())
                (private / 'authenticated').write_text('authenticated\n')
                return locker
            return updater
        with patch.dict(os.environ, environment), patch.object(self.actions.subprocess, 'Popen', side_effect=launch) as spawn, \
             patch.object(self.actions, 'native_lock_configuration', side_effect=OSError('Missing power template')), \
             patch.object(self.actions, 'stop_recording_for_lock'):
            self.actions.main('lock')
        locker.wait.assert_called_once_with()
        updater.terminate.assert_called_once_with()
        updater.wait.assert_called_once_with(timeout=3)
        self.assertFalse(Path(spawn.call_args_list[0].kwargs['env']['ARCHSETUP_LOCK_DIR']).exists())

    def test_recording_cleanup_errors_do_not_prevent_lock_or_fallback(self):
        import contextlib
        import io
        for failure in [OSError('recorder unavailable'),
                        subprocess.CalledProcessError(1, ['record-stop']),
                        subprocess.TimeoutExpired(['record-stop'], 2)]:
            with self.subTest(failure=type(failure).__name__):
                environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'failed-recorder',
                               'XDG_RUNTIME_DIR': self.directory.name}
                animated, updater, native = Mock(), Mock(), Mock()
                animated.wait.return_value = 1
                native.wait.return_value = 0
                errors = io.StringIO()
                with patch.dict(os.environ, environment), \
                     patch.object(self.actions, 'run', side_effect=failure), \
                     patch.object(self.actions.subprocess, 'Popen', side_effect=[animated, updater, native]) as spawn, \
                     contextlib.redirect_stderr(errors):
                    self.actions.main('lock')
                self.assertEqual([call.args[0][0] for call in spawn.call_args_list],
                                 ['qs', str(self.profile / 'bin/lock-visuals'), 'hyprlock'])
                native.wait.assert_called_once_with()
                self.assertIn('locking continues', errors.getvalue())

    def test_pending_recording_selection_does_not_delay_lock_or_fallback(self):
        # Run the real launcher and recording controller with isolated stubs.
        # No compositor, authentication, recording or power command touches the host.
        for crashed in [False, True]:
            with self.subTest(crashed=crashed):
                directory = self.profile / ('pending-selection-' + str(crashed))
                directory.mkdir()
                stubs = directory / 'bin'
                stubs.mkdir()
                marker = directory / 'locker-started'
                started = directory / 'selection-started'
                release = directory / 'release-selection'
                scripts = {
                    'slurp': 'import time\nfrom pathlib import Path\n'
                             + f'Path({str(started)!r}).touch()\n'
                             + f'while not Path({str(release)!r}).exists(): time.sleep(0.01)\n'
                             + 'raise SystemExit(1)\n',
                    'qs': 'import os\nfrom pathlib import Path\n'
                          + ('raise SystemExit(1)\n' if crashed else
                             f'Path({str(marker)!r}).touch()\n'
                             + 'Path(os.environ["ARCHSETUP_LOCK_DIR"], "authenticated").touch()\n'),
                    'hyprlock': 'from pathlib import Path\n' + f'Path({str(marker)!r}).touch()\n',
                }
                for name, body in scripts.items():
                    script = stubs / name
                    script.write_text('#!' + sys.executable + '\n' + body)
                    script.chmod(0o755)
                updater = self.profile / 'bin/lock-visuals'
                updater.write_text('#!' + sys.executable + '\n')
                environment = dict(os.environ, XDG_RUNTIME_DIR=str(directory),
                                   HYPRLAND_INSTANCE_SIGNATURE='pending-region-audit',
                                   PATH=str(stubs) + os.pathsep + os.environ['PATH'])
                environment.pop('WAYLAND_DISPLAY', None)
                region = subprocess.Popen([sys.executable, str(self.profile / 'bin/desktop-record'), 'record-region'],
                                          env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                lock = None
                def wait_for(path):
                    deadline = time.monotonic() + 3
                    while not path.exists():
                        self.assertIsNone(region.poll(), 'Selection exited before cancellation')
                        self.assertLess(time.monotonic(), deadline, f'Timed out waiting for {path.name}')
                        time.sleep(0.01)
                try:
                    wait_for(started)
                    lock = subprocess.Popen([sys.executable, str(self.profile / 'bin/desktop-action'), 'lock'],
                                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    wait_for(marker)
                    # The lock and its fallback must start while selection still
                    # owns the recorder guard. Cleanup must then time out itself.
                    self.assertFalse(release.exists())
                    _, error = lock.communicate(timeout=4)
                    self.assertEqual(lock.returncode, 0, error.decode())
                    self.assertIn(b'locking continues', error)
                    self.assertIsNone(region.poll())
                finally:
                    release.touch()
                    region.communicate(timeout=3)
                    if lock is not None:
                        if lock.poll() is None:
                            lock.terminate()
                        lock.communicate(timeout=3)

    def test_animated_lock_without_success_marker_falls_back_even_on_zero_exit(self):
        for result in [0, 1, -11]:
            with self.subTest(result=result):
                environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'failed-animated-lock', 'XDG_RUNTIME_DIR': self.directory.name}
                animated, updater, native = Mock(pid=123), Mock(), Mock(pid=124)
                animated.wait.return_value = result
                native.wait.return_value = 0
                with patch.dict(os.environ, environment), patch.object(self.actions, 'run'), \
                     patch.object(self.actions.subprocess, 'Popen', side_effect=[animated, updater, native]) as spawn:
                    self.actions.main('lock')
                self.assertEqual([call.args[0][0] for call in spawn.call_args_list], ['qs', str(self.profile / 'bin/lock-visuals'), 'hyprlock'])
                native.wait.assert_called_once_with()
                updater.terminate.assert_called_once_with()
                self.assertFalse(Path(spawn.call_args_list[0].kwargs['env']['ARCHSETUP_LOCK_DIR']).exists())

    def test_missing_animated_lock_runtime_uses_native_locker(self):
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'missing-qs', 'XDG_RUNTIME_DIR': self.directory.name}
        native, updater = Mock(pid=123), Mock()
        native.wait.return_value = 0
        with patch.dict(os.environ, environment), patch.object(self.actions, 'run'), \
             patch.object(self.actions.subprocess, 'Popen', side_effect=[OSError('missing qs'), native, updater]) as spawn:
            self.actions.main('lock')
        self.assertEqual(spawn.call_args_list[1].args[0][0], 'hyprlock')
        native.wait.assert_called_once_with()
        updater.terminate.assert_called_once_with()

    def test_keyboard_identity_maps_real_xkb_names_and_queries_only_once(self):
        visuals = self.lock_visuals()
        devices = {'keyboards': [{'main': True, 'active_keymap': 'English (intl., with AltGr dead keys)', 'capsLock': True}]}
        with patch.object(visuals.subprocess, 'check_output', return_value=json.dumps(devices)) as query:
            info = json.loads(visuals.keyboard_info())
        self.assertEqual(set(info['layouts'].values()), {'US · Euro', 'US · AltGr'})
        self.assertEqual(info['layouts'][info['active']], 'US · AltGr')
        self.assertTrue(info['capsLock'])
        query.assert_called_once_with(['hyprctl', '-j', 'devices'], text=True, timeout=2)

    def test_lock_clock_updates_its_time_day_and_month(self):
        from datetime import datetime
        from PIL import Image
        visuals = self.lock_visuals()
        visuals.lock_clock_image(datetime(2026, 10, 12, 15, 12, 35))
        with Image.open(self.profile / 'theme/lock-clock.png') as generated:
            before = generated.copy()
        self.assertEqual(before.size, (750, 780))
        self.assertEqual(before.getpixel((0, 0))[3], 0)
        visuals.lock_clock_image(datetime(2026, 10, 13, 15, 12, 35))
        with Image.open(self.profile / 'theme/lock-clock.png') as after:
            self.assertNotEqual(before.crop((0, 45, 225, 255)).tobytes(),
                                after.crop((0, 45, 225, 255)).tobytes())
            self.assertEqual(before.crop((520, 550, 735, 750)).tobytes(),
                             after.crop((520, 550, 735, 750)).tobytes())
        visuals.lock_clock_image(datetime(2026, 11, 12, 15, 13, 36))
        with Image.open(self.profile / 'theme/lock-clock.png') as after:
            self.assertNotEqual(before.crop((520, 550, 735, 750)).tobytes(),
                                after.crop((520, 550, 735, 750)).tobytes())
            self.assertNotEqual(before.crop((250, 210, 500, 585)).tobytes(),
                                after.crop((250, 210, 500, 585)).tobytes())

    def test_configured_layouts_keep_variant_order_and_empty_slots(self):
        visuals = self.lock_visuals()
        self.assertEqual(visuals.configured_layouts({
            'keyboardLayouts': 'us,us', 'keyboardVariants': 'euro,altgr-intl',
        }), ['US · Euro', 'US · AltGr'])
        self.assertEqual(visuals.configured_layouts({
            'keyboardLayouts': 'es,us,de', 'keyboardVariants': ',intl',
        }), ['ES', 'US · Intl', 'DE'])
        self.assertEqual(visuals.configured_layouts({}), ['US'])

    def test_native_layout_badge_fits_names_and_is_idempotent(self):
        import math
        import re
        import shlex
        from xml.etree import ElementTree
        from PIL import ImageFont
        visuals = self.lock_visuals()
        self.assertEqual(visuals.identity_config('alex'), 'changed')
        path = self.profile / 'lock-identity.conf'
        content = path.read_text()
        self.assertIn('cmd[update:100:1] printf %s $LAYOUT[', content)
        self.assertIn('alex  ·  US · Euro', content)
        self.assertIn('alex  ·  US · AltGr', content)
        self.assertNotIn('hyprctl', content)
        self.assertNotIn('reload_time', content)
        original_mtime = path.stat().st_mtime_ns
        self.assertEqual(visuals.identity_config('alex'), 'unchanged')
        self.assertEqual(path.stat().st_mtime_ns, original_mtime)
        visuals.identity_config('a_very_long_desktop_username', ['US · Euro', 'US · AltGr'])
        content = path.read_text()
        width = int(re.search(r'size = (\d+), 50', content)[1])
        self.assertLessEqual(width, 196)
        size = int(re.search(r'<span size="(\d+)">', content)[1]) / 1024
        self.assertEqual(size, json.loads((self.profile / 'preferences.json').read_text())['controlFontSize'])
        font = ImageFont.truetype(visuals.font_file(), round(size * 4))
        arguments = re.search(r'\$LAYOUT\[(.*?)\]', content)[1].split(',')
        names = [ElementTree.fromstring(shlex.split(argument)[0]).text for argument in arguments]
        for name, variant in zip(names, ['Euro', 'AltGr']):
            self.assertTrue(name.endswith('US · ' + variant))
            self.assertIn('…', name)
            self.assertLessEqual(math.ceil(font.getlength(name) / 3) + 32, width)

    def test_native_layout_badge_escapes_markup_and_mapping_delimiters(self):
        import re
        import shlex
        from xml.etree import ElementTree
        visuals = self.lock_visuals()
        visuals.identity_config("a'lex", ['A&B', 'x,[y]<z>#'])
        content = (self.profile / 'lock-identity.conf').read_text()
        names = re.search(r'\$LAYOUT\[(.*?)\]', content)[1].split(',')
        self.assertEqual(len(names), 2)
        self.assertEqual([ElementTree.fromstring(shlex.split(name.replace('##', '#'))[0]).text
                          for name in names], ["a'lex  ·  A&B", "a'lex  ·  x,[y]<z>#"])

    def test_lock_starts_without_image_preparation_and_with_native_power_labels(self):
        render(self.profile, {'archsetup_desktop_lock_require_auth_for_power': False})
        self.native_lock_only()
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-compositor',
                       'XDG_RUNTIME_DIR': self.directory.name}
        locker, updater = Mock(pid=123), Mock()
        locker.wait.return_value = 0
        configurations = []
        def launch(arguments, **kwargs):
            if arguments[0] == 'hyprlock':
                run.assert_not_called()
                configurations.append(Path(arguments[2]).read_text())
                private = Path(kwargs['env']['ARCHSETUP_LOCK_DIR'])
                for action, label in [('poweroff', 'Power off'), ('reboot', 'Reboot')]:
                    self.assertEqual((private / f'lock-{action}.label').read_text(), label + '\n')
                refresh.assert_not_called()
                self.assertFalse(any(call.args[-1] == 'prepare' for call in run.call_args_list))
                return locker
            return updater
        with patch.dict(os.environ, environment), patch.object(self.actions, 'refresh_theme') as refresh, \
             patch.object(self.actions, 'run') as run, \
             patch.object(self.actions.subprocess, 'Popen', side_effect=launch) as spawn:
            self.actions.main('lock')
            private = Path(spawn.call_args_list[0].kwargs['env']['ARCHSETUP_LOCK_DIR'])
            run.assert_called_once_with(str(self.profile / 'bin/desktop-record'), 'record-stop', timeout=2,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
            self.assertEqual(spawn.call_args_list[0].args,
                             (['hyprlock', '-c', str(private / 'hyprlock.conf')],))
            self.assertEqual(spawn.call_args_list[1].args,
                             ([str(self.profile / 'bin/lock-visuals'), 'watch', str(os.getpid())],))
            self.assertNotIn('pass_fds', spawn.call_args_list[1].kwargs)
            self.assertEqual(spawn.call_args_list[1].kwargs['env'], spawn.call_args_list[0].kwargs['env'])
            for action in ['poweroff', 'reboot']:
                self.assertIn(str(private / f'lock-{action}.label'), configurations[0])
                self.assertNotIn(str(self.profile / f'theme/lock-{action}.label'), configurations[0])
            self.assertIn('pam:module = archsetup-hyprlock', configurations[0])
            self.assertFalse(private.exists())
            locker.wait.assert_called_once_with()
            updater.terminate.assert_called_once_with()
            updater.wait.assert_called_once_with(timeout=3)
        config = (self.profile / 'hyprlock.conf').read_text()
        self.assertIn('hide_cursor = false', config)
        self.assertIn('immediate_render = true', config)
        self.assertNotIn('reload_cmd =', config)
        self.assertIn('animation = inputFieldDots, 0', config)
        clock = config.split('path = ' + str(self.profile / 'theme/lock-clock.png'))[1].split('}')[0]
        self.assertIn('reload_time = 1', clock)
        self.assertIn(f'source = {self.profile}/lock-identity.conf', config)
        self.assertNotIn('lock-identity.png', config)
        import re
        for action, width in [('poweroff', 136), ('reboot', 120)]:
            onclick = f'onclick = {self.profile}/bin/lock-visuals click-{action}'
            self.assertEqual(config.count(onclick), 1, 'Overlapping widgets must send only one click')
            button = next(block for block in re.findall(r'shape \{(.*?)\n\}', config, re.S) if onclick in block)
            self.assertIn(f'size = {width - 2}, 48', button)
            self.assertIn('border_size = 1', button)
            self.assertIn(f'cmd[update:100:1] cat "{self.profile}/theme/lock-{action}.label"', config)

    def test_first_lock_starts_before_uncached_images_exist(self):
        self.native_lock_only()
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-first-lock', 'XDG_RUNTIME_DIR': self.directory.name}
        locker, updater = Mock(pid=123), Mock()
        locker.wait.return_value = 0
        def launch(arguments, **kwargs):
            if arguments[0] == 'hyprlock':
                private = Path(kwargs['env']['ARCHSETUP_LOCK_DIR'])
                self.assertEqual((private / 'lock-poweroff.label').read_text(), 'Power off\n')
                self.assertEqual((private / 'lock-reboot.label').read_text(), 'Reboot\n')
                self.assertFalse((self.profile / 'theme').exists())
                self.assertIn('immediate_render = true', Path(arguments[2]).read_text())
                return locker
            return updater
        with patch.dict(os.environ, environment), patch.object(self.actions, 'run') as run, \
             patch.object(self.actions.subprocess, 'Popen', side_effect=launch):
            self.actions.main('lock')
            run.assert_called_once_with(str(self.profile / 'bin/desktop-record'), 'record-stop', timeout=2,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)

    def test_lock_stops_image_updater_if_hyprlock_fails(self):
        self.native_lock_only()
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-compositor',
                       'XDG_RUNTIME_DIR': self.directory.name}
        locker, updater = Mock(pid=123), Mock()
        locker.wait.return_value = 1
        with patch.dict(os.environ, environment), patch.object(self.actions, 'refresh_theme'), \
             patch.object(self.actions, 'run'), \
             patch.object(self.actions.subprocess, 'Popen', side_effect=[locker, updater]):
            with self.assertRaises(subprocess.CalledProcessError):
                self.actions.main('lock')
            updater.terminate.assert_called_once_with()
            updater.wait.assert_called_once_with(timeout=3)

    def test_image_updater_startup_failure_still_waits_for_hyprlock(self):
        self.native_lock_only()
        import contextlib
        import io
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-compositor',
                       'XDG_RUNTIME_DIR': self.directory.name}
        locker = Mock(pid=123)
        locker.wait.return_value = 0
        errors = io.StringIO()
        with patch.dict(os.environ, environment), patch.object(self.actions, 'refresh_theme'), \
             patch.object(self.actions, 'run'), \
             patch.object(self.actions.subprocess, 'Popen', side_effect=[locker, OSError('unavailable')]), \
             contextlib.redirect_stderr(errors):
            self.actions.main('lock')
        locker.wait.assert_called_once_with()
        locker.terminate.assert_not_called()
        self.assertIn('Lock image updater unavailable', errors.getvalue())

    def test_locker_inherits_refresh_signal_block_and_parent_mask_is_restored(self):
        self.native_lock_only()
        import signal
        ready = self.profile / 'locker-signal-mask'
        locker = self.profile / 'bin/hyprlock'
        locker.write_text('#!/usr/bin/env python3\nimport os, signal, time\nfrom pathlib import Path\n'
                          + 'assert signal.SIGUSR2 in signal.pthread_sigmask(signal.SIG_BLOCK, set())\n'
                          + 'signal.signal(signal.SIGUSR2, lambda *_: os._exit(42))\n'
                          + 'os.kill(os.getpid(), signal.SIGUSR2)\ntime.sleep(0.1)\n'
                          + 'assert signal.SIGUSR2 in signal.sigpending()\n'
                          + f'Path({str(ready)!r}).write_text("refresh blocked")\n')
        locker.chmod(0o755)
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-masked-lock',
                       'XDG_RUNTIME_DIR': self.directory.name,
                       'PATH': os.pathsep.join([str(locker.parent), str(Path(sys.executable).parent),
                                               os.environ['PATH']])}
        original = signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGUSR2})
        try:
            baseline = signal.pthread_sigmask(signal.SIG_BLOCK, set())
            self.assertNotIn(signal.SIGUSR2, baseline)
            with patch.dict(os.environ, environment), patch.object(self.actions, 'run'):
                self.actions.main('lock')
            self.assertEqual(ready.read_text(), 'refresh blocked')
            self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), baseline)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, original)

    def test_failed_locker_start_restores_parent_signal_mask(self):
        self.native_lock_only()
        import signal
        environment = {'HYPRLAND_INSTANCE_SIGNATURE': 'test-failed-lock',
                       'XDG_RUNTIME_DIR': self.directory.name}
        original = signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGUSR2})
        try:
            baseline = signal.pthread_sigmask(signal.SIG_BLOCK, set())
            self.assertNotIn(signal.SIGUSR2, baseline)
            with patch.dict(os.environ, environment), patch.object(self.actions, 'run'), \
                 patch.object(self.actions.subprocess, 'Popen', side_effect=OSError('unavailable')):
                with self.assertRaises(OSError):
                    self.actions.main('lock')
            self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), baseline)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, original)

    def test_lock_power_policy_renders_both_modes(self):
        for required in [True, False]:
            with self.subTest(required=required):
                profile = render(self.profile / str(required), {
                    'archsetup_desktop_lock_require_auth_for_power': required})
                preferences = json.loads((profile / 'preferences.json').read_text())
                self.assertIs(preferences['lockPowerRequiresAuth'], required)
                native = (profile / 'hyprlock.conf').read_text()
                for action in ['poweroff', 'reboot']:
                    self.assertEqual(f'click-{action}' in native, not required)
                    self.assertEqual(f'lock-{action}.label' in native, not required)
                self.assertIn('pam:enabled = true', native)
                self.assertIn('pam:module = archsetup-hyprlock', native)
        self.assertIs(json.loads((self.profile / 'preferences.json').read_text())['lockPowerRequiresAuth'], True)

    def test_lock_power_policy_fails_closed_and_blocks_direct_requests(self):
        visuals = self.lock_visuals()
        preferences = self.profile / 'preferences.json'
        for content in [None, '{', '{}', '[]', 'null',
                        '{"lockPowerRequiresAuth": true}',
                        '{"lockPowerRequiresAuth": "false"}',
                        '{"lockPowerRequiresAuth": 0}']:
            with self.subTest(content=content):
                if content is None:
                    preferences.unlink(missing_ok=True)
                else:
                    preferences.write_text(content)
                paint, execute = Mock(), Mock()
                buttons = visuals.PowerControls(paint=paint, execute=execute)
                with patch.object(visuals.subprocess, 'run') as run, \
                     patch.object(visuals.socket, 'socket') as socket:
                    for action in ['poweroff', 'reboot']:
                        self.assertFalse(buttons.press(action))
                        self.assertFalse(buttons.press(action))
                        with self.assertRaises(PermissionError):
                            visuals.click_power(action)
                        with self.assertRaises(PermissionError):
                            visuals.power_action(action)
                    run.assert_not_called()
                    socket.assert_not_called()
                    execute.assert_not_called()
                    paint.assert_not_called()

    def test_requiring_unlock_cancels_pending_power_confirmation(self):
        self.allow_lock_power()
        visuals = self.lock_visuals()
        paint, execute = Mock(), Mock()
        buttons = visuals.PowerControls(paint=paint, execute=execute)
        self.assertTrue(buttons.press('poweroff'))
        preferences = self.profile / 'preferences.json'
        preferences.write_text('{"lockPowerRequiresAuth": true}')
        self.assertFalse(buttons.press('poweroff'))
        self.assertIsNone(buttons.selected)
        paint.assert_called_with(None)
        execute.assert_not_called()
        self.allow_lock_power()
        self.assertTrue(buttons.press('poweroff'))
        execute.assert_not_called()

    def test_locked_power_controller_rejects_raw_socket_requests(self):
        import socket
        private = self.profile / 'restricted-lock'
        private.mkdir(mode=0o700)
        log = self.profile / 'unexpected-power-action'
        systemctl = self.profile / 'bin/systemctl'
        systemctl.write_text('#!' + sys.executable + '\nfrom pathlib import Path\n'
                            + f'Path({str(log)!r}).touch()\n')
        systemctl.chmod(0o755)
        environment = dict(os.environ, ARCHSETUP_LOCK_DIR=str(private),
                           PATH=str(systemctl.parent) + os.pathsep + os.environ['PATH'])
        updater = subprocess.Popen([sys.executable, str(self.profile / 'bin/lock-visuals'), 'watch', str(os.getpid())],
                                   env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            endpoint = private / 'control.sock'
            clock = self.profile / 'theme/lock-clock.png'
            deadline = time.monotonic() + 4
            while not endpoint.exists() or not (private / 'lock-reboot.label').exists() or not clock.exists():
                self.assertIsNone(updater.poll())
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.01)
            before = clock.stat().st_mtime_ns
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
                client.connect(str(endpoint))
                for request in [b'p', b'p', b'r', b'r']:
                    client.send(request)
            # Wait for a full visual refresh, ensuring the controller has had
            # time to consume the datagrams between its clock updates.
            deadline = time.monotonic() + 4
            while not clock.exists() or clock.stat().st_mtime_ns == before:
                self.assertIsNone(updater.poll())
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.02)
            self.assertFalse(log.exists())
            self.assertEqual((private / 'lock-poweroff.label').read_text(), 'Power off\n')
            self.assertEqual((private / 'lock-reboot.label').read_text(), 'Reboot\n')
        finally:
            updater.terminate()
            _, error = updater.communicate(timeout=3)
        self.assertEqual(updater.returncode, 0, error.decode())

    def test_lock_power_buttons_confirm_selected_action_or_cancel(self):
        self.allow_lock_power()
        visuals = self.lock_visuals()
        for selected, other in [('poweroff', 'reboot'), ('reboot', 'poweroff')]:
            with self.subTest(selected=selected):
                paint, execute = Mock(), Mock()
                buttons = visuals.PowerControls(paint=paint, execute=execute)
                self.assertTrue(buttons.press(selected))
                paint.assert_called_once_with(selected)
                execute.assert_not_called()
                self.assertTrue(buttons.press(other))
                self.assertIsNone(buttons.selected)
                self.assertEqual(paint.call_args.args, (None,))
                execute.assert_not_called()
                self.assertTrue(buttons.press(selected))
                buttons.press(selected)
                execute.assert_called_once_with(selected)
                buttons.press(selected)
                buttons.press(other)
                execute.assert_called_once_with(selected)

    def test_failed_power_confirmation_restores_original_buttons(self):
        self.allow_lock_power()
        import contextlib
        import io
        visuals = self.lock_visuals()
        paint = Mock()
        execute = Mock(side_effect=subprocess.CalledProcessError(1, ['systemctl', 'reboot']))
        buttons = visuals.PowerControls(paint=paint, execute=execute)
        buttons.press('reboot')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertTrue(buttons.press('reboot'))
        execute.assert_called_once_with('reboot')
        self.assertEqual(paint.call_args.args, (None,))
        self.assertIsNone(buttons.selected)
        self.assertTrue(buttons.press('poweroff'))
        self.assertEqual(paint.call_args.args, ('poweroff',))

    def test_confirmed_lock_power_actions_call_systemctl(self):
        self.allow_lock_power()
        visuals = self.lock_visuals()
        for action in ['poweroff', 'reboot']:
            with self.subTest(action=action), patch.object(visuals.subprocess, 'run') as run:
                visuals.power_action(action)
                run.assert_called_once_with(['systemctl', action], check=True)
        with patch.object(visuals.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                visuals.power_action('suspend')
            run.assert_not_called()

    def test_power_labels_change_and_reset_in_private_directory(self):
        visuals = self.lock_visuals()
        private = self.profile / 'power-images'
        private.mkdir(mode=0o700)
        actions = ['poweroff', 'reboot']
        with patch.dict(os.environ, {'ARCHSETUP_LOCK_DIR': str(private)}):
            visuals.power_labels()
            original = {name: (private / f'lock-{name}.label').read_text() for name in actions}
            for selected in ['poweroff', 'reboot', None]:
                visuals.power_labels(selected)
                for action in actions:
                    expected = original[action] if selected is None else ('Confirm\n' if selected == action else 'Cancel\n')
                    self.assertEqual((private / f'lock-{action}.label').read_text(), expected)
                    self.assertFalse((self.profile / f'theme/lock-{action}.label').exists())

    def test_power_control_messages_require_valid_button_and_same_user(self):
        import socket
        import struct
        visuals = self.lock_visuals()
        control = Mock()
        for uid, data, flags, expected in [
            (os.getuid(), b'p', 0, 'poweroff'), (os.getuid(), b'r', 0, 'reboot'),
            (os.getuid() + 1, b'p', 0, None), (os.getuid(), b'pp', 0, None),
            (os.getuid(), b'p', socket.MSG_TRUNC, None),
        ]:
            with self.subTest(uid=uid, data=data, flags=flags):
                control.recvmsg.return_value = (data, [(socket.SOL_SOCKET, socket.SCM_CREDENTIALS,
                                                       struct.pack('3i', os.getpid(), uid, os.getgid()))], flags, None)
                self.assertEqual(visuals.receive_power(control), expected)

    def test_live_lock_power_controller_confirms_cancels_and_cleans_up(self):
        self.allow_lock_power()
        # Keep the real desktop helper so an accidental session-menu request is
        # observable. Stub only the final system commands; never reboot the host.
        for selected, other in [('poweroff', 'reboot'), ('reboot', 'poweroff')]:
            with self.subTest(selected=selected):
                private = self.profile / ('lock-session-' + selected)
                private.mkdir(mode=0o700)
                log = self.profile / ('power-actions-' + selected)
                systemctl = self.profile / 'bin/systemctl'
                systemctl.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n'
                                     + f'with Path({str(log)!r}).open("a") as output: output.write(" ".join(sys.argv[1:]) + "\\n")\n')
                systemctl.chmod(0o755)
                qs = self.profile / 'bin/qs'
                qs.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                              + f'Path({str(log)!r}).write_text("unexpected session menu\\n")\n')
                qs.chmod(0o755)
                environment = dict(os.environ, ARCHSETUP_LOCK_DIR=str(private), XDG_RUNTIME_DIR=str(self.profile),
                                   HYPRLAND_INSTANCE_SIGNATURE='test-controls',
                                   PATH=os.pathsep.join([str(systemctl.parent), str(Path(sys.executable).parent),
                                                        os.environ['PATH']]))
                updater = subprocess.Popen([sys.executable, str(self.profile / 'bin/lock-visuals'), 'watch', str(os.getpid())],
                                           env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                def wait_until(condition):
                    deadline = time.monotonic() + 3
                    while not condition():
                        self.assertIsNone(updater.poll(), 'Power controller stopped unexpectedly')
                        self.assertLess(time.monotonic(), deadline, 'Power controls did not update')
                        time.sleep(0.01)
                def click(name):
                    result = subprocess.run([sys.executable, str(self.profile / 'bin/lock-visuals'), f'click-{name}'],
                                            env=environment, capture_output=True, timeout=3)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                try:
                    endpoint = private / 'control.sock'
                    labels = {name: private / f'lock-{name}.label' for name in ['poweroff', 'reboot']}
                    wait_until(lambda: endpoint.exists() and all(path.exists() for path in labels.values()))
                    originals = {name: path.read_text() for name, path in labels.items()}
                    self.assertEqual(endpoint.stat().st_mode & 0o777, 0o600)
                    click(selected)
                    wait_until(lambda: labels[selected].read_text() == 'Confirm\n' and labels[other].read_text() == 'Cancel\n')
                    self.assertFalse(log.exists())
                    click(other)
                    wait_until(lambda: all(path.read_text() == originals[name] for name, path in labels.items()))
                    self.assertFalse(log.exists())
                    click(selected)
                    wait_until(lambda: labels[selected].read_text() == 'Confirm\n')
                    started = time.monotonic()
                    click(selected)
                    wait_until(log.exists)
                    self.assertLess(time.monotonic() - started, 1, 'Confirmation still waits a full second')
                    self.assertEqual(log.read_text(), selected + '\n')
                    click(selected)
                    self.assertEqual(log.read_text(), selected + '\n')
                finally:
                    updater.terminate()
                    _, error = updater.communicate(timeout=3)
                self.assertEqual(updater.returncode, 0, error.decode())
                self.assertFalse(endpoint.exists())

    def test_background_lock_updates_clock_without_querying_keyboard(self):
        probes = self.profile / 'keyboard-probes'
        hyprctl = self.profile / 'bin/hyprctl'
        hyprctl.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                           + f'Path({str(probes)!r}).touch()\n')
        hyprctl.chmod(0o755)
        self.lock_visuals().identity_config('alex')
        identity = self.profile / 'lock-identity.conf'
        identity_mtime = identity.stat().st_mtime_ns
        environment = dict(os.environ, PATH=str(hyprctl.parent) + os.pathsep + os.environ['PATH'],
                           XDG_RUNTIME_DIR=self.directory.name, HYPRLAND_INSTANCE_SIGNATURE='test-compositor')
        updater = subprocess.Popen([sys.executable, str(self.profile / 'bin/lock-visuals'), 'watch', str(os.getpid())],
                                   env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        def wait_until(condition):
            deadline = time.monotonic() + 10
            while not condition():
                self.assertIsNone(updater.poll(), 'Lock image updater stopped unexpectedly')
                self.assertLess(time.monotonic(), deadline, 'Lock assets did not update')
                time.sleep(0.05)
        try:
            clock = self.profile / 'theme/lock-clock.png'
            wait_until(clock.exists)
            clock_mtime = clock.stat().st_mtime_ns
            before = clock.read_bytes()
            wait_until(lambda: clock.stat().st_mtime_ns != clock_mtime)
            self.assertNotEqual(clock.read_bytes(), before)
            self.assertEqual(identity.stat().st_mtime_ns, identity_mtime)
            self.assertFalse(probes.exists(), 'Native layout labels must not query hyprctl')
        finally:
            updater.terminate()
            _, error = updater.communicate(timeout=3)
        self.assertFalse(error, error.decode())
        final_mtime = clock.stat().st_mtime_ns
        result = subprocess.run([sys.executable, str(self.profile / 'bin/lock-visuals'), 'watch', '-1'],
                                env=environment, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(clock.stat().st_mtime_ns, final_mtime)

    def test_live_image_updates_never_signal_a_legacy_locker_descriptor(self):
        self.allow_lock_power()
        unexpected = self.profile / 'unexpected-lock-refresh'
        code = ('import signal, time\nfrom pathlib import Path\n'
                + f'signal.signal(signal.SIGUSR2, lambda *_: Path({str(unexpected)!r}).touch())\n'
                + 'print("ready", flush=True)\nwhile True: time.sleep(1)\n')
        private = self.profile / 'lock-session'
        private.mkdir(mode=0o700)
        environment = dict(os.environ, ARCHSETUP_LOCK_DIR=str(private), XDG_RUNTIME_DIR=str(self.profile),
                           HYPRLAND_INSTANCE_SIGNATURE='test-no-refresh-signal')
        with subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE) as locker:
            self.assertEqual(locker.stdout.readline(), b'ready\n')
            descriptor = os.pidfd_open(locker.pid)
            updater = None
            try:
                updater = subprocess.Popen([sys.executable, str(self.profile / 'bin/lock-visuals'),
                                            'watch', str(os.getpid()), str(descriptor)], pass_fds=(descriptor,),
                                           env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                def wait_until(condition):
                    deadline = time.monotonic() + 5
                    while not condition():
                        self.assertIsNone(updater.poll())
                        self.assertIsNone(locker.poll())
                        self.assertLess(time.monotonic(), deadline, 'Image updater did not progress')
                        time.sleep(0.02)
                clock = self.profile / 'theme/lock-clock.png'
                button = private / 'lock-poweroff.label'
                wait_until(lambda: clock.exists() and button.exists())
                before_clock = clock.stat().st_mtime_ns
                wait_until(lambda: clock.stat().st_mtime_ns != before_clock)
                before_button = button.read_bytes()
                for selected in ['poweroff', 'reboot']:
                    result = subprocess.run([sys.executable, str(self.profile / 'bin/lock-visuals'),
                                             f'click-{selected}'], env=environment, capture_output=True, timeout=3)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    if selected == 'poweroff':
                        wait_until(lambda: button.read_bytes() != before_button)
                    else:
                        wait_until(lambda: button.read_bytes() == before_button)
                self.assertFalse(unexpected.exists(), 'Updater entered the unsafe SIGUSR2 refresh handler')
            finally:
                error = b''
                if updater is not None:
                    updater.terminate()
                    _, error = updater.communicate(timeout=3)
                os.close(descriptor)
                locker.terminate()
                self.assertFalse(error, error.decode())

    def test_theme_preserves_wallpaper_and_managed_preferences(self):
        managed = (self.profile / 'preferences.json').read_bytes()
        (self.profile / 'state.json').write_text('{"wallpaper":"/tmp/picture.png","theme":"rose","light":false}')
        with patch.object(self.actions.subprocess, 'run'):
            self.actions.main('theme')
        state = json.loads((self.profile / 'state.json').read_text())
        self.assertTrue(state['light'])
        self.assertEqual(state['wallpaper'], '/tmp/picture.png')
        self.assertEqual(state['theme'], 'rose')
        # Selecting a preset persists it; refreshes and mode changes retain the
        # wallpaper and the explicit choice even when the managed default differs.
        with patch.object(self.actions, 'menu', return_value='Material'), patch.object(self.actions.subprocess, 'run'):
            self.actions.main('theme-select')
        self.actions.main('refresh-theme')
        state = json.loads((self.profile / 'state.json').read_text())
        self.assertEqual(state['theme'], 'material')
        self.assertFalse(state['light'])
        self.assertEqual(state['wallpaper'], '/tmp/picture.png')
        with patch.object(self.actions.subprocess, 'run'):
            self.actions.main('theme')
        state = json.loads((self.profile / 'state.json').read_text())
        self.assertEqual(state['theme'], 'material')
        self.assertTrue(state['light'])
        self.assertEqual((self.profile / 'preferences.json').read_bytes(), managed)

    def test_desktop_background_and_font_are_independent_of_lock_wallpaper(self):
        from PIL import Image
        lock_wallpaper = (self.profile / 'assets/lock-wallpaper.jpg').read_bytes()
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
        self.assertEqual((self.profile / 'assets/lock-wallpaper.jpg').read_bytes(), lock_wallpaper)
        self.assertIn(str(self.profile / 'assets/lock-wallpaper.jpg'),
                      (self.profile / 'hyprlock.conf').read_text())

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
            if path.is_file() and path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp', '.ttf'):
                self.assertIsNone(banned.search(path.read_text()), str(path))

if __name__ == '__main__':
    unittest.main()
