# Configuration Files (DKVMDATA)

DKVM uses two separate persistence layers. This document covers the **DKVMDATA
data partition** — where VM workloads live. For OS-level persistence (Alpine
`lbu` overlay), see the [Architecture document](../contributor/architecture.md#persistence-model).

---

## DKVMDATA Partition

VM workload data (disk images, ISOs, TPM state, VM configs) is stored on a
dedicated ext4 partition labeled `DKVMDATA`. This partition is kept separate
from the USB boot image so it can be large enough for guest operating systems.

### Requirements

| Property       | Value                               |
|----------------|-------------------------------------|
| Filesystem     | ext4                                |
| Label          | `DKVMDATA` (case-sensitive)         |
| Mount point    | `/media/dkvmdata`                   |
| Auto-mount     | Boot script (`dkvm_folder.start`)   |
| Boot behaviour | `nofail` — system boots regardless  |

### Formatting

If you do not already have a partition with the correct label, create one:

```bash
# Replace /dev/sdXY with your target partition (e.g., /dev/sda3)
sudo mkfs.ext4 -L DKVMDATA /dev/sdXY
```

After formatting, reboot the system. The partition is automatically mounted at
`/media/dkvmdata` by `/etc/local.d/dkvm_folder.start` during boot.

> **First-boot behaviour**: if no DKVMDATA partition is found the system still
> boots normally (thanks to `nofail` in fstab). You will see a warning on tty1
> that no data partition is available. Create one as described above and reboot.

### Verifying the Mount

```bash
lsblk -f | grep DKVMDATA
mount | grep dkvmdata
```

Both commands should show the partition mounted at `/media/dkvmdata`.

---

## Directory Layout

Once mounted, the DKVM Manager creates and manages the following structure under
`/media/dkvmdata`:

```
/media/dkvmdata/
├── images/          # VM disk images (*.qcow2, *.raw)
├── iso/             # Guest OS installation ISOs
├── tpm/             # TPM state directories (one per VM, managed by swtpm)
└── config/          # VM configuration files (managed by DKVM Manager)
```

### `images/`

Stores the virtual hard disks for each VM. Files are typically QEMU QCOW2
format (copy-on-write, sparse) but raw images are also supported.

### `iso/`

Guest OS installation ISOs placed here are discoverable by DKVM Manager when
attaching a CDROM drive to a VM. Copy your ISOs here before creating a VM.

### `tpm/`

Per-VM directories containing software TPM (swtpm) state. These are created and
managed automatically by DKVM Manager when TPM is enabled for a VM. Do not
modify them manually.

### `config/`

VM configuration files written and managed exclusively by DKVM Manager. Each VM
has its own configuration that specifies CPU pinning, PCI passthrough devices,
USB devices, memory allocation, disk paths, and other VM parameters.

---

## Important: DKVM Manager is the Only Configuration Interface

All VM and system configuration **must** be done through the DKVM Manager TUI
(launched automatically on tty1). Manual editing of files under `/media/dkvmdata`
or system files is not supported.

**DKVM Manager handles**:
- CPU pinning and topology
- PCI/USB passthrough
- VM creation, editing, and deletion
- Disk and CDROM attachment
- TPM configuration
- Hugepages and memory allocation
- Persistence (via `lbu commit`)

Attempting to edit configuration files by hand may lead to inconsistent state
and is not supported.

---

## Persistence Model Summary

| Layer       | Medium       | Contents                    | Managed by                |
|-------------|--------------|-----------------------------|---------------------------|
| OS overlay  | USB stick    | System config, binaries     | `lbu commit` (DKVM Man.)  |
| VM data     | DKVMDATA     | Disks, ISOs, TPM, VM config | DKVM Manager TUI          |

For full details on how persistence works across boot cycles, see the
[Architecture document](../contributor/architecture.md#persistence-model).
