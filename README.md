# DKVM
DKVM - Desktop KVM

DKVM is a minimal hypervisor that runs entirely from RAM, enabling you to virtualize your own desktop PC with maximum performance. It supports full VGA (GPU) passthrough, PCI‑e device assignment, and other hardware acceleration features, delivering near‑native speed for the guest OS.

The project builds a bootable USB image containing an Alpine Linux base, the required virtualization packages, and a custom DKVM menu (`dkvmmenu.sh`).

## Build Process
Pre-built images are automatically generated via GitHub Actions and available in the [GitHub Releases](https://github.com/glemsom/dkvm/releases) section of this project.

If you wish to build the image manually:
1. Run `./setup.sh`. The script:
   - Sets up an Alpine Linux environment.
   - Extracts the kernel and initramfs.
   - Boots a temporary QEMU VM and runs `scripts/runme.sh` via `expect` to automate the installation.
   - Generates `dkvm-<version>.img`.

## Usage (Linux)

### 1. Download and Unpack
Download the latest release ZIP file from the [Releases](https://github.com/glemsom/dkvm/releases) page and unpack it:
```bash
unzip dkvm-*.zip
```

### 2. Write to USB Disk
Write the resulting `.img` file to your USB stick using `dd`:
```bash
# Replace /dev/sdX with your actual USB device (e.g., /dev/sdb)
# WARNING: This will erase all data on the target device!
sudo dd if=dkvm-*.img of=/dev/sdX bs=4M status=progress && sync
```

### 3. Boot
Configure your system’s BIOS/UEFI to boot from the USB device. After boot, the DKVM menu appears, allowing you to start the VM with GPU passthrough and other options.

## Custom Launcher Menu (`dkvmmenu.sh`)
The interactive menu provides a convenient way to configure and launch the VM:
- **CPU Pinning & Topology** – Detects host CPU topology, reserves cores for the host, and pins guest vCPUs to specific host threads for optimal performance.
- **PCI Passthrough** – Lets you select PCI devices (including GPUs) to pass through to the VM.
- **USB Passthrough** – Allows selection of USB devices to expose to the guest.
- **VM Creation & Editing** – Create new VM configurations, edit existing ones, and adjust disk, CDROM, and other parameters.
- **Hugepages & Memory Allocation** – Configures hugepages and reserves memory for the VM.
- **TPM Support** – Starts a software TPM (`swtpm`) for the guest.
- **Live Monitoring** – Shows QEMU thread IDs, passed‑through devices, and VM status via QMP.
- **Persistence** – Changes are saved using Alpine’s `lbu commit` to ensure they survive reboots.

## Features
- **GPU (VGA) Passthrough** – Direct access to your graphics card for high‑performance graphics.
- **PCI‑e Device Assignment** – Attach other devices such as network cards or USB controllers.
- **Minimal Overhead** – Runs from RAM, no persistent host OS required.
- **Persistent Configuration** – Changes made inside the USB image are saved via Alpine’s LBU system.

For more details, see the blog post: [GlemSom Tech](https://glemsomtechs.blogspot.com/2018/07/dkvm-desktop-kvm.html)
