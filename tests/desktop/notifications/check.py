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
        ipc('quiet', 'true')
        ipc('opened', 'true')
        # Read the popup inside the same IPC call as the change: no timer or
        # external audio query should be needed before the new value is visible.
        ipc('resetAudio', '0.30', 'false')
        for expected in [35, 40, 45, 50]:
            changed = json.loads(ipc('changeAndRead', '5'))
            assert changed['ok'] and round(changed['volume'] * 100) == expected, changed
            assert changed['toast'] == f'Volume {expected}%', changed
        changed = json.loads(ipc('changeAndRead', '-5'))
        assert changed['ok'] and changed['toast'] == 'Volume 45%', changed
        ipc('resetAudio', '0.97', 'true')
        changed = json.loads(ipc('changeAndRead', '5'))
        assert changed['volume'] == 1 and changed['muted'] and changed['toast'] == 'Volume 100% (muted)', changed
        ipc('resetAudio', '0.03', 'false')
        changed = json.loads(ipc('changeAndRead', '-5'))
        assert changed['volume'] == 0 and changed['toast'] == 'Volume 0%', changed
        ipc('availability', 'false')
        changed = json.loads(ipc('changeAndRead', '5'))
        assert not changed['ok'] and changed['volume'] == 0 and changed['toast'] == 'Volume 0%', changed
        ipc('availability', 'true')
        changed = json.loads(ipc('changeAndRead', '101'))
        assert not changed['ok'] and changed['volume'] == 0, changed
        ipc('dismiss')
        ipc('volume', '35', 'false')
        assert status()['count'] == 0 and status()['toast'] == 'Volume 35%', status()
        time.sleep(0.8)
        ipc('volume', '40', 'true')
        assert status()['count'] == 0 and status()['toast'] == 'Volume 40% (muted)', status()
        ipc('volume', '101', 'false')
        assert status()['toast'] == 'Volume 40% (muted)', status()
        time.sleep(0.9)
        assert status()['toast'] == 'Volume 40% (muted)', status()
        time.sleep(0.7)
        assert status()['toast'] == '', status()
        ipc('volume', '50', 'false')
        ipc('dismiss')
        assert status()['toast'] == '' and status()['count'] == 0, status()
        ipc('battery', 'low', '20')
        assert status()['count'] == 1 and status()['toast'] == 'Battery low', status()
        ipc('volume', '55', 'false')
        assert status()['toast'] == 'Battery low', status()
        time.sleep(1.6)
        assert status()['toast'] == 'Battery low', status()
        ipc('quiet', 'false')
        ipc('quiet', 'true')
        ipc('opened', 'false')
        ipc('opened', 'true')
        assert status()['toast'] == 'Battery low', status()
        ipc('battery', 'critical', '10')
        assert status()['toast'] == 'Battery critically low', status()
        notify('Ordinary notification during critical battery')
        assert status()['toast'] == 'Battery critically low', status()
        ipc('battery', 'suspend', '2')
        assert status()['toast'] == 'Battery almost empty', status()
        ipc('charged')
        assert status()['toast'] == '', status()
        ipc('clear')
        assert status()['count'] == 0
        print('ARCHSETUP_NOTIFICATIONS_PASSED')
    finally:
        process.terminate()
        process.wait(timeout=5)
        log.seek(0)
        output = log.read()
        assert not any(message in output for message in ('TypeError', 'ReferenceError', 'Failed to load configuration')), output
