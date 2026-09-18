# ArchSetup development plan

Status: proposed design; provisioning scripts and playbooks are not implemented.

## Objective and scope

Turn an installed Arch Linux system into a configured personal computer using a
version-controlled description of its packages, services, and configuration files.
Use the same entry point for initial setup and later configuration changes.

Assume Arch is already installed, bootable, and connected to the internet, with
working package repositories and either root access or a user with sudo access.
Support a root-only initial installation and subsequent runs as the configured
regular user. Disk partitioning, encryption setup, and bootloader installation are
outside the first version.

The agreed first release covers the command-line environment, base system
settings, and dotfiles. Desktop and hardware-specific configuration are later
milestones. AUR support is optional and follows the core implementation.
Personal package choices and existing dotfiles still need to be supplied.

## Repeatability contract

Ansible should describe the desired state: a package is installed, a file has
particular content and permissions, or a service is enabled and running.

The implementation must meet these requirements:

- A successful configuration run followed immediately by the same run reports
  `changed=0` and `failed=0` when inputs and managed state are unchanged.
- Editing or deleting a managed file is corrected on the next run; another run
  then makes no changes. Files explicitly designated as user-owned are preserved.
- Repeated execution does not duplicate configuration entries, recreate users,
  regenerate credentials, or restart healthy services unnecessarily.
- Configuration changes, package removals, and upgrades have explicit inputs.
  Removing a package name from an installation list does not uninstall it.
- Failures produce a nonzero exit status and useful recovery instructions.
  A rerun converges after a recoverable failure; it must not hide an incomplete
  operation behind a generic "setup completed" marker.

This is a testable idempotency goal, not a promise that every future Arch update,
network request, or interrupted package transaction will succeed. Arch is a rolling
release: reproducing configuration does not guarantee identical package versions
months later. Exact historical package reproduction would require a separate
repository snapshot strategy.

## Execution model

Run Ansible locally on the computer being configured. Use a named inventory host
with `ansible_connection: local`, explicit target-user variables, and privilege
escalation only for system operations. The first root-run workflow must not require
sudo to exist before bootstrap installs it. Later runs use the regular user and
request the sudo password when needed.

Expose these proposed commands through a small wrapper. These are interface
examples, not commands that exist in the repository yet.

| Command | Intended behavior |
| --- | --- |
| `./setup.sh bootstrap` | Install missing execution prerequisites and declared Ansible collections. |
| `./setup.sh check` | Preview configuration changes with Ansible check and diff modes. |
| `./setup.sh apply` | Install missing declared packages and converge configuration. |
| `./setup.sh apply --tags dotfiles` | Apply a documented subset with its prerequisites checked. |
| `./setup.sh upgrade` | Perform an explicitly requested full Arch system upgrade. |
| `./setup.sh verify` | Check managed packages, files, and services without changing them. |

The wrapper should locate its repository regardless of the working directory,
validate arguments, propagate failures, and prevent overlapping mutating runs.
It must not fetch new configuration commits automatically during `apply`.
Updating the checkout is a deliberate step before reviewing and applying changes.

Bootstrap is deliberately small: check Arch and privileges, install missing Git,
Python, Ansible, and sudo prerequisites, then install the declared collection
versions. If prerequisite packages are missing, install them as part of a full
system upgrade. When prerequisites already exist, bootstrap should avoid that
package transaction entirely.
Document how to obtain the repository on a minimal system where Git is absent.

Check mode requires bootstrap to have completed; the wrapper must not install
prerequisites as a hidden side effect of a preview. Check mode is a simulation,
and some modules or tasks depending on earlier changes cannot fully predict a
first installation. Document these gaps and test real provisioning in a VM.
See [Ansible check and diff modes](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html).

## Proposed repository layout

```text
ArchSetup/
├── readme.md
├── setup.sh
├── ansible.cfg
├── requirements.yml
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/all.yml
│   └── host_vars/workstation.yml
├── playbooks/
│   ├── site.yml
│   ├── upgrade.yml
│   └── verify.yml
├── roles/
│   ├── preflight/
│   ├── users/
│   ├── base_system/
│   ├── packages/
│   ├── dotfiles/
│   └── services/
├── tests/
│   └── vm/
└── docs/
    ├── development-plan.md
    └── recovery.md
```

Use role defaults for reusable settings, group variables for shared preferences,
and host variables for machine-specific values. Keep usernames, locale, keyboard,
timezone, package lists, and feature switches out of task definitions. Resolve
the target home directory from its account; do not use the invoking root user's
home for user configuration.

