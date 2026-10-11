#!/usr/bin/env python3
"""Render a sandbox profile without Ansible or target-system changes."""
import json
import shutil
import sys
from pathlib import Path
import jinja2
import yaml

REPO = Path(__file__).resolve().parents[2]
ROLE = REPO / 'roles/desktop'
def render(destination, overrides=None):
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    defaults = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())
    defaults.update(overrides or {})
    defaults.update(desktop_root=str(destination), role_path=str(ROLE))
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(ROLE / 'templates'),
                             undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
    env.filters['bool'] = lambda value: str(value).lower() in ('true', 'yes', '1', 'on')
    env.filters['to_json'] = json.dumps
    env.filters['from_json'] = json.loads
    env.globals['lookup'] = lambda plugin, path: Path(path).read_text()
    for template in (ROLE / 'templates').glob('*.j2'):
        (destination / template.stem).write_text(env.get_template(template.name).render(defaults))
    shutil.copytree(ROLE / 'files/shell', destination / 'shell', dirs_exist_ok=True)
    (destination / 'bin').mkdir(exist_ok=True)
    for filename in ['desktop-action', 'desktop-record', 'session-services', 'validate-config', 'lock-visuals']:
        shutil.copy2(ROLE / 'files' / filename, destination / 'bin' / filename)
        (destination / 'bin' / filename).chmod(0o755)
    shutil.copy2(ROLE / 'files/shortcuts.json', destination / 'shortcuts.json')
    (destination / '.runtime-validation').mkdir(mode=0o700, exist_ok=True)
    (destination / 'state.json').write_text('{}\n')
    return destination
if __name__ == '__main__':
    print(render(sys.argv[1]))
