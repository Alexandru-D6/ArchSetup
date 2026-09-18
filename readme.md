# ArchSetup

Ansible configuration for setting up and maintaining a computer after a fresh
Arch Linux installation.

## Disposable Arch VM

Use the official Arch cloud image to test safely in a local QEMU virtual machine.
Install the host dependencies first:

```bash
sudo pacman -S qemu-desktop cloud-image-utils
```

Then create an already-installed Arch VM and connect to it:

```bash
./scripts/vm.sh init
./scripts/vm.sh start
./scripts/vm.sh ssh
```

`init` downloads the official image and its SHA-256 file, verifies the image,
creates a local SSH key under `vm/keys/`, and builds a writable overlay. The VM is
available only at `127.0.0.1:2222`; its console is recorded in
`vm/run/console.log`. The `archsetup` VM user has passwordless sudo solely to make
this disposable test environment convenient.

Use `./scripts/vm.sh status`, `console`, and `stop` to manage it. Run
`./scripts/vm.sh reset` to discard the writable VM disk and start again with a
fresh machine. Generated images, disks, keys, and logs are ignored by Git.

The first implementation installs a configurable list of basic official-repository
tools: build essentials, shell completion, Git, network tools, search tools, archive
tools, terminal multiplexer, manuals, and package maintenance utilities. See
[inventory/group_vars/all.yml](inventory/group_vars/all.yml) for the exact list.

The central requirement is **idempotency**: applying the same configuration again
should make no changes when the managed state already matches it. System upgrades
will be an explicit maintenance operation.

## Use

On a fresh, installed Arch system, clone or copy this repository and run:

```bash
./setup.sh bootstrap
./setup.sh check
./setup.sh apply
./setup.sh verify
```

`bootstrap` installs Git, Python, Ansible, and sudo if missing. Because Arch only
supports full upgrades, that initial prerequisite installation uses `pacman -Syu`.
`apply` does not refresh package databases or upgrade packages; it only ensures the
declared tools are present. Use `./setup.sh upgrade` separately for a deliberate
full system upgrade. Supply normal Ansible options after each command, such as
`./setup.sh apply --ask-become-pass`.

Run bootstrap as root when sudo is not yet installed. Later commands can run as a
regular sudo-enabled user. The first `apply` needs current package metadata; if
pacman cannot install a missing tool because the local metadata is stale, run the
explicit upgrade command and retry.

To change the tool set, edit
[inventory/group_vars/all.yml](inventory/group_vars/all.yml). Removing a name from
the list leaves an already installed package in place. Package removal is not
automated yet.

See the [development plan](docs/development-plan.md) for the next roles, dotfiles,
and VM-based repeatability tests.
