#!/usr/bin/env bash
# Manage a disposable local Arch Linux QEMU VM for ArchSetup testing.
set -euo pipefail

readonly vm_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/vm"
readonly image_url="${ARCHSETUP_VM_IMAGE_URL:-https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2}"
readonly image_name="${image_url##*/}"
readonly base_image="${vm_root}/images/${image_name}"
readonly overlay_image="${vm_root}/disks/archsetup.qcow2"
readonly seed_image="${vm_root}/disks/seed.iso"
readonly user_data="${vm_root}/cloud-init/user-data"
readonly meta_data="${vm_root}/cloud-init/meta-data"
readonly network_config="${vm_root}/cloud-init/network-config"
readonly private_key="${vm_root}/keys/archsetup_vm_ed25519"
readonly public_key="${private_key}.pub"
readonly pid_file="${vm_root}/run/qemu.pid"
readonly console_log="${vm_root}/run/console.log"
readonly ssh_port="${ARCHSETUP_VM_SSH_PORT:-2222}"
readonly ssh_user="archsetup"

usage() {
  cat <<'EOF'
Usage: ./scripts/vm.sh <command> [options]

Commands:
  init [public-key-file]  Download and verify the official Arch cloud image,
                          create a test key if needed, and prepare the VM disk.
  start                   Start the VM in the background on 127.0.0.1:2222.
  stop                    Request a graceful shutdown over SSH.
  ssh                     Connect as the archsetup user.
  status                  Show whether the QEMU process is running.
  console                 Follow the serial console log.
  reset                   Stop the VM and discard its writable disk and seed.

Environment:
  ARCHSETUP_VM_IMAGE_URL  Override the official cloud image URL.
  ARCHSETUP_VM_SSH_PORT   Override the local SSH port (default: 2222).
EOF
}

require_commands() {
  local command
  for command in "$@"; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "${command}" >&2
      exit 1
    fi
  done
}

is_running() {
  [[ -r "${pid_file}" ]] && kill -0 "$(<"${pid_file}")" 2>/dev/null
}

run_ssh() {
  ssh -i "${private_key}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${vm_root}/keys/known_hosts" -o ConnectTimeout=5 \
    -p "${ssh_port}" "${ssh_user}@127.0.0.1" "$@"
}

write_cloud_init() {
  local key="$1"
  mkdir -p "${vm_root}/cloud-init" "${vm_root}/disks" "${vm_root}/run"
  cat >"${user_data}" <<EOF
#cloud-config
users:
  - default
  - name: ${ssh_user}
    groups: wheel
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${key}
ssh_pwauth: false
package_update: false
EOF
  cat >"${meta_data}" <<EOF
instance-id: archsetup-local
local-hostname: archsetup
EOF
  cat >"${network_config}" <<'EOF'
version: 2
ethernets:
  eth0:
    dhcp4: true
EOF
}

initialize() {
  require_commands curl sha256sum qemu-img cloud-localds ssh-keygen
  if is_running; then printf '%s\n' 'Stop the VM before initializing it.' >&2; exit 1; fi
  mkdir -p "${vm_root}/images" "${vm_root}/disks" "${vm_root}/keys" "${vm_root}/run"
  chmod 700 "${vm_root}/keys"

  if [[ ! -f "${base_image}" || ! -f "${base_image}.SHA256" ]]; then
    curl --fail --location --remote-name --output-dir "${vm_root}/images" "${image_url}"
    curl --fail --location --remote-name --output-dir "${vm_root}/images" "${image_url}.SHA256"
  fi
  ( cd -- "${vm_root}/images"; sha256sum --check --status "${image_name}.SHA256" )

  local requested_key="${1:-}"
  if [[ -n "${requested_key}" ]]; then
    [[ -r "${requested_key}" ]] || { printf 'Cannot read SSH public key: %s\n' "${requested_key}" >&2; exit 1; }
    cp -- "${requested_key}" "${public_key}"
  elif [[ ! -f "${private_key}" || ! -f "${public_key}" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "${private_key}" -C archsetup-vm
  fi
  chmod 600 "${private_key}" 2>/dev/null || true
  local key
  key="$(<"${public_key}")"
  [[ -n "${key}" ]] || { printf '%s\n' 'The SSH public key is empty.' >&2; exit 1; }
  write_cloud_init "${key}"
  cloud-localds --network-config="${network_config}" "${seed_image}" "${user_data}" "${meta_data}"
  [[ -f "${overlay_image}" ]] || qemu-img create -f qcow2 -F qcow2 -b "${base_image}" "${overlay_image}"
  printf 'VM initialized. Start it with ./scripts/vm.sh start\n'
}

start() {
  require_commands qemu-system-x86_64
  if is_running; then printf 'VM is already running (PID %s).\n' "$(<"${pid_file}")"; exit 0; fi
  [[ -f "${overlay_image}" && -f "${seed_image}" ]] || { printf '%s\n' 'VM is not initialized. Run ./scripts/vm.sh init first.' >&2; exit 1; }
  rm -f -- "${pid_file}"
  local -a acceleration=(-accel tcg)
  [[ -r /dev/kvm && -w /dev/kvm ]] && acceleration=(-enable-kvm -cpu host)
  qemu-system-x86_64 "${acceleration[@]}" -m 2048 -smp 2 -display none \
    -serial "file:${console_log}" -pidfile "${pid_file}" -daemonize \
    -drive "file=${overlay_image},format=qcow2,if=virtio" \
    -drive "file=${seed_image},format=raw,media=cdrom,readonly=on" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${ssh_port}-:22" \
    -device virtio-net-pci,netdev=net0
  printf 'VM started. Cloud-init may take a moment; connect with ./scripts/vm.sh ssh\n'
}

stop() {
  if ! is_running; then printf '%s\n' 'VM is not running.'; exit 0; fi
  if run_ssh sudo systemctl poweroff; then
    printf '%s\n' 'Shutdown requested.'
  else
    printf '%s\n' 'Could not reach the VM. The process was left running; check ./scripts/vm.sh console.' >&2
    exit 1
  fi
}

reset() {
  if is_running; then
    stop
    local attempt
    for attempt in {1..30}; do is_running || break; sleep 1; done
  fi
  is_running && { printf '%s\n' 'VM did not stop; refusing to discard its disk.' >&2; exit 1; }
  rm -f -- "${overlay_image}" "${seed_image}" "${pid_file}" "${console_log}" \
    "${vm_root}/keys/known_hosts"
  printf '%s\n' 'Writable VM state discarded. Run ./scripts/vm.sh init to create a fresh VM.'
}

case "${1:-}" in
  init) shift; (($# <= 1)) || { usage; exit 2; }; initialize "${1:-}" ;;
  start) start ;;
  stop) stop ;;
  ssh) run_ssh ;;
  status) is_running && printf 'VM is running (PID %s).\n' "$(<"${pid_file}")" || printf '%s\n' 'VM is stopped.' ;;
  console) mkdir -p "${vm_root}/run"; touch "${console_log}"; tail -f "${console_log}" ;;
  -h|--help|help|'') usage ;;
  *) printf 'Unknown command: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac
