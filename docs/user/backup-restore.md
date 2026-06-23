# Backup, Restore, and Migration

DKVM separates VM data from the boot USB. VM disk images, ISOs, TPM state, and
VM configurations live on the `DKVMDATA` partition. This guide shows how to
protect that data, recover it after a failure, and move it to another DKVM host.

> **Terminology**: See [CONTEXT.md](../../CONTEXT.md) for definitions of
> "DKVMDATA", "Guest", "Host", "lbu", and other project terms.

## Prerequisites

Before performing a backup, restore, or migration:

- **A running DKVM host** with `DKVMDATA` mounted at `/media/dkvmdata`.
  Follow the [First-Boot Walkthrough](first-boot.md) if you have not set this up
  yet.
- **An external storage device** — a USB drive, external SSD, or network-mounted
  directory with enough free space to hold the contents of your DKVMDATA
  partition.
- **For migration**: a second DKVM host (or one you will re-purpose) that can
  mount a `DKVMDATA` partition.
- **Root shell access** on the DKVM host via tty1 or SSH.

---

## 1. Backing Up DKVMDATA

The safest approach is to shut down all running VMs and copy the DKVMDATA
partition contents to an external drive.

### 1.1 Shut Down All VMs

From the DKVM Manager TUI on tty1, stop each running VM. Alternatively, stop a
VM from the command line:

```bash
# List running VMs (QEMU processes)
ps aux | grep qemu

# Gracefully shut down a VM via QMP
echo '{"execute":"qmp_capabilities"}{"execute":"system_powerdown"}' | nc localhost 4444
```

Wait until all QEMU processes have exited before proceeding.

### 1.2 Mount the External Drive

Insert your external storage device and mount it:

```bash
# Identify the device (e.g., /dev/sdb1)
lsblk

# Create a mount point and mount
mkdir -p /mnt/backup
mount /dev/sdb1 /mnt/backup
```

> If the external drive uses a filesystem not supported by the DKVM host (e.g.,
> NTFS, exFAT), format it as ext4 first, or use a drive already formatted as
> ext4 / FAT32.

### 1.3 Copy DKVMDATA with rsync

Use `rsync` to preserve permissions, ownership, and sparse file handling for
QCOW2 disk images:

```bash
rsync -avh --sparse --progress /media/dkvmdata/ /mnt/backup/dkvmdata/
```

- **`-a`** — archive mode (preserves permissions, timestamps, symlinks).
- **`-v`** — verbose output.
- **`--sparse`** — preserve sparseness of QCOW2 images (saves space).
- **`--progress`** — show transfer progress per file.

Alternatively, use `cp` for a simpler copy:

```bash
cp -a /media/dkvmdata/ /mnt/backup/dkvmdata/
```

### 1.4 Verify the Backup

Check that the backup contains all expected directories:

```bash
ls -la /mnt/backup/dkvmdata/
```

Expected layout:

```
/mnt/backup/dkvmdata/
├── config/          # VM configuration files
├── images/          # VM disk images
├── iso/             # Guest OS ISOs
└── tpm/             # swtpm state directories
```

Compare file counts or total sizes:

```bash
echo "Original:"
du -sh /media/dkvmdata/
echo "Backup:"
du -sh /mnt/backup/dkvmdata/
```

### 1.5 Unmount and Store

```bash
sync
umount /mnt/backup
```

Store the external drive in a safe location.

---

## 2. Restoring from Backup

Use this procedure when DKVMDATA is corrupted, the drive fails, or you are
recreating the partition on a new drive.

### 2.1 Create a New DKVMDATA Partition

If the old partition is gone or unusable, create a new one:

```bash
# Replace /dev/sdXY with your target partition (e.g., /dev/sda3)
sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
```

