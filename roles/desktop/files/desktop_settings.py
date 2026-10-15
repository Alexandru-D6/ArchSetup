"""Shared, user-owned desktop settings. No authentication or session control."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile


POWER_FIELD = 'general.lockPowerRequiresAuth'
POWER_START = '# archsetup-lock-power-start\n'
POWER_END = '# archsetup-lock-power-end\n'


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
    return preferences, saved


def resolve(preferences, saved):
    effective = dict(preferences)
    effective['lockPowerRequiresAuth'] = saved['general'].get(
        'lockPowerRequiresAuth', preferences.get('lockPowerRequiresAuth') is not False)
    return effective


def effective_preferences(root):
    """A corrupt override must never enable lock-screen power requests."""
    try:
        preferences, saved = documents(root)
        return resolve(preferences, saved)
    except SettingsError:
        return {'lockPowerRequiresAuth': True}


def snapshot_from(preferences, saved):
    encoded = json.dumps([preferences, saved], sort_keys=True, separators=(',', ':'), allow_nan=False)
    effective = resolve(preferences, saved)
    return {'revision': hashlib.sha256(encoded.encode()).hexdigest(),
            'values': {POWER_FIELD: effective['lockPowerRequiresAuth']},
            'preferences': effective}


def snapshot(root):
    return snapshot_from(*documents(root))


def native_lock_configuration(root, configuration, preferences=None):
    """Build the next session's private lock config from current effective values.

    The launcher already snapshots native configuration into its private session
    directory. No mutable generated output or active-lock restart is needed for
    this first setting; settings.json is the single atomic commit point.
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
    return before + POWER_START + power + POWER_END + after


def atomic_save(path, document):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.settings-', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(document, stream, indent=2, allow_nan=False)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def apply(root, revision, changes):
    if not isinstance(changes, dict) or not changes or set(changes) - {POWER_FIELD}:
        raise SettingsError('validation', 'The request contains an unsupported setting.')
    if type(changes.get(POWER_FIELD)) is not bool:
        raise SettingsError('validation', 'Require unlock must be enabled or disabled.',
                            {POWER_FIELD: 'Choose enabled or disabled.'})
    # All writers use this same lock, including separate Configuration processes.
    descriptor = os.open(root / '.settings.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, 'r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        preferences, saved = documents(root)
        current = snapshot_from(preferences, saved)
        if revision != current['revision']:
            raise SettingsError('conflict', 'Settings changed elsewhere. Revert to reload the current values.', snapshot=current)
        if all(current['values'][key] == value for key, value in changes.items()):
            return current
        updated = dict(saved, revision=saved['revision'] + 1,
                       general=dict(saved['general'], lockPowerRequiresAuth=changes[POWER_FIELD]))
        # Stage and validate the native configuration before committing. The
        # locker will generate its private copy from the committed values.
        native_lock_configuration(root, (root / 'hyprlock.conf').read_text(), resolve(preferences, updated))
        # Check defaults again in case Ansible changed them during staging.
        if snapshot(root)['revision'] != revision:
            raise SettingsError('conflict', 'Settings changed elsewhere. Revert to reload the current values.', snapshot=snapshot(root))
        atomic_save(root / 'settings.json', updated)
        return snapshot_from(preferences, updated)
