# DKVM
DKVM - Desktop KVM

DKVM is a minimal hypervisor that runs entirely from RAM, enabling you to virtualize your own desktop PC with maximum performance. It supports full passthrough, PCI‑e device assignment, and other hardware acceleration features, delivering near‑native speed for the guest OS.

The project builds a bootable USB image containing an Alpine Linux base, the necessary virtualization packages, and a custom DKVM menu (`dkvmmenu.sh`). The resulting `usbdisk.img` can be written to a USB stick and booted directly from BIOS/UEFI, turning any machine into a dedicated KVM host.

## Build Process
1. Run `./setup.sh`. The script:
   - Sets up an Alpine Linux environment.
   - Extracts the kernel and initramfs.
   - Boots a temporary QEMU VM and runs `scripts/runme.sh` via `expect` to automate the installation.
   - Generates `usbdisk.img`.
2. Write the image to a USB drive, e.g. `sudo dd if=usbdisk.img of=/dev/sdX bs=4M status=progress && sync`.
3. Configure your system’s BIOS/UEFI to boot from the USB device.

After boot, the DKVM menu appears, allowing you to start the VM with GPU passthrough and other options.
On the first boot, configure CPU affinity and other settings via the DKVM menu.

## Custom Launcher Menu (`dkvmmenu.sh`)
The interactive menu provides a convenient way to configure and launch the VM:
- **CPU Pinning & Topology** – Detects host CPU topology, reserves cores for the host, and pins guest vCPUs to specific host threads for optimal performance.
- **PCI Passthrough** – Lets you select PCI devices (including GPUs) to pass through to the VM. The menu automatically detects whether a device is a GPU and enables multifunction mode when needed.
- **USB Passthrough** – Allows selection of USB devices to expose to the guest.
- **VM Creation & Editing** – Create new VM configurations, edit existing ones, and adjust disk, CDROM, and other parameters.
- **Hugepages & Memory Allocation** – Configures hugepages and reserves memory for the VM while leaving headroom for the host.
- **TPM Support** – Starts a software TPM (`swtpm`) for the guest.
- **Live Monitoring** – Shows QEMU thread IDs, passed‑through devices, and VM status via QMP.
- **Power Management** – Options to reboot, power off, or drop to a shell for debugging.
- **Persistence** – Changes are saved using Alpine’s `lbu commit` to ensure they survive reboots.

These features make it easy to fine‑tune the virtual machine for the best possible performance and hardware utilization.

## Features
- **GPU (VGA) Passthrough** – Direct access to your graphics card for high‑performance graphics.
- **PCI‑e Device Assignment** – Attach other devices such as network cards or USB controllers.
- **Minimal Overhead** – Runs from RAM, no persistent host OS required.
- **Persistent Configuration** – Changes made inside the USB image are saved via Alpine’s LBU system.

## Usage
- Boot from the USB stick.
- At the DKVM menu, select “Start VM” to launch your desktop VM.

For more details, see the blog post: [GlemSom Tech](https://glemsomtechs.blogspot.com/2018/07/dkvm-desktop-kvm.html)
