# DKVM
DKVM - Desktop KVM

DKVM is a minimal hypervisor that runs entirely from RAM, enabling you to virtualize your own desktop PC with maximum performance. It supports full VGA (GPU) passthrough, PCI‑e device assignment, and other hardware acceleration features, delivering near‑native speed for the guest OS.

The project builds a bootable USB image containing an Alpine Linux base, the required virtualization packages, and a custom DKVM menu (`dkvmmenu.sh`).

## Features
- **GPU (VGA) Passthrough** – Direct access to your graphics card for high‑performance graphics.
- **PCI‑e Device Assignment** – Attach other devices such as network cards or USB controllers.
- **Minimal Overhead** – Runs from RAM.

## Build Process
Pre-built images are available in the [GitHub Releases](https://github.com/glemsom/dkvm/releases) section of this project.

If you wish to build the image manually:
1. Verify dependencies: `make verify-deps`
2. Run `make build`. This will:
   - Download Alpine Linux ISO (if needed)
   - Find and copy OVMF files (if needed)
   - Set up an Alpine Linux environment.
   - Extract the kernel and initramfs.
   - Boots a temporary QEMU VM and runs `scripts/runme.sh` via `expect` to automate the installation.
   - Generate `dkvm-<version>.img`.

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
sudo dd if=dkvm-<version>.img of=/dev/sdX bs=4M status=progress && sync
```

### 3. Boot
Configure your system’s BIOS/UEFI to boot from the USB device.
On the first boot, you should configure the storage partition as described in the next section - and reboot the system.
After rebooting, you should configure CPU Affinity, PCI Passthrough, USB Passthrough and other settings in the DKVM menu.

### 4. Storage Configuration (`dkvmdata`)
DKVM requires a persistent storage area for VM data (hard disks, ISOs, TPM state, and configurations). For automatic mounting, the partition **MUST** have the filesystem label `DKVMDATA`.

It will be mounted at:
```
/media/dkvmdata
```

**Example (formatting and labeling a partition as ext4):**
```bash
# Replace /dev/sdXY with your target partition
sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
```
The DKVM menu will look for VM configurations and data in this directory.

## Custom Launcher Menu
The interactive menu provides a convenient way to configure and launch the VM:
- **CPU Pinning & Topology** – Detects host CPU topology, reserves cores for the host, and pins guest vCPUs to specific host threads for optimal performance.
- **PCI Passthrough** – Lets you select PCI devices (including GPUs) to pass through to the VM.
- **USB Passthrough** – Allows selection of USB devices to expose to the guest.
- **VM Creation & Editing** – Create new VM configurations, edit existing ones, and adjust disk, CDROM, and other parameters.
- **Hugepages & Memory Allocation** – Configures hugepages and reserves memory for the VM.
- **TPM Support** – Starts a software TPM (`swtpm`) for the guest.
- **Persistence** – Changes are saved using Alpine’s `lbu commit` to ensure they survive reboots.

For more details, see the blog post: [GlemSom Tech](https://glemsomtechs.blogspot.com/2018/07/dkvm-desktop-kvm.html)
