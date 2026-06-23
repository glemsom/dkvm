# Example Scripts

This document describes the two example scripts provided in the DKVM `examples/`
directory. They are optional helpers — you do not need them for basic DKVM
operation.

> **Terminology**: See [CONTEXT.md](../../CONTEXT.md) for definitions of
> "DKVMDATA", "Guest", "Host", "lbu", and other project terms.

---

## 1. `amd_9000_StartStop.sh`

**Purpose**: Enable PCI passthrough for AMD 9000-series GPUs by cycling the
`amdgpu` kernel driver. These GPUs need a special driver unload/load sequence
before `vfio-pci` can claim them. The script automates that sequence.

**File**: [`examples/amd_9000_StartStop.sh`](../../examples/amd_9000_StartStop.sh)

### Requirements

- AMD 9000-series GPU with IOMMU enabled (`amd_iommu=on` on kernel cmdline)
- `vfio-pci` kernel module loaded
- DKVM system with PCI passthrough configured
25:d05|
### Installation

Place the script so DKVM Manager loads it on startup:

1. **Copy the script** to the DKVMDATA mount:
   ```bash
   cp examples/amd_9000_StartStop.sh /media/dkvmdata/amd_9000_StartStop.sh
   ```

2. **Source it from DKVM Manager's `.profile`** — DKVM Manager sources
   `/media/dkvmdata/.profile` at startup. Either:
   - Create/edit `/media/dkvmdata/.profile` and add:
     ```bash
     source /media/dkvmdata/amd_9000_StartStop.sh
     ```
   - Or source from the host's root profile instead:
     ```bash
     echo "source /media/dkvmdata/amd_9000_StartStop.sh" >> /root/.profile
     ```

3. **Reload the profile** (or reboot):
   ```bash
   source /root/.profile
   ```

### Verification

Confirm the hooks are loaded:
```bash
declare -f customVMStart customVMStop
```
This prints both function bodies if they are correctly registered. If you see
`customVMStart: not found`, the script is not being sourced.

### How DKVM Manager Integration Works

DKVM Manager looks for two optional shell functions that you can define:

- `customVMStart()` — called **before** the VM starts
- `customVMStop()` — called **after** the VM stops

The `amd_9000_StartStop.sh` script provides both. Source it from your shell
profile or place it where DKVM Manager can load it (e.g., via
`/media/dkvmdata/`).

### What `customVMStart()` Does

1. **Reads passthrough device list** from `/media/dkvmdata/passthroughPCIDevices`
   (set by DKVM Manager).
2. **Detects the VGA device** among the passthrough devices (class `0x03*`).
3. **Protects iGPUs** — any VGA-class device not in the passthrough list gets a
   `driver_override` so `amdgpu` will not claim it.
4. **Loads the `amdgpu` module** (required before the driver cycle).
5. **Unbinds all passthrough devices** from their current drivers.
6. **Performs the AMDGPU driver cycle** for the VGA device:
   - Bind `amdgpu` to the VGA device (initializes the card)
   - Unbind `amdgpu` from the VGA device
7. **Binds all passthrough devices** to `vfio-pci`.

### What `customVMStop()` Does

1. **Reads passthrough device list** from the system.
2. **Unbinds all passthrough devices** from `vfio-pci`.
3. **Removes VFIO IDs** so the kernel can re-attach native drivers on next boot.

### Important Notes

- The iGPU protection logic prevents the `amdgpu` driver from accidentally
  attaching to an integrated GPU that should remain available for the host.
- The `sleep` calls in the script are timing heuristics — adjust if your
  hardware needs more settle time.
- This script is specific to AMD 9000-series. Other AMD GPUs or NVIDIA GPUs
  have different driver requirements.

---

## 2. `verify_pinning.sh`

**Purpose**: Verify that CPU pinning configured in DKVM Manager is actually
working. It runs **inside the guest VM**, correlates guest vCPUs to host
physical cores, and reports PASS/FAIL for core sibling and die topology
consistency.

**File**: [`examples/verify_pinning.sh`](../../examples/verify_pinning.sh)

### Requirements

- Passwordless SSH root access to the DKVM host (set via SSH key)
- `cpu-pm` (CPU power management) disabled in the VM configuration
- `lscpu`, `taskset`, `yes` available in the guest (standard on most Linux
  guests)

### Configuration