See [Setting Up DKVMDATA](first-boot.md#3-setting-up-dkvmdata) for details.

### 2.2 Mount the Backup Drive

```bash
# Mount the external drive containing your backup
mount /dev/sdb1 /mnt/backup
```

### 2.3 Copy Data Back

```bash
# Ensure DKVMDATA is mounted
mount | grep dkvmdata

# Restore the backup
rsync -avh --sparse --progress /mnt/backup/dkvmdata/ /media/dkvmdata/
```

### 2.4 Verify the Restore

```bash
ls -la /media/dkvmdata/
mount | grep dkvmdata
```

The directory structure should match the backup. Reboot the host to confirm
DKVM Manager detects the restored VMs:

```bash
reboot
```

After reboot, open the DKVM Manager TUI on tty1. Your VMs should appear in the
VM list with their previous configurations.

---

## 3. Migrating VMs to a New DKVM Host

Migration means moving the DKVMDATA drive — or its contents — from one physical
machine to another.

### 3.1 Method A: Move the Entire DKVMDATA Drive

If the DKVMDATA partition lives on a removable drive (e.g., a second internal
SSD or an external drive), you can physically move it:

1. **On the source host**: Shut down all VMs, then power off the DKVM host.
2. **Remove the drive** containing the DKVMDATA partition.
3. **Install the drive** in the new DKVM host machine.
4. **Boot the new host** from a DKVM USB stick.
5. The DKVMDATA partition is auto-detected and mounted at `/media/dkvmdata`.
   Verify:
   ```bash
   mount | grep dkvmdata
   ```

### 3.2 Method B: rsync Over SSH (Network Migration)

Use this when both hosts are on the same network and you want to copy data
without physically moving drives.

1.  **On the source host**, ensure SSH is running and accessible:
    ```bash
    rc-service sshd status
    ```

2.  **On the destination host**, mount a fresh DKVMDATA partition
    (see [Restoring from Backup](#2-restoring-from-backup)).

3.  **From the destination host**, pull the data over SSH:
    ```bash
    # Replace <source-ip> with the source DKVM host's IP
    rsync -avh --sparse --progress -e ssh root@<source-ip>:/media/dkvmdata/ /media/dkvmdata/
    ```

4.  Verify the sync:
    ```bash
    ls -la /media/dkvmdata/
    ```

5.  Reboot the destination host:
    ```bash
    reboot
    ```

### 3.3 Post-Migration Checks

After migration, verify on the new host:

- `mount | grep dkvmdata` shows the partition
- DKVM Manager TUI lists all migrated VMs
- Start a VM and confirm it boots
- Update networking configuration in DKVM Manager if the new host is on a
  different subnet (see [Networking](networking.md))

---

## 4. Full USB Backup with `dd`

For a complete bit-for-bit copy of the entire DKVM USB boot drive (including the
Alpine OS overlay), use `dd`. This is useful for duplicating your exact DKVM
setup, including the `lbu` overlay configuration.

```bash
# Identify the USB device (e.g., /dev/sdc — **not** a partition)
lsblk

# Create a full disk image
sudo dd if=/dev/sdc of=/mnt/backup/dkvm-usb.img bs=4M status=progress && sync
```

> **Warning**: `dd` copies the entire device block-by-block, including unused
> space. The resulting image is the same size as the USB drive. For a 16 GB
> USB stick, expect a 16 GB image file.

### Restoring a `dd` Backup

```bash
# Write the image back to a USB stick (replace /dev/sdc with your device)
sudo dd if=/mnt/backup/dkvm-usb.img of=/dev/sdc bs=4M status=progress && sync
```

### When to Use Which Method

| Situation                                  | Recommended Method                          |
|--------------------------------------------|---------------------------------------------|
| Protect VM data only                       | `rsync` DKVMDATA (Section 1)                |
| Full USB replacement (OS + overlay)        | `dd` (Section 4)                            |
| Recover after DKVMDATA failure             | Restore from `rsync` (Section 2)            |
| Move VMs to new hardware                   | Migration (Section 3)                       |
| Clone identical USB sticks for deployment  | `dd` (Section 4)                            |

---

## 5. What Does NOT Survive

Understanding DKVM's two-layer persistence helps you know what a DKVMDATA
backup covers and what it misses.

| Layer       | Medium       | Contents                               | Survives DKVMDATA backup? |
|-------------|--------------|----------------------------------------|---------------------------|
| VM data     | DKVMDATA     | Disk images, ISOs, TPM state, configs  | ✅ Yes — this is what you back up |
| OS overlay  | USB stick    | System config, binaries, lbu overlay   | ❌ No — backed up separately via `dd` or `lbu` |

### What a DKVMDATA Backup Does NOT Cover

- **Alpine OS configuration** — DKVM Manager settings for CPU pinning, PCI/USB
  passthrough, memory, and hugepages are persisted via `lbu commit` to the USB
  stick, **not** to DKVMDATA. If the USB stick fails or is replaced, these
  settings are lost.
- **Example scripts** placed outside `/media/dkvmdata/` — scripts sourced
  from `/root/.profile` or other system locations.
- **SSH host keys** — regenerated on first boot of a new USB image.
- **Network configuration** — bridge setup, hostname, and DHCP client state are
  part of the OS overlay on the USB.

### To Preserve OS Overlay Settings

Include a `dd` backup of the USB stick (Section 4), or manually record your
DKVM Manager configuration and re-apply it on a fresh install.

---

## Reference

| Task                   | Command / Method       | Section                               |
|------------------------|------------------------|---------------------------------------|
| Backup VM data         | `rsync -avh --sparse` | [Section 1](#1-backing-up-dkvmdata)   |
| Restore from backup    | `rsync` / `cp -a`     | [Section 2](#2-restoring-from-backup) |
| Migrate DKVMDATA drive | Physical move or rsync | [Section 3](#3-migrating-vms-to-a-new-dkvm-host) |
| Full USB clone         | `dd`                   | [Section 4](#4-full-usb-backup-with-dd) |
| OS overlay persistence | `lbu commit`          | [Architecture Reference](../contributor/architecture-reference.md#persistence-model) |
| DKVMDATA layout        | —                      | [Configuration Files](configuration-files.md) |
| DKVMDATA setup         | `mkfs.ext4 -L DKVMDATA` | [First-Boot Walkthrough](first-boot.md#3-setting-up-dkvmdata) |

---

*Last updated: 2026-06-23*
