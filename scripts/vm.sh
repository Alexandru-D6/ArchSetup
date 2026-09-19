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
readonly disk_size="${ARCHSETUP_VM_DISK_SIZE:-30G}"

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
  resize <size>           Grow an existing VM disk and its root filesystem.
  reset                   Stop the VM and discard its writable disk and seed.

Environment:
  ARCHSETUP_VM_IMAGE_URL  Override the official cloud image URL.
  ARCHSETUP_VM_SSH_PORT   Override the local SSH port (default: 2222).
  ARCHSETUP_VM_DISK_SIZE  Set the disk created by init (default: 30G).
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

vm_pid() {
  local candidate
  if [[ -r "${pid_file}" ]]; then
    candidate="$(<"${pid_file}")"
    if [[ "${candidate}" =~ ^[0-9]+$ ]] && kill -0 "${candidate}" 2>/dev/null; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if command -v fuser >/dev/null 2>&1; then
    for candidate in $(fuser "${overlay_image}" 2>/dev/null); do
      if [[ -r "/proc/${candidate}/cmdline" ]] \
        && tr '\0' ' ' <"/proc/${candidate}/cmdline" | grep -Fq -- 'qemu-system' \
        && tr '\0' ' ' <"/proc/${candidate}/cmdline" | grep -Fq -- "${overlay_image}"; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  fi
  return 1
}

is_running() {
  vm_pid >/dev/null
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
growpart:
  mode: auto
  devices: ["/"]
resize_rootfs: true
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
  if [[ ! -f "${overlay_image}" ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "${base_image}" "${overlay_image}"
    qemu-img resize "${overlay_image}" "${disk_size}"
  fi
  printf 'VM initialized with a %s virtual disk. Start it with ./scripts/vm.sh start\n' "${disk_size}"
}

start() {
  require_commands qemu-system-x86_64
  if is_running; then printf 'VM is already running (PID %s).\n' "$(vm_pid)"; exit 0; fi
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

wait_for_ssh() {
  local attempt
  for attempt in {1..60}; do
    if run_ssh true >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  printf '%s\n' 'The VM did not become reachable by SSH within 60 seconds.' >&2
  return 1
}

grow_guest_root() {
  run_ssh bash -s <<'EOF'
set -euo pipefail
root_partition="$(findmnt -n -o SOURCE /)"
root_disk="/dev/$(lsblk -n -o PKNAME "${root_partition}")"
partition_number="$(lsblk -n -o PARTN "${root_partition}")"
sudo growpart "${root_disk}" "${partition_number}"
case "$(findmnt -n -o FSTYPE /)" in
  ext4) sudo resize2fs "${root_partition}" ;;
  btrfs) sudo btrfs filesystem resize max / ;;
  xfs) sudo xfs_growfs / ;;
  *)
    printf 'Root filesystem was not resized automatically: %s\n' "$(findmnt -n -o FSTYPE /)" >&2
    exit 1
    ;;
esac
EOF
}

resize() {
  local requested_size="$1"
  require_commands qemu-img qemu-system-x86_64
  [[ -f "${overlay_image}" ]] || { printf '%s\n' 'VM is not initialized. Run ./scripts/vm.sh init first.' >&2; exit 1; }
  if is_running; then
    printf '%s\n' 'Stop the VM before resizing it.' >&2
    exit 1
  fi
  qemu-img resize "${overlay_image}" "${requested_size}"
  start
  wait_for_ssh
  grow_guest_root
  printf 'VM disk and root filesystem expanded to %s.\n' "${requested_size}"
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
  status) is_running && printf 'VM is running (PID %s).\n' "$(vm_pid)" || printf '%s\n' 'VM is stopped.' ;;
  console) mkdir -p "${vm_root}/run"; touch "${console_log}"; tail -f "${console_log}" ;;
  resize) shift; (($# == 1)) || { usage; exit 2; }; resize "$1" ;;
  -h|--help|help|'') usage ;;
  *) printf 'Unknown command: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac
