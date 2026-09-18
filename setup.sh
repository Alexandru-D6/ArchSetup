#!/usr/bin/env bash
# Local bootstrap and execution wrapper for ArchSetup.
set -euo pipefail

readonly setup_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly setup_command="${1:-}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh <command> [Ansible options]

Commands:
  bootstrap  Install Ansible prerequisites and the declared collections.
  check      Preview changes without modifying the system.
  apply      Install the declared command-line tools.
  upgrade    Perform an explicit full Arch system upgrade.
  verify     Confirm that the declared command-line tools are installed.
EOF
}

require_ansible() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    printf '%s\n' 'Ansible is not installed. Run ./setup.sh bootstrap first.' >&2
    exit 1
  fi
}

run_with_privilege() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    printf '%s\n' 'Run bootstrap as root because sudo is not installed yet.' >&2
    exit 1
  fi
}

bootstrap() {
  if [[ ! -f /etc/arch-release ]] || ! command -v pacman >/dev/null 2>&1; then
    printf '%s\n' 'Bootstrap supports an installed Arch Linux system only.' >&2
    exit 1
  fi

  local prerequisites=(ansible git python sudo)
  local missing=()
  local package
  for package in "${prerequisites[@]}"; do
    if ! pacman -Q "${package}" >/dev/null 2>&1; then
      missing+=("${package}")
    fi
  done

  if ((${#missing[@]})); then
    printf 'Installing prerequisites with a full system upgrade: %s\n' "${missing[*]}"
    run_with_privilege pacman -Syu --needed -- "${missing[@]}"
  fi

  ansible-galaxy collection install -r "${setup_root}/requirements.yml" \
    -p "${setup_root}/collections"
}

run_playbook() {
  local playbook="$1"
  shift
  require_ansible
  cd -- "${setup_root}"
  ansible-playbook "${playbook}" "$@"
}

case "${setup_command}" in
  bootstrap)
    if (($# != 1)); then usage; exit 2; fi
    bootstrap
    ;;
  check)
    shift
    run_playbook playbooks/site.yml --check --diff "$@"
    ;;
  apply)
    shift
    run_playbook playbooks/site.yml "$@"
    ;;
  upgrade)
    shift
    run_playbook playbooks/upgrade.yml "$@"
    ;;
  verify)
    shift
    run_playbook playbooks/verify.yml "$@"
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "${setup_command}" >&2
    usage >&2
    exit 2
    ;;
esac
