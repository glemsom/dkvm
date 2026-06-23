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

## Quick Start

1. Download the latest release ZIP from
   [Releases](https://github.com/glemsom/dkvm/releases).
2. Write the image to a USB stick (see
   [First-Boot Walkthrough](docs/user/first-boot.md#1-write-usb)).
3. Boot from USB and follow the
   [walkthrough](docs/user/first-boot.md).

---

## Documentation

### 🧪 Tutorials — start here

| Document | What you'll do |
|----------|----------------|
| [First-Boot Walkthrough](docs/user/first-boot.md) | Write USB image, boot DKVM, configure storage and devices, create your first VM. |

### 🔧 How-to Guides — solve specific problems

| Document | Problem it solves |
|----------|-------------------|
| [Networking](docs/user/networking.md) | Set up bridge, user-mode, or port forwarding networking for guests. |
| [Troubleshooting](docs/user/troubleshooting.md) | Diagnose DKVMDATA mounts, VM boot failures, SSH issues. |
| [Example Scripts](docs/user/example-scripts.md) | GPU driver cycling for AMD 9000-series, CPU pinning verification. |
| [Configuration Files](docs/user/configuration-files.md) | Understand the DKVMDATA partition layout and how VM configs are stored. |

### 📖 Reference — technical details

| Document | What it describes |
|----------|-------------------|
| [Architecture](docs/contributor/architecture.md) | Boot sequence, build pipeline, persistence model, component map. |
| [Local Development](docs/contributor/local-dev.md) | Build commands, quick iteration loop, image inspection, cleanup. |
| [CONTRIBUTING](docs/contributor/CONTRIBUTING.md) | PR process, coding standards, changelog policy. |
| [CHANGELOG](CHANGELOG.md) | Version history and release notes. |

### 🧠 Explanation — deeper understanding

| Document | Topic |
|----------|-------|
| [CONTEXT](CONTEXT.md) | Project terminology and ubiquitous language (what "DKVM", "DKVMDATA", "Guest" mean). |
| [Architecture](docs/contributor/architecture.md) | How DKVM works end-to-end — boot, build, persistence, ACPI. |
| [Persistence Model](docs/user/configuration-files.md#persistence-model-summary) | How OS settings and VM data survive reboots. |

---

## Build Process

Pre-built images are available in
[GitHub Releases](https://github.com/glemsom/dkvm/releases).

To build manually:

```bash
make verify-deps
make build
```

Output: `dkvm-<version>.img` — a bootable FAT32 disk image.

For detailed build instructions, see
[Local Development](docs/contributor/local-dev.md).

---

## DKVM Manager

The **DKVM Manager** is a Golang-based TUI that provides a convenient way to
configure and launch VMs:

- **CPU Pinning & Topology** – Detects host CPU topology, reserves cores for
  the host, and pins guest vCPUs to specific host threads.
- **PCI Passthrough** – Lets you select PCI devices (including GPUs) to pass
  through to the VM.
- **USB Passthrough** – Allows selection of USB devices to expose to the guest.
- **VM Creation & Editing** – Create new VM configurations, edit existing ones,
  and adjust disk, CDROM, and other parameters.
- **Hugepages & Memory Allocation** – Configures hugepages and reserves memory
  for the VM.
- **TPM Support** – Starts a software TPM (`swtpm`) for the guest.
- **Persistence** – Changes are saved using Alpine's `lbu commit` to ensure they
  survive reboots.

For more details, see the blog post:
[GlemSom Tech](https://glemsomtechs.blogspot.com/2018/07/dkvm-desktop-kvm.html).

---

## Project Repositories

| Repository | Purpose |
|------------|---------|
| [glemsom/dkvm](https://github.com/glemsom/dkvm) | This repo. Makefile, scripts, examples, docs. Produces the bootable USB image. |
| [glemsom/dkvmmanager](https://github.com/glemsom/dkvmmanager) | Go TUI binary that runs on tty1. Separate repo, version-pinned in Makefile. |
| [glemsom/dkvm-qemu](https://github.com/glemsom/dkvm-qemu) | Custom QEMU APK repository with DKVM-specific patches. |
