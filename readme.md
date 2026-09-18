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

The project is currently in the planning stage. See the
[development plan](docs/development-plan.md) for the proposed architecture,
implementation milestones, and tests for safe repeated execution.

The central requirement is **idempotency**: applying the same configuration again
should make no changes when the managed state already matches it. System upgrades
will be an explicit maintenance operation.
