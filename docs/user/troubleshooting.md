# Troubleshooting

Common problems and how to diagnose them.

If your issue is not covered here, check the logs (see [Getting Logs](#getting-logs)) and open a
[GitHub issue](https://github.com/glemsom/dkvm/issues).

---

## DKVMDATA Not Mounting

The `DKVMDATA` partition is required for VM disk images, ISOs, TPM state, and VM
configurations. The system boots without it (thanks to `nofail` in fstab), but
the DKVM Manager shows a warning and VMs cannot start.

### 1. Verify Partition Label

The partition **must** have the exact filesystem label `DKVMDATA` (case-sensitive).

```bash
blkid | grep DKVMDATA
```

If nothing appears, list all partitions:

```bash
lsblk -f
```

Look for your target partition — if the label is missing or wrong, re-label it:

```bash
# Replace /dev/sdXY with your partition
sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
```

> **Warning**: Formatting destroys all data on the partition.

### 2. Check Mount Status

```bash
mount | grep dkvmdata
```

Expected output: `/dev/sdXY on /media/dkvmdata type ext4 (rw,noatime,nofail...)`

If not mounted, try mounting manually:

```bash
sudo mount /dev/sdXY /media/dkvmdata
```

### 3. Check dmesg for Mount Errors

```bash
dmesg | grep -i dkvmdata
dmesg | grep -i ext4 | tail -20
```

Common causes:

| Symptom                         | Likely Cause                          |
|---------------------------------|---------------------------------------|
| `wrong fs type`                 | Partition is not ext4                 |
| `can't read superblock`         | Corrupted partition or wrong device   |
| `mount: /media/dkvmdata: ...`   | `nofail` — check `/etc/fstab` entry   |

### 4. Filesystem Type

DKVM requires **ext4**. Check with:

```bash
blkid /dev/sdXY
```

If the TYPE field is not `ext4`, reformat (see step 1).

### 5. Verify Contents

If mounted but DKVM Manager still shows a warning, check the expected layout:

```bash
ls -la /media/dkvmdata/
```

A fresh partition is empty — this is normal. The DKVM Manager creates the
required subdirectories (`images/`, `iso/`, `tpm/`, `config/`) on first launch.

For full details on the DKVMDATA layout, see the
[Configuration Files](configuration-files.md) document.

---

## VM Won't Boot

### 1. Check OVMF Firmware

DKVM uses TianoCore OVMF (UEFI) firmware. Verify it is present:

```bash
ls -la /usr/share/ovmf/ /usr/share/qemu/ovmf-*.fd 2>/dev/null
```

If OVMF is missing, the VM cannot start. Rebuild the image or copy the firmware
from the build host.

### 2. Verify Kernel IOMMU/VFIO Parameters

The boot kernel must have IOMMU and VFIO enabled. Check current parameters:

```bash
cat /proc/cmdline
```

Expected flags: `intel_iommu=on` or `amd_iommu=on`, `iommu=pt`, `vfio-pci.ids=...`

If these are missing, the VM will not have hardware passthrough capability.
The GRUB configuration is set during image build — see the
[Architecture document](../contributor/architecture.md#boot-sequence).

### 3. Check Passthrough Device IDs

Verify the devices you selected for passthrough are correctly bound to `vfio-pci`:

```bash
lspci -nnk | grep -A3 VGA
lspci -nnk | grep -A3 Audio
```

Look for `Kernel driver in use: vfio-pci`. If the device is still bound to the
host driver (e.g., `nvidia`, `amdgpu`, `snd_hda_intel`), the VM may fail to
start or crash.

**Common GPU passthrough issues:**

- **IOMMU group not isolated** — check the group:
  ```bash
  for d in /sys/kernel/iommu_groups/*/devices/*; do echo "$(basename $(dirname $d)): $(basename $d)"; done
  ```
  If your GPU shares a group with other devices, all devices in the group must
  be passed through or isolated via ACS override patches.

- **Missing VBIOS** — some GPUs require a VBIOS ROM file. DKVM Manager can
  specify one. Ensure any custom VBIOS is valid for your GPU.

- **GPU currently in use** — the GPU must not be the primary display output. Use
  an iGPU or secondary GPU for the DKVM host.

### 4. Check QEMU Output

If you launched the VM from a terminal (or via the Makefile `run` target), QEMU
output appears on stderr. Look for error messages such as:

- `Failed to assign device`
- `Could not open '/dev/vfio/...'`
- `kvm: ... unsupported`

If the VM was started from DKVM Manager (tty1), check the log output via QMP
(see [Getting Logs](#getting-logs) below).

### 5. QMP — Power and Diagnostics

The DKVM host exposes a QEMU Machine Protocol (QMP) socket on **localhost:4444**
when a VM is running. You can send QMP commands to inspect or control the VM:

```bash
# Connect and enable capabilities
echo '{ "execute": "qmp_capabilities" }' | nc localhost 4444

# Query VM status
echo '{ "execute": "query-status" }' | nc localhost 4444

# Send system powerdown
echo '{ "execute": "system_powerdown" }' | nc localhost 4444
```

Use `query-status` to confirm whether the VM is running, paused, or stopped.

---

## SSH Access Not Working

See the [Networking troubleshooting](networking.md#ssh-access-not-working) section
for detailed steps. Summary:

- Confirm DKVM host IP: `ip addr show br0`
- Root SSH is enabled by default (`PermitRootLogin yes`)
- Test from another machine: `ssh root@<dkvm-ip>`
- Check `sshd` is running: `rc-service sshd status`
- Verify bridge networking is up: `ip a show br0`

### Bridge Not Up

```bash
ip a show br0
```

If `br0` is missing, check `/etc/network/interfaces` and restart networking:

```bash
rc-service networking restart
```

### Firewall / Network Segment

If the DKVM host is behind a firewall or on an isolated segment, ensure:

- The LAN router gives DHCP leases to the bridge interface.
- Inbound traffic to the DKVM host is allowed.
- The physical cable is connected and `eth0` has link:
  ```bash
  ip link show eth0
  ```

---

## Getting Logs

### QMP (Runtime VM Diagnostics)

When a VM is running, QMP is available on localhost:4444:

```bash
echo '{ "execute": "qmp_capabilities" }' | nc localhost 4444
echo '{ "execute": "query-status" }' | nc localhost 4444
```

For QEMU event notifications, use:

```bash
echo '{ "execute": "qmp_capabilities" }' | nc localhost 4444
echo '{ "execute": "query-events" }' | nc localhost 4444
```

### Kernel Messages (dmesg)

Kernel and driver messages are useful for diagnosing hardware passthrough issues:

```bash
dmesg | grep -i vfio
dmesg | grep -i iommu
dmesg | grep -i pci
```

### DKVM Manager Output

The DKVM Manager TUI runs on tty1. If it crashes or produces errors, switch to
another TTY (e.g., `Ctrl+Alt+F2`) and check the terminal output. You can return
to tty1 with `Ctrl+Alt+F1`.

### System Logs

Alpine OpenRC logs are in `/var/log/`:

```bash
ls /var/log/
cat /var/log/messages   # General system messages
```

---

## Still Stuck?

- Check the [Networking](networking.md) doc for network-specific issues.
- Review the [First-Boot Walkthrough](first-boot.md) to ensure all setup steps
  were followed.
- Read the [Architecture document](../contributor/architecture.md) for a deep
  understanding of boot sequence and components.
- Search or open a [GitHub issue](https://github.com/glemsom/dkvm/issues).
