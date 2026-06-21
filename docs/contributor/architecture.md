# DKVM Architecture

This document describes the end-to-end architecture of DKVM — how the operating
system is built, how it boots, how data persists, and how the components relate.

---

## Boot Sequence

DKVM follows a standard Alpine Linux diskless boot path with customizations for
virtualization and passthrough.

```
USB Power On
    │
    ▼
UEFI/BIOS → GRUB (on USB, FAT32)
    │
    │ Kernel cmdline includes:
    │   intel_iommu=on amd_iommu=on iommu=pt
    │   mitigations=off elevator=noop waitusb=5
    │   blacklist=amdgpu split_lock_detect=off
    │   modules=...vfio-pci
    │
    ▼
Alpine LTS Kernel + initramfs (loaded into RAM)
    │
    ▼
initramfs completes → diskless mode (root in RAM)
    │
    ▼
/etc/local.d/dkvm_folder.start runs:
    │   mkdir /media/dkvmdata
    │   mount -a  →  mounts DKVMDATA partition if present
    │
    ▼
OpenRC starts services:
    │   - lvm (LVM2)
    │   - local (local scripts)
    │   - ntpd (NTP time sync)
    │   - sshd (root login enabled)
    │
    ▼
tty1: DKVM Manager TUI (respawn on exit)
    │
    ▼
User configures VMs via the TUI
```

### Key points

- **Everything runs from RAM.** The USB is only read at boot and written during
  `lbu commit` or explicit saves. The OS roots are in a tmpfs.
- **GRUB is configured** by `scripts/runme.sh` during build to inject IOMMU,
  VFIO, and microcode parameters. CPU microcode (AMD + Intel) is loaded before
  the kernel.
- **DKVM Manager launches on tty1** via `/etc/inittab` with `respawn` flag so
  it restarts automatically if it exits.
- **DKVMDATA is optional at boot.** The `nofail` option in fstab means the
  system boots even if no DKVMDATA partition exists.

---

## Build Pipeline

DKVM uses a Makefile-based build system. The output is a bootable FAT32 disk
image (`dkvm-<version>.img`).

### Flow diagram

```
make build
    │
    ├── verify-deps
    │       Check wget, expect, mkisofs, dd, xorriso, zip, qemu-system-x86_64,
    │       losetup, mount, sudo, tar
    │
    ├── OVMF_CODE.fd / OVMF_VARS.fd
    │       Locate and copy UEFI firmware from system paths
    │
    ├── alpine-standard-<ver>.iso
    │       Download from Alpine mirror (if not present)
    │
    ├── scripts.iso
    │       Build ISO containing:
    │       │   - scripts/runme.sh
    │       │   - scripts/answer.txt
    │       │   - scripts/dkvmmanager (pre-built binary)
    │       └── mkisofs -iso-level 4
    │
    ├── alpine_extract/vmlinuz-lts
    │       Extract LTS kernel from Alpine ISO via xorriso
    │
    ├── alpine_extract/initramfs-lts
    │       Extract initramfs via xorriso
    │
    ├── dkvm-<version>.img (2048 MB default)
    │   │
    │   │ dd if=/dev/zero → raw disk image
    │   │
    │   └── QEMU VM (automated via install.expect)
    │           │
    │           │ QEMU args:
    │           │   -kernel alpine_extract/vmlinuz-lts
    │           │   -initrd alpine_extract/initramfs-lts
    │           │   -drive Alpine ISO (sr0)
    │           │   -drive scripts ISO (sr1)
    │           │   -drive disk image (usb stick)
    │           │   -nographic, serial console
    │           │
    │           │ install.expect drives setup-alpine:
    │           │   1. Boots QEMU with Alpine kernel + initramfs
    │           │   2. Waits for login prompt → logs in as root
    │           │   3. Mounts scripts ISO → runs runme.sh /dev/sda
    │           │
    │           │ runme.sh inside QEMU:
    │           │   1. Creates FAT32 partition on /dev/sda
    │           │   2. Runs setup-alpine -f answer.txt (diskless mode)
    │           │   3. Copies Alpine ISO bootfiles via setup-bootable
    │           │   4. Installs packages (QEMU, VFIO, bridge, swtpm, etc.)
    │           │   5. Patches GRUB with IOMMU/VFIO cmdline args
    │           │   6. Copies CPU microcode
    │           │   7. Installs DKVM Manager binary, configures tty1
    │           │   8. Sets up fstab, modules, SSH, ACPI power button
    │           │   9. lbu commit → saves overlay to USB
    │           │  10. Poweroff
    │           │
    │           └── Post-build: mount image, write dkvm-release version file
    │
    └── dkvm-<version>.img ✓
```

### Quick iteration (script-only changes)

For faster iteration when only `scripts/runme.sh` or `scripts/answer.txt`
change:

```bash
make scripts.iso && sudo expect install.expect \
  /usr/bin/qemu-system-x86_64 \
  OVMF_CODE.fd OVMF_VARS.fd \
  dkvm-<version>.img \
  alpine-standard-<ver>.iso \
  scripts.iso
```

This skips ISO download, kernel extraction, and OVMF discovery — reusing the
previously built artifacts.

### Inspecting a built image

```bash
sudo losetup --show -f -P dkvm-<version>.img
# → /dev/loop0
sudo mount /dev/loop0p1 /mnt
# Inspect contents: kernel, initramfs, scripts, dkvm-release
sudo umount /mnt
sudo losetup -d /dev/loop0
```

---

## Persistence Model