Edit the `HOST_IP` variable at the top of the script to match your DKVM host's
IP address on the bridge network:

```bash
HOST_IP="192.168.50.21"
```

### Usage

1. Copy the script to your guest VM (e.g., via `scp`).
2. Inside the guest, run:
   ```bash
   ./verify_pinning.sh
   ```

### How It Works

1. **Fetch guest topology** — reads `lscpu -p=CPU,Core` to map guest vCPU IDs
   to guest core IDs.
2. **Fetch host topology** — SSHs into the DKVM host and reads sysfs for each
   CPU: `core_id`, `thread_siblings_list`, `die_id`, cache info, and CPPC
   performance values.
3. **Collect guest siblings** — reads `thread_siblings_list` and `die_id` from
   the guest's own sysfs.
4. **For each guest vCPU**:
   - Pins a load generator (`yes >/dev/null`) to that vCPU via `taskset`.
   - SSHs to the host and compares `/proc/stat` snapshots to detect which
     physical host CPU is handling the load.
   - Records the mapping.
5. **Core sibling verification** — checks that vCPUs sharing a guest core map
   to the same host physical core.
6. **CPU-die verification** — checks that vCPUs on the same guest die map to
   the same host die.

### Output Interpretation

#### Main Table

```
Guest vCPU    | Guest Core ID  | Guest Die  | Host Logical CPU | Host Core ID    | L3 Cache    | CPPC
-------------|----------------|------------|-----------------|-----------------|------------|----------
0            | 0              | 0          | 4               | 0               | 32M        | 204
1            | 0              | 0          | 5               | 0               | 32M        | 204
2            | 1              | 0          | 6               | 1               | 32M        | 204
3            | 1              | 0          | 7               | 1               | 32M        | 204
```

- **Guest vCPU** — virtual CPU ID inside the guest.
- **Guest Core ID** — the core this vCPU belongs to (from guest topology).
- **Guest Die** — the die this vCPU belongs to.
- **Host Logical CPU** — the physical host CPU that handled the load.
- **Host Core ID** — the physical core on the host.
- **L3 Cache** — L3 cache size on the host core (useful for spotting CCD
  boundaries on AMD).
- **CPPC** — CPPC highest performance value (indicates preferred/turbo cores).

#### Core Sibling Verification

```
Guest Core ID | Guest vCPU  | Host Core ID  | Host Logical CPU | Status
--------------|-------------|---------------|-----------------|---------
Core 0        | vCPU 0      | 0             | 4               | PASS
Core 0        | vCPU 1      | 0             | 5               | PASS
Core 1        | vCPU 2      | 1             | 6               | PASS
Core 1        | vCPU 3      | 1             | 7               | PASS
```

- **PASS** — all vCPUs in the same guest core map to the same host core.
  Pinning is correct.
- **FAIL** — vCPUs in the same guest core map to different host cores.
  Pinning is misconfigured.

#### CPU-Die Verification

```
Guest Die ID  | Guest vCPUs                   | Host Die ID    | Status
--------------|-------------------------------|---------------|---------
Die 0         | 0,1,2,3                       | 0             | PASS
```

- **PASS** — all vCPUs on the same guest die map to the same host die.
- **FAIL** — vCPUs on the same guest die map to different host dies.

### Troubleshooting

- **No output / connection refused**: Verify `HOST_IP` is correct and SSH access
  works manually first.
- **All results show FAIL**: `cpu-pm` is likely enabled. Disable it in the VM
  configuration via DKVM Manager.
- **Inconsistent results across runs**: Background load on the host can
  interfere. Run the test on an idle system.

---

## Security Notes

- `verify_pinning.sh` needs passwordless root SSH access to the DKVM host.
  Ensure your DKVM host is on a trusted network.
- The example scripts are provided as-is for reference. Review them before
  running on your hardware.
- Only use these scripts on hardware you own and control.

## Reference

| Topic | Document |
|-------|----------|
| First-time setup | [First-Boot Walkthrough](first-boot.md) |
| GPU passthrough setup | [GPU Passthrough](gpu-passthrough.md) |
| Architecture & design | [Architecture Overview](../contributor/architecture-overview.md) |
| Build & develop | [Local Development](../contributor/local-dev.md) |
| Project terminology | [CONTEXT](../../CONTEXT.md) |

---

*Last updated: 2026-06-23*
