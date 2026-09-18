# ArchSetup

Ansible configuration for setting up and maintaining a computer after a fresh
Arch Linux installation.

The project is currently in the planning stage. See the
[development plan](docs/development-plan.md) for the proposed architecture,
implementation milestones, and tests for safe repeated execution.

The central requirement is **idempotency**: applying the same configuration again
should make no changes when the managed state already matches it. System upgrades
will be an explicit maintenance operation.