Store a tested `community.general` version in `requirements.yml`, and document the
compatible Ansible/Python versions. Install collections into a predictable location
and validate their versions before applying configuration. Resolve exact versions
during implementation rather than assuming the newest versions are compatible.

Add desktop, development-tool, and AUR roles when those features are implemented.
Start with one workstation profile; introduce additional host profiles when needed.

For a newly created regular user, document setting its initial login credential
before leaving the root session. Keep that step explicit, preserve existing
passwords, and never supply a shared default password.

## Responsibilities and implementation rules

| Component | Responsibility | Rule for safe repeated runs |
| --- | --- | --- |
| Preflight | Validate OS, variables, privileges, dependencies, and package-manager availability. | Read-only checks; stop with a specific explanation for invalid inputs. |
| Users | Ensure the selected user, groups, home, and sudo policy exist. | Preserve existing passwords and unrelated group membership; validate sudo configuration before replacing it. |
| Base system | Manage explicitly selected hostname, timezone, locale, and console keyboard settings. | Compare actual state; regenerate derived configuration only when needed. |
| Packages | Install declared official-repository packages. | Use `community.general.pacman` with `state: present`; make removals a separate explicit list. |
| Dotfiles | Deploy selected files and application settings. | Use content-aware copy/template tasks with explicit ownership and permissions. |
| Services | Enable and start selected system services. | Use desired service state and handlers for necessary reloads or restarts. |

Prefer Ansible modules over shell commands. Where a command is necessary, detect
its actual state first and define truthful change and failure conditions. Use
`creates` only when that path reliably proves the required operation is complete.
Do not use `changed_when: false` to hide changes or `ignore_errors` to suppress
setup failures. Avoid timestamps or freshly generated randomness in templates.

Ansible handlers provide change-triggered service actions. Ensure a failure after
writing a configuration file cannot leave a pending reload permanently forgotten:
choose an appropriate handler flush point or track pending application, and test
the failure path. See [Ansible handlers](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_handlers.html).

## Arch package and update policy

