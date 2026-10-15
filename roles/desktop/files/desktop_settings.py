"""Validated desktop settings and transactions for system timezone and input."""
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from zoneinfo import ZoneInfo

import desktop_system as system


POWER_FIELD = 'general.lockPowerRequiresAuth'
POWER_START = '# archsetup-lock-power-start\n'
POWER_END = '# archsetup-lock-power-end\n'
TIMEZONE_FIELD = 'general.timezone'
LAYOUTS_FIELD = 'general.keyboard.layouts'
DESKTOP_FIELD = 'general.clockPlacement.desktop'
LOCK_FIELD = 'general.clockPlacement.lockScreen'
FIELDS = {POWER_FIELD, TIMEZONE_FIELD, LAYOUTS_FIELD, DESKTOP_FIELD, LOCK_FIELD}
CLOCK_START = '# archsetup-lock-clock-start\n'
CLOCK_END = '# archsetup-lock-clock-end\n'
GENERATED = ['settings-input.lua', 'lock-identity.conf', 'theme/lock-identity.conf']


class SettingsError(ValueError):
    def __init__(self, code, message, fields=None, snapshot=None):
        super().__init__(message)
        self.code = code
        self.fields = fields or {}
        self.snapshot = snapshot


def parse_json(text):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key: ' + key)
            result[key] = value
        return result
    def invalid_constant(value):
        raise ValueError('Invalid JSON number: ' + value)
    return json.loads(text, object_pairs_hook=unique_object, parse_constant=invalid_constant)


def read_document(path, default=None):
    try:
        document = parse_json(path.read_text())
        if not isinstance(document, dict):
            raise ValueError('Expected a JSON object')
        return document
    except FileNotFoundError:
        if default is not None:
            return default
        raise SettingsError('read', 'Cannot read ' + path.name + '.') from None
    except (OSError, ValueError, UnicodeError):
        raise SettingsError('read', 'Cannot read ' + path.name + '; repair the file before applying settings.') from None


def documents(root):
    preferences = read_document(root / 'preferences.json')
    saved = read_document(root / 'settings.json', {'schemaVersion': 1, 'revision': 0, 'general': {}})
    if (type(saved.get('schemaVersion')) is not int or saved['schemaVersion'] != 1
            or type(saved.get('revision')) is not int or saved['revision'] < 0
            or not isinstance(saved.get('general'), dict)):
        raise SettingsError('schema', 'Unsupported or invalid settings.json; repair the file before applying settings.')
    general = saved['general']
    if 'lockPowerRequiresAuth' in general and type(general['lockPowerRequiresAuth']) is not bool:
        raise SettingsError('validation', 'Require unlock must be enabled or disabled.',
                            {POWER_FIELD: 'Choose enabled or disabled.'})
    positions = general.get('clockPlacement', {})
    if not isinstance(positions, dict):
        raise SettingsError('schema', 'Invalid clock placement in settings.json.')
    for key, value in positions.items():
        if key in ('desktop', 'lockScreen'):
            validate_position(value, 'general.clockPlacement.' + key)
    if 'keyboard' in general:
        if not isinstance(general['keyboard'], dict) or 'layouts' not in general['keyboard']:
            raise SettingsError('schema', 'Invalid keyboard settings in settings.json.')
        validate_layout_shape(general['keyboard']['layouts'])
    return preferences, saved


def default_layouts(preferences):
    variants = preferences.get('keyboardVariants', '').split(',')
    return [{'layout': code.strip(), 'variant': variants[index].strip() if index < len(variants) else ''}
            for index, code in enumerate(preferences.get('keyboardLayouts', 'us').split(','))]


def validate_position(value, field):
    if value is not None and (not isinstance(value, dict) or set(value) != {'x', 'y'} or any(
            type(number) not in (int, float) or not math.isfinite(number) or not 0 <= number <= 1
            for number in value.values())):
        raise SettingsError('validation', 'Clock positions must be between 0% and 100%.',
                            {field: 'Use a valid position or Default.'})


def validate_layout_shape(value):
    if (not isinstance(value, list) or not 1 <= len(value) <= system.MAX_LAYOUTS or any(
            not isinstance(item, dict) or set(item) != {'layout', 'variant'} or any(
                not isinstance(text, str) for text in item.values()) for item in value)):
        raise SettingsError('validation', 'Choose between one and four keyboard layouts.',
                            {LAYOUTS_FIELD: 'At least one layout is required; up to four are supported.'})