DKVM uses two persistence mechanisms that serve different purposes:

### 1. Alpine `lbu` overlay (on USB)

Alpine Linux in diskless mode keeps the root filesystem in a tmpfs. To persist
changes (configuration, installed packages, modified files), `lbu` stores an
overlay on the USB stick.

- **`lbu commit`** saves the current state to the USB.
- **`lbu include <path>`** marks a file/directory for inclusion in the overlay.
- DKVM Manager runs `lbu commit` automatically when configuration changes are
  saved.
- The overlay survives reboots because the USB is writable.

Files persisted via `lbu`:
- `/etc/inittab` (DKVM Manager on tty1)
- `/usr/bin/dkvmmanager` (the binary itself)
- System configuration changes made via the TUI

### 2. DKVMDATA data partition

VM workload data (disk images, ISOs, TPM state, VM configs) is too large for
the `lbu` overlay. It lives on a separate ext4 partition labeled `DKVMDATA`.

- **Auto-mounted** at `/media/dkvmdata` by `/etc/local.d/dkvm_folder.start`
  during boot.
- **Format**: ext4 with label `DKVMDATA`. Example:
  ```bash
  sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
  ```
- **Contents**:
  - VM disk images (`.qcow2`, `.raw`)
  - ISO files for guest OS installation
  - TPM state directories (per-VM, managed by `swtpm`)
  - VM configuration files (managed by DKVM Manager)
- **`nofail`** in fstab ensures the system boots even if the partition is
  missing (first-boot scenario).

> **Important**: All VM and system configuration must be done through the
> DKVM Manager TUI. Manual editing of configuration files under
> `/media/dkvmdata` is not supported.

---

## Component Map

```
┌─────────────────────────────────────────────────────────────────┐
│                      Build System (Host)                        │
│                                                                 │
│  Makefile                                                       │
│    ├── verify-deps      — check dependencies                   │
│    ├── build            — full pipeline                         │
│    ├── run              — smoke test in QEMU                    │
│    ├── cleanup          — remove generated files                │
│    └── scripts.iso      — rebuild script ISO only               │
│                                                                 │
│  install.expect (Expect script)                                 │
│    └── Automated QEMU session: boots Alpine, runs runme.sh      │
│                                                                 │
│  scripts/                                                       │
│    ├── runme.sh          — installation logic inside QEMU VM   │
│    ├── answer.txt        — setup-alpine answer file             │
│    ├── dkvmmanager      — pre-built binary (downloaded)         │
│                                                                 │
│  examples/                                                      │
│    ├── amd_9000_StartStop.sh  — GPU passthrough with driver     │
│    │                             cycling                        │
│    └── verify_pinning.sh      — CPU pinning verification        │
│                                                                 │
│  OVMF_CODE.fd / OVMF_VARS.fd  — UEFI firmware (copied from     │
│                                  host system)                   │
│  alpine-standard-<ver>.iso     — Alpine base ISO (downloaded)   │
│  alpine_extract/               — extracted kernel + initramfs   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  DKVM Operating System (Target)                  │
│                                                                 │
│  GRUB → Alpine LTS Kernel + initramfs                           │
│       │                                                         │
│       ▼                                                         │
│  /etc/local.d/dkvm_folder.start                                 │
│       │  Mounts DKVMDATA partition                              │
│       ▼                                                         │
│  OpenRC services: lvm, local, ntpd, sshd                        │
│       │                                                         │
│       ▼                                                         │
│  DKVM Manager (tty1)  ────  glemsom/dkvmmanager (separate repo) │
│       │                                                         │
│       ├── CPU pinning & topology                                │
│       ├── PCI passthrough                                       │
│       ├── USB passthrough                                       │
│       ├── VM creation & editing                                 │
│       ├── Hugepages & memory                                    │
│       ├── TPM support (swtpm)                                   │
│       └── lbu commit (persistence)                              │
│                                                                 │
│  Guest VMs (QEMU/KVM)                                           │
│       ├── QMP socket on localhost:4444                          │
│       ├── Bridge networking (br0)                               │
│       └── Passthrough devices via vfio-pci                      │
└─────────────────────────────────────────────────────────────────┘
```

### External dependencies

| Component | Source | Notes |
|-----------|--------|-------|
| Alpine Linux | [alpinelinux.org](https://alpinelinux.org) | Base OS, diskless mode |
| QEMU | `glemsom/dkvm-qemu` (custom APK repo) | Custom build with DKVM patches |
| DKVM Manager | [glemsom/dkvmmanager](https://github.com/glemsom/dkvmmanager) | Go TUI, separate repo, version-pinned in Makefile |
| OVMF (UEFI) | Host system package | `ovmf` from Alpine community repo |
| swtpm | Alpine community repo | Software TPM for guests |

### Repositories

- **glemsom/dkvm** — This repo. Makefile, install scripts, examples,
  documentation. Produces the bootable USB image.
- **glemsom/dkvmmanager** — The Go TUI binary that runs on tty1. Pinned via
  `DKVM_MANAGER_VERSION` in the Makefile.
- **glemsom/dkvm-qemu** — Custom QEMU APK repository with DKVM-specific
  patches and configurations.

---

## ACPI Power Management

When the DKVM host power button is pressed, an ACPI event triggers:

```bash
echo '{ "execute": "qmp_capabilities" }' |
  echo '{ "execute": "system_powerdown" }' |
  timeout 5 nc localhost 4444
```

This sends a graceful shutdown request to the running guest VM via the QMP
socket. The host does not shut down until the guest responds.