Keep ordinary configuration and system maintenance as separate operations.
Arch supports full system upgrades; refreshing package databases and upgrading
only selected packages can leave an unsupported partial upgrade. See
[ArchWiki: upgrading packages](https://wiki.archlinux.org/title/Pacman#Upgrading_packages).

For ordinary `apply` runs:

- Ensure declared packages are present without refreshing databases or requesting
  package upgrades automatically.
- Before installing missing packages, check whether the existing sync databases
  show outstanding system upgrades; require the maintenance workflow first if so.
- If cached repository metadata references unavailable packages, stop with an
  instruction to run maintenance. Do not recover by running `pacman -Sy` alone.
- Never delete pacman's lock automatically or force dependency/conflict resolution.

For `upgrade`, refresh databases and upgrade the entire system using
`community.general.pacman` with `update_cache: true` and `upgrade: true`. Package
installation is a separate task because `name` and `upgrade` are mutually exclusive.
The maintenance run is allowed to change the system when upstream packages change;
it is excluded from the unchanged-configuration `changed=0` acceptance test.
See the [pacman module documentation](https://docs.ansible.com/projects/ansible/latest/collections/community/general/pacman_module.html).

Document reading relevant Arch news before upgrades, reviewing `.pacnew` files,
and checking whether a reboot is needed. Do not reboot automatically. Changing
repository configuration must require the full-upgrade path before new installs.

## Configuration ownership and downloads

Start with dotfiles and templates in this repository. For every managed path,
document whether ArchSetup owns the complete file or only a named block/drop-in.
Prefer supported drop-in directories when applications provide them.

Before taking ownership of an existing conflicting personal file, stop and report
the path. Provide an explicit adoption option that creates a recoverable backup.
Once adopted, the repository is authoritative and reruns repair deviations. Keep
personal override files outside that ownership boundary.

Use template validation for configuration formats with an available validator,
particularly sudoers. Keep backups for replacements where recovery matters.
The [template module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html)
supports validation before replacement, backups, and content-aware updates.

If a separate dotfiles repository is needed, declare its URL, destination, and
commit explicitly. Preserve local changes and fail on conflicts rather than
forcing a reset. The [Git module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/git_module.html)
supports revision selection and protects modified files when `force` is false.
Keep the running setup checkout separate from any managed external checkout.

Prefer official packages for software. For unavoidable direct downloads, declare
a versioned URL, trusted SHA-256 checksum, destination, and permissions; verify
before installation. The [get_url module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/get_url_module.html)
can skip an existing file when its checksum matches. Its preview does not verify
the downloaded contents, so a dry run cannot replace the real integrity check.

Keep secrets outside public configuration or encrypted with Ansible Vault, with
the decryption key supplied separately. Suppress logs and diffs for secret tasks.
Preserve existing private keys and credentials on reruns.

## Development milestones

Implement in this order, validating each milestone before expanding its scope.
Milestones 1 through 4 deliver the first CLI-and-dotfiles release; 5 and 6 extend it.

| Milestone | Deliverables | Acceptance criteria |
| --- | --- | --- |
| 1. Foundation | Inventory, variables, dependency declarations, wrapper, bootstrap, preflight, and lint configuration. | A minimal Arch VM can bootstrap; repeating bootstrap skips satisfied prerequisites; invalid inputs fail clearly. |
| 2. First useful setup | Users, base settings, a small declared CLI package list, shell/Git dotfiles, and selected services. | Provision a fresh VM successfully; the immediate second apply reports no changes. |
| 3. Lifecycle and recovery | Check/verify commands, full-upgrade playbook, adoption backups, explicit removals, and recovery documentation. | Managed drift is repaired; a preview does not mutate the target; a recoverable interrupted run converges. |
| 4. First release readiness | Automated checks, reproducible VM test procedure, usage examples, and troubleshooting. | A fresh machine can follow the README from repository acquisition through a verified second run. |
| 5. Personal workstation | Chosen desktop or window manager, development tools, and machine-specific features. | Selected profile starts successfully after reboot; rerun remains idempotent. |
| 6. Optional sources | Only required AUR packages, external repositories, or direct-download applications. | Repeating setup skips already satisfied installs/builds; changes to declared versions take effect predictably. |

For optional AUR support, build as an unprivileged user and elevate only for package
installation. Review build recipes, track installed versions, and handle rebuilds
needed after library upgrades explicitly. Do not treat an AUR helper as a transparent
replacement for pacman. Arch's [makepkg manual](https://man.archlinux.org/man/makepkg.8.en)
documents the package-building tool; the pacman module also warns about helper
compatibility. AUR behavior needs its own acceptance tests before inclusion.

## Verification strategy

Add static checks as the corresponding files are implemented: YAML lint,
`ansible-lint`, playbook syntax checks, and ShellCheck for the wrapper. Run target
mutation tests only in disposable Arch VMs, never on the developer's workstation.
VM coverage is needed for systemd, privileges, boot behavior, and service state;
container-only checks are insufficient for the complete workstation.

The release test sequence is:

1. Boot a minimal Arch VM and bootstrap from the documented starting state.
2. Apply configuration and verify package presence, file content/permissions, and
   service state. Cover both root-only and existing-sudo-user starting conditions.
3. Apply again with identical inputs and assert `changed=0`, `failed=0`; confirm
   managed files were not rewritten and unchanged services were not restarted.
4. Modify one managed file, remove another, and stop a managed service. Apply and
   verify repair, then confirm another run makes no changes.
5. Run check/diff mode with a known pending change and verify no target mutation;
   document unsupported first-install predictions explicitly.
6. Test an invalid configuration, conflicting personal file, and failed download.
   Confirm clear failure, retained valid configuration, and usable backups.
7. Interrupt a safe configuration phase, rerun, and verify convergence. Test an
   active pacman lock separately; package database repair requires an explicit
   recovery procedure rather than blind retries.
8. Exercise full upgrades in a separate VM snapshot, inspect resulting configuration
   changes, reboot, and verify again. A VM snapshot is the recovery boundary for
   system changes; file backups alone are not a whole-system rollback.

Record the setup commit, Ansible/collection versions, and VM/image date with test
results. Test the immediate idempotency rerun under unchanged external inputs;
also schedule periodic fresh-Arch compatibility checks as the project matures.

## Personalization inputs

The framework can be developed with documented example values. Before producing
the actual personal profile, supply the username, hostname, locale, timezone,
keyboard layout, preferred shell, essential packages, and dotfiles source.
Desktop choice, GPU/laptop requirements, AUR needs, and secret storage determine
which optional roles are needed. Do not infer these settings from the development
computer or copy its complete package list into the new-machine profile.