def validate_layouts(value, preferences):
    validate_layout_shape(value)
    catalog = {item['id']: {variant['id'] for variant in item['variants']} for item in system.keyboard_catalog()}
    pairs = [(item['layout'], item['variant']) for item in value]
    if len(set(pairs)) != len(pairs) or any(layout not in catalog or variant not in catalog[layout] for layout, variant in pairs):
        raise SettingsError('validation', 'Choose installed layouts and their matching variants; remove duplicate pairs.',
                            {LAYOUTS_FIELD: 'Each layout/variant pair must be installed and unique.'})
    try:
        system.layout_names(value, preferences)
    except (OSError, RuntimeError) as error:
        raise SettingsError('validation', str(error), {LAYOUTS_FIELD: str(error)}) from None


def resolve(preferences, saved):
    effective = dict(preferences)
    effective['lockPowerRequiresAuth'] = saved['general'].get(
        'lockPowerRequiresAuth', preferences.get('lockPowerRequiresAuth') is not False)
    layouts = saved['general'].get('keyboard', {}).get('layouts', default_layouts(preferences))
    effective['keyboardLayouts'] = ','.join(item['layout'] for item in layouts)
    effective['keyboardVariants'] = ','.join(item['variant'] for item in layouts)
    effective['clockPlacement'] = {'desktop': None, 'lockScreen': None, **saved['general'].get('clockPlacement', {})}
    return effective


def effective_preferences(root):
    """A corrupt override must never enable lock-screen power requests."""
    try:
        preferences, saved = documents(root)
        return resolve(preferences, saved)
    except SettingsError:
        return {'lockPowerRequiresAuth': True}


def observed_state():
    return {'timezone': system.timezone_name(), 'keyboard': system.observe_keyboard()}


def snapshot_from(preferences, saved, observed=None):
    observed = observed if observed is not None else observed_state()
    fingerprint = {'timezone': observed['timezone'], 'keyboard': None}
    if observed['keyboard']:
        keyboard = observed['keyboard']
        fingerprint['keyboard'] = {key: keyboard[key] for key in ('layout', 'variant', 'file')}
        fingerprint['keyboard']['devices'] = [{key: item.get(key) for key in ('name', 'layout', 'variant')}
                                               for item in keyboard['keyboards']]
    encoded = json.dumps([preferences, saved, fingerprint], sort_keys=True, separators=(',', ':'), allow_nan=False)
    effective = resolve(preferences, saved)
    effective['timezone'] = observed['timezone']
    return {'revision': hashlib.sha256(encoded.encode()).hexdigest(),
            'values': {POWER_FIELD: effective['lockPowerRequiresAuth'], TIMEZONE_FIELD: observed['timezone'],
                       DESKTOP_FIELD: effective['clockPlacement']['desktop'], LOCK_FIELD: effective['clockPlacement']['lockScreen'],
                       LAYOUTS_FIELD: saved['general'].get('keyboard', {}).get('layouts', default_layouts(preferences))},
            'preferences': effective,
            'runtime': {'inSession': observed['keyboard'] is not None,
                        'activeLayout': next((item.get('active_keymap', '') for item in (observed['keyboard'] or {}).get('keyboards', []) if item.get('main')), '')}}


def snapshot(root, allow_recovery=False):
    if not allow_recovery and (root / '.settings-recovery.json').exists():
        try:
            with (root / '.settings.lock').open() as guard:
                try:
                    fcntl.flock(guard, fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise SettingsError('busy', 'Settings are being applied. Wait for the current request to finish.') from None
                if (root / '.settings-recovery.json').exists():
                    raise SettingsError('recovery', 'A previous Apply was interrupted. Choose Recover to reconcile the saved and system settings.')
        except FileNotFoundError:
            raise SettingsError('recovery', 'A previous Apply was interrupted. Choose Recover to reconcile the saved and system settings.') from None
    return snapshot_from(*documents(root))


def clock_snapshot(zone=None, now=None):
    zone = zone or system.timezone_name()
    timezone = ZoneInfo(zone)
    now = (now or datetime.now(timezone))
    now = now.replace(tzinfo=timezone) if now.tzinfo is None else now.astimezone(timezone)
    minutes = int(now.utcoffset().total_seconds() / 60)
    return {'timezone': zone, 'timestamp': now.timestamp(), 'iso': now.isoformat(),
            'time': now.strftime('%H:%M'), 'date': now.strftime('%A, %B %-d'), 'shortDate': now.strftime('%-d %b'),
            'utcOffset': 'UTC' + ('+' if minutes >= 0 else '−') + f'{abs(minutes) // 60:02}:{abs(minutes) % 60:02}'}


def catalog():
    return {'timezones': [{'id': zone, 'name': zone.replace('_', ' ')} for zone in system.timezone_catalog()],
            'layouts': system.keyboard_catalog(), 'maxLayouts': system.MAX_LAYOUTS}


def placement_rect(position, width, height, widget_width, widget_height, margins, default):
    left, top, right, bottom = margins
    maximum_x = max(left, width - right - widget_width)
    maximum_y = max(top, height - bottom - widget_height)
    x, y = default if position is None else (left + position['x'] * (maximum_x - left), top + position['y'] * (maximum_y - top))
    return round(min(maximum_x, max(left, x))), round(min(maximum_y, max(top, y)))


def native_clock(root, preferences, monitors):
    """Hyprlock uses bottom-up offsets; monitor dimensions are logical pixels."""
    position = preferences.get('clockPlacement', {}).get('lockScreen')
    blocks = []
    font = preferences.get('font', 'DejaVu Sans')
    points = int(preferences.get('controlFontSize', 12))
    line = math.ceil(points * 4 / 3 * 1.3)
    for monitor in monitors:
        name = monitor.get('name', '')
        if not re.fullmatch(r'[A-Za-z0-9_.:-]+', name):
            continue
        scale = monitor.get('scale', 1)
        width, height = monitor['width'] / scale, monitor['height'] / scale
        if monitor.get('transform', 0) % 2:
            width, height = height, width
        caption = 20 + line * 2 + 8
        if height - 64 - 140 <= caption + 4 or width <= 32:
            continue
        image_width = max(1, min(250, width * 0.4, height * 0.45, (height - 64 - 140 - caption) * 250 / 260))
        image_height = image_width * 260 / 250
        group_width = min(width - 32, max(image_width, 300))
        group_height = image_height + caption
        left, top = placement_rect(position, width, height, group_width, group_height, (16, 64, 16, 140),
                                   ((width - group_width) / 2, (height - image_height) / 2))
        image_left = left + (group_width - image_width) / 2
        blocks.append(f'''image {{
    monitor = {name}
    path = {root}/theme/lock-clock.png
    size = {round(image_width)}
    rounding = 0
    border_size = 0
    reload_time = 1
    position = {round(image_left)}, {-top}
    halign = left
    valign = top
    zindex = 1
}}
''')
        for text, y in [('Locked', top + image_height + 20),
                        (f'cmd[update:1000] "{root}/bin/desktop-settings" date', top + image_height + 20 + line + 8)]:
            blocks.append(f'''label {{
    monitor = {name}
    text = {text}
    color = rgba(f0eaffff)
    font_size = {points}
    font_family = {font}
    position = {round(left + group_width / 2 - width / 2)}, {-round(y)}
    halign = center
    valign = top
    zindex = 1
}}
''')
    return ''.join(blocks)


def native_lock_configuration(root, configuration, preferences=None):
    """Build the next session's private lock config from current effective values.

    The launcher snapshots configuration into its private session directory.
    Placement changes take effect on the next lock without restarting a locker.
    """
    if (configuration.count(POWER_START) != 1 or configuration.count(POWER_END) != 1
            or configuration.index(POWER_START) > configuration.index(POWER_END)):
        raise SettingsError('native-config', 'The native lock configuration needs to be reapplied.')
    before, tail = configuration.split(POWER_START)
    _, after = tail.split(POWER_END)
    preferences = preferences if preferences is not None else effective_preferences(root)
    power = ''
    if preferences.get('lockPowerRequiresAuth') is False:
        base = root / 'lock-power.conf'
        themed = root / 'theme/lock-power.conf'
        path = themed if themed.exists() and themed.stat().st_mtime_ns >= base.stat().st_mtime_ns else base
        power = path.read_text()
    configuration = before + POWER_START + power + POWER_END + after
    if preferences.get('clockPlacement', {}).get('lockScreen') is not None:
        if (configuration.count(CLOCK_START) != 1 or configuration.count(CLOCK_END) != 1
                or configuration.index(CLOCK_START) > configuration.index(CLOCK_END)):
            raise SettingsError('native-config', 'Reapply the desktop profile before changing clock placement.')
        try:
            monitors = system.monitors()
            if monitors:
                before, tail = configuration.split(CLOCK_START, 1)
                _, after = tail.split(CLOCK_END, 1)
                configuration = before + CLOCK_START + native_clock(root, preferences, monitors) + CLOCK_END + after
        except (OSError, RuntimeError, ValueError, KeyError, TypeError, ArithmeticError, subprocess.SubprocessError):
            raise SettingsError('native-config', 'Cannot read monitor geometry for custom clock placement.') from None
    # A freshly generated identity file wins over an older themed copy.
    identity = root / 'lock-identity.conf'
    themed_identity = root / 'theme/lock-identity.conf'
    if identity.exists() and (not themed_identity.exists() or identity.stat().st_mtime_ns > themed_identity.stat().st_mtime_ns):
        configuration = configuration.replace(str(themed_identity), str(identity))
    return configuration


def atomic_save(path, document):
    atomic_text(path, json.dumps(document, indent=2, allow_nan=False) + '\n')


def atomic_text(path, content):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.settings-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def apply(root, revision, changes):
    if not isinstance(changes, dict) or not changes or set(changes) - FIELDS:
        raise SettingsError('validation', 'The request contains an unsupported setting.')
    if POWER_FIELD in changes and type(changes[POWER_FIELD]) is not bool:
        raise SettingsError('validation', 'Require unlock must be enabled or disabled.',
                            {POWER_FIELD: 'Choose enabled or disabled.'})
    for field in (DESKTOP_FIELD, LOCK_FIELD):
        if field in changes:
            validate_position(changes[field], field)
    if TIMEZONE_FIELD in changes and (not isinstance(changes[TIMEZONE_FIELD], str) or changes[TIMEZONE_FIELD] not in system.timezone_catalog()):
        raise SettingsError('validation', 'Choose an installed timezone.', {TIMEZONE_FIELD: 'Choose a timezone from the installed catalog.'})
    # All writers use this same lock, including separate Configuration processes.
    descriptor = os.open(root / '.settings.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, 'r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        preferences, saved = documents(root)
        if (root / '.settings-recovery.json').exists():
            raise SettingsError('recovery', 'A previous Apply was interrupted. Choose Recover before applying more changes.')
        observed = observed_state()
        current = snapshot_from(preferences, saved, observed)
        if revision != current['revision']:
            raise SettingsError('conflict', 'Settings changed elsewhere. Revert to reload the current values.', snapshot=current)
        if all(current['values'][key] == value for key, value in changes.items()):
            return current
        updated = parse_json(json.dumps(saved))
        updated['revision'] += 1
        general = updated['general']
        for field, value in changes.items():
            if field == POWER_FIELD:
                general['lockPowerRequiresAuth'] = value
            elif field in (DESKTOP_FIELD, LOCK_FIELD):
                general.setdefault('clockPlacement', {})[field.rsplit('.', 1)[1]] = value
            elif field == LAYOUTS_FIELD:
                general['keyboard'] = {'layouts': value}
        layouts = general.get('keyboard', {}).get('layouts', default_layouts(preferences))
        validate_layouts(layouts, preferences)
        effective = resolve(preferences, updated)
        # Stage and validate the native configuration before committing. The
        # locker will generate its private copy from the committed values.
        native_lock_configuration(root, (root / 'hyprlock.conf').read_text(), effective)
        keyboard_changed = LAYOUTS_FIELD in changes and changes[LAYOUTS_FIELD] != current['values'][LAYOUTS_FIELD]
        timezone = changes.get(TIMEZONE_FIELD, observed['timezone'])
        timezone_changed = timezone != observed['timezone']
        staged = {}
        if keyboard_changed:
            if observed['keyboard'] and observed['keyboard']['file']:
                raise SettingsError('system', 'A custom keyboard keymap overrides layout selection. Review your input configuration.')
            staged['settings-input.lua'] = system.input_text(layouts)
            try:
                system.validate_input(root, staged['settings-input.lua'])
                staged['lock-identity.conf'] = system.command([sys.executable, str(root / 'bin/lock-visuals'), 'render-identity'],
                                                            input=json.dumps(effective), timeout=10)
                staged['theme/lock-identity.conf'] = themed_lock_text(root, staged['lock-identity.conf'])
            except (RuntimeError, subprocess.SubprocessError) as error:
                raise SettingsError('system', 'Cannot prepare keyboard configuration: ' + str(error), {LAYOUTS_FIELD: str(error)}) from None
        # Check defaults again in case Ansible changed them during staging.
        if snapshot(root)['revision'] != revision:
            raise SettingsError('conflict', 'Settings changed elsewhere. Revert to reload the current values.', snapshot=snapshot(root))
        journal = {'oldSaved': saved, 'newSaved': updated, 'oldTimezone': observed['timezone'], 'newTimezone': timezone,
                   'oldKeyboard': observed['keyboard'], 'oldFiles': {name: (root / name).read_text() if (root / name).exists() else None for name in staged}}
        external = keyboard_changed or timezone_changed
        if external:
            atomic_save(root / '.settings-recovery.json', journal)
        try:
            if timezone_changed:
                system.set_timezone(timezone)
            for name, content in staged.items():
                (root / name).parent.mkdir(exist_ok=True)
                atomic_text(root / name, content)
            if keyboard_changed:
                system.reload_keyboard(layouts, observed['keyboard'])
            atomic_save(root / 'settings.json', updated)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            failures = rollback(root, journal) if external else []
            if failures:
                raise SettingsError('recovery', 'Apply did not finish. Recovery is required: ' + '; '.join(failures),
                                    snapshot=snapshot(root, allow_recovery=True)) from None
            if external:
                (root / '.settings-recovery.json').unlink(missing_ok=True)
            raise SettingsError('system', 'Changes were not saved. ' + str(error)) from None
        if external:
            (root / '.settings-recovery.json').unlink(missing_ok=True)
        return snapshot(root)


def themed_lock_text(root, text):
    palette_path = root / 'theme/palette.json'
    if not palette_path.exists():
        return text
    palette = read_document(palette_path)
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if re.match(r'\s*(?:color|border_color|inner_color|outer_color)\s*=', line):
            for original, key in [('292332', 'raised'), ('eae0f5', 'ink'), ('45404f', 'outline')]:
                line = line.replace(original, palette.get(key, '#' + original).removeprefix('#'))
            lines[index] = line
    return ''.join(lines)


def rollback(root, journal, interactive=False):
    failures = []
    for name, content in journal['oldFiles'].items():
        try:
            if name not in GENERATED:
                raise ValueError('Invalid recovery output')
            if content is None:
                (root / name).unlink(missing_ok=True)
            else:
                atomic_text(root / name, content)
        except (OSError, ValueError) as error:
            failures.append('Cannot restore ' + name + ': ' + str(error))
    if journal['oldFiles'] and system.in_session():
        try:
            old = journal.get('oldKeyboard')
            layouts = default_layouts({'keyboardLayouts': old['layout'], 'keyboardVariants': old['variant']}) if old else default_layouts(
                resolve(*documents(root)))
            system.reload_keyboard(layouts, old)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            failures.append('Cannot restore keyboard configuration: ' + str(error))
    if journal['newTimezone'] != journal['oldTimezone']:
        current = system.timezone_name()
        if current == journal['newTimezone']:
            try:
                system.set_timezone(journal['oldTimezone'], interactive=interactive)
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                failures.append('Cannot restore timezone (currently ' + system.timezone_name() + '): ' + str(error))
        elif current != journal['oldTimezone']:
            failures.append('The timezone was changed externally to ' + current + '; review it before recovery.')
    return failures


def recover(root):
    descriptor = os.open(root / '.settings.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, 'r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        recover_locked(root)
    return snapshot(root)


def recover_locked(root):
    path = root / '.settings-recovery.json'
    if not path.exists():
        return
    journal = read_document(path)
    if (not all(isinstance(journal.get(key), dict) for key in ('oldSaved', 'newSaved', 'oldFiles'))
            or not all(isinstance(journal.get(key), str) for key in ('oldTimezone', 'newTimezone'))
            or set(journal['oldFiles']) - set(GENERATED)
            or any(content is not None and not isinstance(content, str) for content in journal['oldFiles'].values())):
        raise SettingsError('recovery', 'Invalid recovery record; repair .settings-recovery.json before applying settings.')
    old = journal.get('oldKeyboard')
    if old is not None and (not isinstance(old, dict) or not all(isinstance(old.get(key), str) for key in ('layout', 'variant'))
                            or not isinstance(old.get('keyboards'), list)):
        raise SettingsError('recovery', 'Invalid keyboard recovery record.')
    current = documents(root)[1]
    if current == journal['newSaved']:
        pass  # The commit completed before the process was interrupted.
    elif current != journal['oldSaved']:
        raise SettingsError('recovery', 'Saved settings changed after the interrupted Apply. Review the recovery record before proceeding.')
    else:
        failures = rollback(root, journal, interactive=True)
        if failures:
            raise SettingsError('recovery', '; '.join(failures))
    path.unlink()


def sync(root):
    descriptor = os.open(root / '.settings.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, 'r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        recover_locked(root)
        preferences, saved = documents(root)
        layouts = saved['general'].get('keyboard', {}).get('layouts')
        if layouts is not None:
            validate_layouts(layouts, preferences)
        content = system.input_text(layouts)
        path = root / 'settings-input.lua'
        changed = not path.exists() or path.read_text() != content
        if changed:
            system.validate_input(root, content)
            atomic_text(path, content)
        return changed
