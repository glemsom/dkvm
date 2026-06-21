# First-Boot Walkthrough

This guide walks through your first DKVM session — from writing the USB image to
running your first virtual machine.

If you run into problems, see the [Troubleshooting](troubleshooting.md) guide.

---

## 1. Write USB

Download the latest release ZIP from the
[Releases page](https://github.com/glemsom/dkvm/releases) and unpack it:

```bash
unzip dkvm-*.zip
```

Write the image to a USB stick (replace `/dev/sdX` with your device):

```bash
sudo dd if=dkvm-<version>.img of=/dev/sdX bs=4M status=progress && sync
```

> **Warning**: This erases all data on the target device. Double-check the device
> path before running.

---

## 2. Booting

Configure your system BIOS/UEFI to boot from the USB device.

### What You See

```
GRUB menu → Alpine kernel messages → tty1: DKVM Manager TUI
```

1. **GRUB** — the bootloader appears briefly, then loads the Alpine LTS kernel
   with IOMMU/VFIO parameters (see
   [Architecture](../contributor/architecture.md#boot-sequence) for details).
2. **Kernel messages** — scroll by as the system boots from RAM (diskless mode).
3. **tty1** — the DKVM Manager TUI launches automatically.

### First-Boot Behaviour

On the very first boot, no `DKVMDATA` partition exists yet. The DKVM Manager
shows a warning that no data partition is available. This is expected — the
system boots normally thanks to the `nofail` option in fstab.

Proceed to the next section to set up the data partition.

---

## 3. Setting Up DKVMDATA

DKVM requires a dedicated ext4 partition labeled `DKVMDATA` for VM disk images,
ISOs, TPM state, and configuration. This partition is auto-mounted at
`/media/dkvmdata`.

### 3.1 Identify the Target Partition

Use `lsblk` or `fdisk` to find the disk and partition you want to use:

```bash
lsblk
```

Choose a partition that has enough free space for your guest VMs (at least
50 GB recommended).

### 3.2 Format and Label

Replace `/dev/sdXY` with your target partition (e.g., `/dev/sda3`):

```bash
sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
```

### 3.3 Reboot

Reboot the system:

```bash
reboot
```

After reboot, the partition is automatically mounted at `/media/dkvmdata`.
Verify with:

```bash
lsblk -f | grep DKVMDATA
mount | grep dkvmdata
```

For more details on the DKVMDATA layout, see the
[Configuration Files](configuration-files.md) document.

---

## 4. Configuring via DKVM Manager

All system and VM configuration is done through the DKVM Manager TUI on tty1.
No manual file editing is needed.

### 4.1 CPU Pinning

1. From the main menu, select **CPU Pinning**.
2. DKVM Manager detects the host CPU topology (sockets, cores, threads).
3. Choose which cores to reserve for the host OS and which to assign to the
   guest. A common setup is to reserve 1-2 cores for the host and dedicate the
   rest to the VM.
4. Save the configuration.

### 4.2 PCI Passthrough

1. Select **PCI Passthrough** from the main menu.
2. You will see a list of PCI devices on the host.
3. Select the GPU and any other devices to pass through to the guest.
4. The system configures `vfio-pci` to bind these devices on boot.
5. Save the configuration.

> **GPU passthrough note**: If your GPU is currently in use by the host display
> driver, you may need to add it to the VFIO blacklist (handled by DKVM Manager)
> and reboot.

### 4.3 USB Passthrough

1. Select **USB Passthrough** from the main menu.
2. Choose USB devices to expose to the guest (e.g., keyboard, mouse,
   USB dongles).
3. Save the configuration.

### 4.4 Memory and Hugepages

1. Select **Memory / Hugepages** from the main menu.
2. Configure hugepage size and count. Hugepages reduce memory overhead and
   improve guest performance.
3. Set the memory allocation for the guest VM.
4. Save the configuration.

### 4.5 Creating a VM

1. Select **Create VM** from the main menu.
2. Fill in:
   - **VM name** — a descriptive name (e.g., `win10-gaming`).
   - **Disk image** — choose an existing image or create a new one. Images are
     stored on `DKVMDATA` under `/media/dkvmdata/images/`.
   - **CDROM / ISO** — optionally attach a guest OS installation ISO from
     `/media/dkvmdata/iso/`.
   - **TPM** — optionally enable software TPM (`swtpm`) for the guest.
3. Save the VM configuration.

---

## 5. Verifying Setup

### 5.1 Launch the VM

From the DKVM Manager main menu, select the VM and choose **Start**.

### 5.2 Check Passthrough Devices

Once the guest OS is running, verify that passthrough devices are visible inside
the guest:

- **GPU** — check the device manager or `lspci` in the guest.
- **USB devices** — plugged devices should appear in the guest.
- **PCI devices** — verify with `lspci` in the guest.

### 5.3 Guest Networking

The guest receives a LAN IP via DHCP on the `br0` bridge. Check the guest IP
and try connecting:

```bash
# From another machine on the LAN
ssh root@<guest-ip>
```

See the [Networking](networking.md) document for more details.

---

## 6. Next Steps

- **Persist changes** — DKVM Manager runs `lbu commit` automatically when you
  save configuration. The system state (binaries, config, overlay) persists on
  the USB across reboots.
- **Add more VMs** — repeat the VM creation steps for additional guests.
- **Explore examples** — see the
  [example scripts](../examples/verify_pinning.sh) for GPU passthrough and CPU
  pinning workflows.
- **Read the Architecture doc** — for a deep understanding of the boot sequence
  and components, see the [Architecture](../contributor/architecture.md)
  document.

---

## Reference

| Step              | Document                                                        |
|-------------------|-----------------------------------------------------------------|
| Boot flow         | [Architecture](../contributor/architecture.md#boot-sequence)    |
| DKVMDATA layout   | [Configuration Files](configuration-files.md)                   |
| Networking modes  | [Networking](networking.md)                                     |
| Common problems   | [Troubleshooting](troubleshooting.md)                           |
| Build & develop   | [Local Development](../contributor/local-dev.md)                |
