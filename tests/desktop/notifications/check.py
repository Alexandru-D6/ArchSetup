"""Runs only inside a private dbus-run-session, never on the user's bus."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

fixture = Path(sys.argv[1])
environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   XDG_RUNTIME_DIR=str(fixture / 'runtime'), XDG_CACHE_HOME=str(fixture / 'cache'), XDG_STATE_HOME=str(fixture / 'state'))
environment.pop('WAYLAND_DISPLAY', None)
(fixture / 'runtime').mkdir(mode=0o700)


def call(method, *args):
    result = subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.freedesktop.Notifications',
        '--object-path', '/org/freedesktop/Notifications', '--method', 'org.freedesktop.Notifications.' + method, *args],
        capture_output=True, text=True, timeout=5, env=environment)
    assert result.returncode == 0, result.stderr
    return result.stdout


def notify(summary, replaces=0, hints='{}', timeout=1000):
    result = call('Notify', 'Test', str(replaces), '', summary, 'A plain <body>', "['default', 'Open']", hints, str(timeout))
    return int(re.search(r'uint32 (\d+)', result)[1])


def ipc(method, *args):
    result = subprocess.run(['qs', '-p', str(fixture), 'ipc', 'call', 'test', method, *args],
        capture_output=True, text=True, timeout=5, env=environment)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def status(): return json.loads(ipc('status'))


with (fixture / 'log').open('w+') as log:
    process = subprocess.Popen(['qs', '-p', str(fixture), '--no-color'], env=environment, stdout=log, stderr=subprocess.STDOUT)
    try:
        for attempt in range(60):
            try:
                status()
                break
            except AssertionError:
                if process.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(0.05)
        else: raise AssertionError('Notification fixture never became ready')
        first = notify('First')
        time.sleep(0.15)
        assert status()['toast'] == 'First', status()
        assert status()['count'] == 1
        time.sleep(1)
        assert status()['toast'] == '', status()
        assert status()['count'] == 1  # Toast expiry retains session history.
        notify('Updated', replaces=first)
        assert status()['count'] == 1
        assert status()['entries'][0]['summary'] == 'Updated'
        call('CloseNotification', str(first))
        assert status()['count'] == 0
        notify('Transient', hints="{'transient': <true>}", timeout=200)
        assert status()['count'] == 0
        time.sleep(0.3)
        assert status()['toast'] == ''
        ipc('quiet', 'true')
        notify('Quiet')
        assert status()['count'] == 1 and status()['toast'] == ''
        ipc('quiet', 'false')
        ipc('opened', 'true')
        notify('Open panel')
        assert status()['count'] == 2 and status()['toast'] == ''
        ipc('opened', 'false')
        notify('Action')
        ipc('invoke')
        assert status()['count'] == 2
        ipc('clear')
        assert status()['count'] == 0
        assert status()['toast'] == ''
        print('ARCHSETUP_NOTIFICATIONS_PASSED')
    finally:
        process.terminate()
        process.wait(timeout=5)
        log.seek(0)
        output = log.read()
        assert not any(message in output for message in ('TypeError', 'ReferenceError', 'Failed to load configuration')), output
