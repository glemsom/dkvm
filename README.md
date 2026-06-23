# DKVM

[![Build](https://github.com/glemsom/dkvm/actions/workflows/build-image.yml/badge.svg)](https://github.com/glemsom/dkvm/actions/workflows/build-image.yml)

DKVM — Desktop KVM. A minimal hypervisor that runs entirely from RAM,
enabling you to virtualize your own desktop PC with maximum performance.
Tailored for **power users**, **homelab enthusiasts**, and **developers** who need
near-native VM performance with GPU/PCI passthrough.
Supports full VGA (GPU) passthrough, PCI‑e device assignment, and other
hardware acceleration features, delivering near‑native speed for the guest OS.

The project builds a bootable USB image containing an Alpine Linux base, the
required virtualization packages, and the **DKVM Manager** Golang TUI.

## Features

- **GPU (VGA) Passthrough** – Direct access to your graphics card for
  high‑performance graphics.
- **PCI‑e Device Assignment** – Attach other devices such as network cards or
  USB controllers.
- **Minimal Overhead** – Entire OS runs from RAM after boot.
- **DKVM Manager TUI** – CPU pinning, PCI/USB passthrough, VM creation, and
  configuration via an interactive terminal UI.
- **Hugepages** – Back guest memory with hugepages to reduce TLB pressure and
  overhead.
- **TPM (swtpm)** – Virtual TPM 2.0 for guests requiring secure boot or
  BitLocker.
- **Bridge Networking** – `br0` bridge with DHCP for seamless guest access to
  the LAN.
- **QMP Guest Management** – QEMU Machine Protocol for scripted VM control and
  automation.
- **ACPI Power Management** – Graceful guest shutdown, reboot, and power
  management via ACPI.
- **Two‑Layer Persistence** – `lbu` overlay preserves OS configuration; a
  dedicated `DKVMDATA` partition stores VM data across reboots.

## Quick Start

1. Download the latest release ZIP from
   [Releases](https://github.com/glemsom/dkvm/releases).
2. Write the image to a USB stick (see
   [First-Boot Walkthrough](docs/user/first-boot.md#1-write-usb)).
3. Boot from USB (see
   [First-Boot Walkthrough](docs/user/first-boot.md#2-booting)).
4. Create a `DKVMDATA` partition:
   `sudo mkfs.ext4 -L DKVMDATA /dev/sdXY && reboot`
   (see [Setting Up DKVMDATA](docs/user/first-boot.md#3-setting-up-dkvmdata)).
5. Configure CPU pinning, PCI/USB passthrough, memory, and hugepages via the
   DKVM Manager TUI on tty1
   (see [the guide](docs/user/first-boot.md#4-configuring-via-dkvm-manager)).
6. Create and start a virtual machine (see
   [Creating a VM](docs/user/first-boot.md#45-creating-a-vm) and
   [Launch the VM](docs/user/first-boot.md#51-launch-the-vm)).

---

## Documentation

### 🧪 Tutorials — start here

| Document | What you'll do | Last reviewed |
|----------|----------------|---------------|
| [First-Boot Walkthrough](docs/user/first-boot.md) | Write USB image, boot DKVM, configure storage and devices, create your first VM. | 2026-06-23 |

### 🔧 How-to Guides — solve specific problems

| Document | Problem it solves | Last reviewed |
|----------|-------------------|---------------|
| [Networking](docs/user/networking.md) | Set up bridge, user-mode, or port forwarding networking for guests. | 2026-06-23 |
| [Troubleshooting](docs/user/troubleshooting.md) | Diagnose DKVMDATA mounts, VM boot failures, SSH issues. | 2026-06-23 |
| [Example Scripts](docs/user/example-scripts.md) | GPU driver cycling for AMD 9000-series, CPU pinning verification. | 2026-06-23 |
| [GPU Passthrough](docs/user/gpu-passthrough.md) | Configure dedicated GPU passthrough, IOMMU groups, vfio-pci binding, VBIOS, reset issues. | 2026-06-23 |
| [Configuration Files](docs/user/configuration-files.md) | Understand the DKVMDATA partition layout and how VM configs are stored. | 2026-06-23 |
| [Backup, Restore & Migration](docs/user/backup-restore.md) | Back up VM data, restore after failure, and migrate VMs to another host. | 2026-06-23 |

| Document | What it describes | Last reviewed |
|----------|-------------------|---------------|
| [Architecture Reference](docs/contributor/architecture-reference.md) | Boot sequence details, build pipeline commands, persistence specifics, component map. | 2026-06-23 |
| [Local Development](docs/contributor/local-dev.md) | Build commands, quick iteration loop, image inspection, cleanup. | 2026-06-23 |
| [CONTRIBUTING](docs/contributor/CONTRIBUTING.md) | PR process, coding standards, changelog policy. | 2026-06-23 |
| [CHANGELOG](CHANGELOG.md) | Version history and release notes. | 2026-06-23 |

### 🧠 Explanation — deeper understanding

| Document | Topic | Last reviewed |
|----------|-------|---------------|
| [CONTEXT](CONTEXT.md) | Project terminology and ubiquitous language (what "DKVM", "DKVMDATA", "Guest" mean). | 2026-06-23 |
| [Architecture Overview](docs/contributor/architecture-overview.md) | How DKVM works, design decisions, high-level architecture narrative. | 2026-06-23 |
| [Persistence Model](docs/user/configuration-files.md#persistence-model-summary) | How OS settings and VM data survive reboots. | 2026-06-23 |

---

## Build Process

Pre-built images are available in
[GitHub Releases](https://github.com/glemsom/dkvm/releases).

To build from source, see the
[Local Development](docs/contributor/local-dev.md) guide.
---

## DKVM Manager

The **DKVM Manager** is a Golang-based TUI that provides a convenient way to
configure and launch VMs — CPU pinning, PCI/USB passthrough, VM creation,
hugepages, TPM support, and more.

See the [First-Boot Walkthrough](docs/user/first-boot.md#4-configuring-via-dkvm-manager)
for a step-by-step guide. For the full feature list, see the
[dkvmmanager repository](https://github.com/glemsom/dkvmmanager).

---

## Project Repositories

| Repository | Purpose |
|------------|---------|
| [glemsom/dkvm](https://github.com/glemsom/dkvm) | This repo. Makefile, scripts, examples, docs. Produces the bootable USB image. |
| [glemsom/dkvmmanager](https://github.com/glemsom/dkvmmanager) | Go TUI binary that runs on tty1. Separate repo, version-pinned in Makefile. |
| [glemsom/dkvm-qemu](https://github.com/glemsom/dkvm-qemu) | Custom QEMU APK repository with DKVM-specific patches. |
