#!/usr/bin/env python3
"""Exercise the actual Ansible package gates with controlled package records."""
import copy
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import yaml

ROLE = Path(__file__).resolve().parents[2] / 'roles/desktop'


class PackageMaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.ansible = shutil.which('ansible-playbook')
        if not self.ansible:
            self.skipTest('ansible-playbook is required')
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'bin').mkdir()
        pacman = self.root / 'bin/pacman'
        pacman.write_text(f'''#!{sys.executable}
import os, sys
from pathlib import Path
assert sys.argv[1:] == ['-Qu'], sys.argv
Path(os.environ['PACKAGE_QUERY_MARKER']).touch()
print(os.environ['PACKAGE_UPGRADES'], end='')
sys.exit(int(os.environ['PACKAGE_QUERY_RC']))
''')
        pacman.chmod(0o755)
        self.variables = {
            'ansible_facts': {'packages': {name: [{}] for name in ['desktop', 'login', 'network']}},
            'archsetup_desktop_packages': ['desktop'],
            'archsetup_desktop_login_packages': ['login'],
            'archsetup_desktop_network_packages': ['network'],
            'archsetup_desktop_manage_login': True,
            'archsetup_desktop_manage_network': True,
            'archsetup_desktop_browser': 'brave-browser.desktop',
            'archsetup_desktop_code_editor': 'codium.desktop',
            'archsetup_desktop_install_brave': True,
            'archsetup_desktop_install_vscodium': True,
            'desktop_browser_entries': {'results': [{'stat': {'exists': True}}]},
            'desktop_code_editor_entries': {'results': [{'stat': {'exists': True}}]},
        }

    def run_gate(self, filename, variables, pending=True, query_rc=None, check=False):
        tasks = []
        for original in yaml.safe_load((ROLE / 'tasks' / filename).read_text()):
            task = copy.deepcopy(original)
            if 'ansible.builtin.package_facts' in task:
                continue  # Supply fixture package records; retain all decision tasks.
            if 'ansible.builtin.import_tasks' in task:
                task['ansible.builtin.import_tasks'] = str(ROLE / 'tasks' / task['ansible.builtin.import_tasks'])
            if 'community.general.pacman' in task:
                task.pop('community.general.pacman')
                task['ansible.builtin.debug'] = {'msg': 'PACKAGE_INSTALL_REQUESTED'}
                tasks.append(task)
                break  # Stop before compositor checks or network service changes.
            tasks.append(task)
        playbook = self.root / 'gate.yml'
        playbook.write_text(yaml.safe_dump([dict(hosts='localhost', gather_facts=False, become=False,
                                               vars=variables, tasks=tasks)]))
        marker = self.root / 'queried'
        marker.unlink(missing_ok=True)
        environment = dict(os.environ, ANSIBLE_HOME=str(self.root), ANSIBLE_LOCAL_TEMP=str(self.root / 'tmp'),
                           PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                           PACKAGE_QUERY_MARKER=str(marker), PACKAGE_UPGRADES='other 1 -> 2\n' if pending else '',
                           PACKAGE_QUERY_RC=str(query_rc if query_rc is not None else 0 if pending else 1))
        result = subprocess.run([self.ansible, '-i', 'localhost,', '-c', 'local', str(playbook)]
                                + (['--check'] if check else []), env=environment,
                                capture_output=True, text=True, timeout=30)
        return result, marker.exists()

    def test_desktop_gate_covers_reapplication_missing_dependencies_and_aur_builds(self):
        cases = ['installed', 'missing', 'login_opt_out', 'network_opt_out', 'missing_brave', 'missing_codium', 'clean_install']
        for case in cases:
            for check in [False, True]:
                with self.subTest(case=case, check=check):
                    variables = copy.deepcopy(self.variables)
                    if case in ('missing', 'clean_install'):
                        del variables['ansible_facts']['packages']['desktop']
                    if case == 'login_opt_out':
                        del variables['ansible_facts']['packages']['login']
                        variables['archsetup_desktop_manage_login'] = False
                    if case == 'network_opt_out':
                        del variables['ansible_facts']['packages']['network']
                        variables['archsetup_desktop_manage_network'] = False
                    if case == 'missing_brave':
                        variables['desktop_browser_entries']['results'][0]['stat']['exists'] = False
                    if case == 'missing_codium':
                        variables['desktop_code_editor_entries']['results'][0]['stat']['exists'] = False
                    result, queried = self.run_gate('packages.yml', variables, pending=case != 'clean_install', check=check)
                    blocked = case in ('missing', 'missing_brave', 'missing_codium')
                    self.assertEqual(result.returncode, 2 if blocked else 0, result.stdout + result.stderr)
                    self.assertEqual(queried, blocked or case == 'clean_install')
                    self.assertEqual('PACKAGE_INSTALL_REQUESTED' in result.stdout, case == 'clean_install')
                    if blocked:
                        self.assertIn('./setup.sh upgrade --ask-become-pass', result.stdout)

    def test_standalone_network_installation_uses_the_same_guard(self):
        for installed, pending in [(True, True), (False, True), (False, False)]:
            for check in [False, True]:
                with self.subTest(installed=installed, pending=pending, check=check):
                    variables = copy.deepcopy(self.variables)
                    if not installed:
                        del variables['ansible_facts']['packages']['network']
                    result, queried = self.run_gate('network.yml', variables, pending=pending, check=check)
                    self.assertEqual(result.returncode, 2 if pending and not installed else 0, result.stdout + result.stderr)
                    self.assertEqual(queried, not installed)
                    self.assertEqual('PACKAGE_INSTALL_REQUESTED' in result.stdout, not installed and not pending)

    def test_package_query_errors_stop_installation(self):
        variables = copy.deepcopy(self.variables)
        del variables['ansible_facts']['packages']['desktop']
        result, queried = self.run_gate('packages.yml', variables, pending=False, query_rc=2)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(queried)
        self.assertNotIn('PACKAGE_INSTALL_REQUESTED', result.stdout)


if __name__ == '__main__': unittest.main()
