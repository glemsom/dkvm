# GPU Passthrough
<!-- markdownlint-disable MD051 -->

Configure a dedicated GPU for exclusive use by a guest VM with near-native
performance.

DKVM's headline feature is GPU/PCI passthrough — assigning a physical GPU to a
guest so it has direct, unmediated access to the hardware. This guide covers
the full setup: from hardware prerequisites and IOMMU verification to binding
the GPU to `vfio-pci` and diagnosing common failures.

If you run into problems, see the [Troubleshooting](troubleshooting.md) guide.

---

## Prerequisites

Before starting, ensure your hardware and DKVM setup meet these requirements.

### IOMMU Support

| Component     | Intel                  | AMD                    |
|---------------|------------------------|------------------------|
| Technology    | VT-d                   | AMD-Vi                 |
| Kernel param  | `intel_iommu=on`       | `amd_iommu=on`         |

Most modern CPUs and motherboards support IOMMU. Enable it in BIOS/UEFI:

- **Intel**: VT-d (Virtualization Technology for Directed I/O) — often labelled
  *VT-d* or *Intel Virtualization Technology for Directed I/O*.
- **AMD**: SVM (Secure Virtual Machine) plus IOMMU — often labelled *SVM Mode*
  and *IOMMU* in AMD CBS menus.

> **Already enabled in DKVM**: The DKVM boot image passes `intel_iommu=on` or
> `amd_iommu=on` plus `iommu=pt` on the kernel command line by default. Verify
> with `cat /proc/cmdline`.

### Hardware Requirements

- **Secondary GPU** — The GPU you passthrough *cannot* be the host's primary
  display output. Use an integrated GPU (iGPU) or a second dedicated GPU for
  the DKVM host. See [Primary vs Secondary GPU](#5-primary-vs-secondary-gpu).
- **ACS-supporting chipset** — The PCIe root ports must support Access Control
  Services (ACS) so each device ends up in its own IOMMU group. Most modern
  chipsets (Intel Z/X-series, AMD X/B-series) work. See
  [Non-Isolated IOMMU Groups](#non-isolated-iommu-groups) if your GPU shares a
  group with other functions.
- **Sufficient RAM** — The guest needs its own memory allocation (4 GB minimum
  for a desktop OS, 8–16 GB recommended) on top of host needs.
- **UEFI boot** — DKVM boots via UEFI/OVMF. Legacy BIOS boot is not supported
  for GPU passthrough.

### Software Prerequisites

- DKVM booted and DKVM Manager TUI running on tty1.
- A `DKVMDATA` partition set up — see
  [First-Boot Walkthrough](first-boot.md#3-setting-up-dkvdata) if you have not
  done so yet.

---

## 1. Identify GPU PCI Addresses

Each PCI device on the host is identified by a BDF (Bus:Device.Function) address
such as `0000:26:00.0`. You need the addresses of your GPU and its companion
audio function (the HDMI/DP audio controller).

List all VGA-compatible controllers:

```bash
lspci -nn | grep -i vga
```text

Example output:

```text
26:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484] (rev a1)
```text

List audio devices to find the GPU's audio function (same bus, function `.1`):

```bash
lspci -nn | grep -i audio
```text

Example output:

```text
26:00.1 Audio device [0403]: NVIDIA Corporation GA104 High Definition Audio Controller [10de:228b] (rev a1)
```text

Note the full PCI addresses (`0000:26:00.0` and `0000:26:00.1`). You will use
them in the next steps.

---

## 2. Check IOMMU Groups

DKVM Manager handles most passthrough configuration, but it is useful to
understand IOMMU grouping so you can diagnose passthrough failures.

List all IOMMU groups and their devices:

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  echo "$(basename $(dirname $d)): $(basename $d)"
done | sort -t: -k1 -n
```text

Example output for an isolated GPU:

```text
16: 0000:26:00.0
16: 0000:26:00.1
```text

Here the GPU and its audio function share group 16. Because they are the only
devices in the group, both can be passed through together — this is the ideal
scenario.

### Non-Isolated IOMMU Groups

If the output shows additional devices sharing the GPU's group (e.g., an NVMe
SSD, a USB controller, or the GPU's own PCIe bridge), you have a
**non-isolated group**. Running `for d in /sys/kernel/iommu_groups/*/devices/*; do echo "$(basename $(dirname $d)): $(basename $d)"; done | sort -t: -k1 -n` may show:

```text
16: 0000:26:00.0
16: 0000:26:00.1
16: 0000:27:00.0
```text

Options:

1. **Pass all devices in the group** — if the extra devices are not needed by
   the host, add them to the passthrough list in DKVM Manager.
2. **ACS override patch** — the DKVM kernel includes ACS override support,
   which splits groups at the PCIe root port level. Enable it by adding
   `pcie_acs_override=downstream` to the kernel command line. See
   [Architecture Reference](../contributor/architecture-reference.md#boot-sequence) for how to
   modify kernel parameters.
3. **Re-seat the GPU** — moving the GPU to a different PCIe slot can sometimes
   put it in its own group, especially on AMD platforms.

> **Warning**: ACS override bypasses hardware-enforced isolation. Only use it
> on hardware you trust and understand.

---

## 3. Bind GPU to vfio-pci

The `vfio-pci` kernel driver must claim the GPU and its audio function instead
of their native drivers (`nvidia`, `amdgpu`, `snd_hda_intel`, etc.).

### 3.1 Identify Native Drivers

Check which driver is currently bound:

```bash
lspci -nnk -s 26:00
```text

Look for the `Kernel driver in use:` line. For an NVIDIA GPU still bound to
the host driver:

```text
Kernel driver in use: nvidia
```text

### 3.2 Add PCI IDs to vfio-pci

DKVM Manager does this automatically when you select a device in the **PCI
Passthrough** menu and save. The IDs are written to
`/media/dkvmdata/passthroughPCIDevices` and loaded via the
`vfio-pci.ids=kernel parameter`.

If you need to do it manually (for testing), add the vendor and device IDs to
the kernel command line in GRUB:

```text
vfio-pci.ids=10de:2484,10de:228b
```text

The two IDs (comma-separated, no spaces) correspond to the GPU and its audio
function.

### 3.3 Blacklist Native Drivers

The native GPU driver must be prevented from claiming the device before
`vfio-pci` can bind. DKVM Manager handles blacklisting, but if you encounter
issues, verify the blacklist:

```bash
cat /etc/modprobe.d/*.conf | grep -i blacklist
```text

Expected entries:

```text
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
```text

For AMD GPUs:

```text
blacklist amdgpu
```text

> **Note**: On AMD systems with an iGPU that the host uses, do **not** blacklist
> `amdgpu` entirely — see [Primary vs Secondary GPU](#5-primary-vs-secondary-gpu).

### 3.4 Reboot

After configuring PCI passthrough in DKVM Manager, reboot the system:

```bash
reboot
```text

### 3.5 Verify vfio-pci Binding

After reboot, confirm the devices are bound to `vfio-pci`:

```bash
lspci -nnk -s 26:00
```text

Expected output:

```text
26:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484]
        Subsystem: ...
        Kernel driver in use: vfio-pci
        Kernel modules: nvidia

26:00.1 Audio device [0403]: NVIDIA Corporation GA104 High Definition Audio Controller [10de:228b]
        Kernel driver in use: vfio-pci
```text

Also verify that `vfio-pci` has claimed the devices:

```bash
ls -la /dev/vfio/
```text

You should see one or more `vfio` device files (e.g., `/dev/vfio/16` for IOMMU
group 16) plus `/dev/vfio/vfio`.

---

## 4. VBIOS ROM Considerations

QEMU needs access to the GPU's VBIOS (Video BIOS) to initialise the device
when the guest starts. Most GPUs expose their VBIOS via PCI option ROM,
and QEMU reads it automatically.

### When You Need a VBIOS File

- **Secondary GPU** — A GPU that is not the primary display output usually
  works without a custom VBIOS file.
- **Primary GPU passthrough** — If you attempt to pass through the host's
  primary GPU, the VBIOS may be shadowed by the system firmware and
  inaccessible to QEMU. A VBIOS ROM dump from the host or a vendor-provided
  file may be required.
- **Certain NVIDIA cards** — Some NVIDIA GPUs (especially laptop GPUs) do not
  expose a usable VBIOS. You may need to extract one or use a modified
  VBIOS — see [NVIDIA Error 43](#nvidia-error-43).

### Extracting VBIOS

Extract the current GPU VBIOS from the host:

```bash
echo 1 > /sys/bus/pci/devices/0000:26:00.0/rom
cat /sys/bus/pci/devices/0000:26:00.0/rom > /media/dkvmdata/gpu.rom
echo 0 > /sys/bus/pci/devices/0000:26:00.0/rom
```text

Specify the ROM file in your VM configuration via DKVM Manager (set the VBIOS
path in the PCI passthrough device settings).

> **Note**: Not all GPUs support reading the ROM this way. If the `rom` file
> does not exist or is empty, check `dmesg` for errors.

---

## 5. Primary vs Secondary GPU

The GPU passed through to the guest **must not** be the host's primary display
output. DKVM is designed for this scenario — it boots on tty1 via the integrated
GPU or a secondary card while you dedicate the performance GPU to the guest.

### Intel iGPU (Recommended for Host)

Most Intel CPUs include an integrated GPU. Use it as the host display:

1. Connect your monitor to the motherboard video output (HDMI/DP on the I/O
   panel, not the GPU).
2. In BIOS/UEFI, ensure the iGPU is enabled and set as the primary display
   device (often labelled *IGFX* or *Internal Graphics* as primary).
3. DKVM boots on the iGPU via the `simpledrm` or `i915` driver.

### AMD iGPU

AMD APUs (e.g., 7000-series G, 8000-series G) have an integrated GPU. The
same principle applies: set the iGPU as the primary display in BIOS.

If you are using an AMD **dedicated** GPU as the host card, do **not**
blacklist the `amdgpu` driver entirely. Instead, only bind the secondary GPU
to `vfio-pci` by its PCI IDs. The `amdgpu` driver continues to drive the
host's display.

### Dual Dedicated GPUs

If your system has two dedicated GPUs and no iGPU:

1. Use the less powerful GPU for the DKVM host — connect your monitor to it.
2. Pass through the more powerful GPU to the guest.

---

## 6. Reset Issues

GPU reset behaviour differs between vendors and affects how reliably you can
stop and restart the VM.

### NVIDIA

- **Consumer cards (GeForce RTX/GTX)** — Do not support a full function-level
  reset (FLR) in the same way as workstation cards. After the VM stops, the GPU
  may not reset cleanly. A host reboot is often required to use the GPU again
  (either in the guest or if re-binding to the host driver).
- **Workstation/Server cards (Quadro, Tesla)** — Support FLR reliably. You can
  stop and restart the VM without rebooting the host.
- **Mitigation**: Use the vendor-reset tool (not included in DKVM by default)
  or configure a VM lifecycle that minimises GPU restart cycles.

### AMD

- **RX 400/500 series and earlier** — Known for the *AMD reset bug*. After the
  VM stops, the GPU enters an undefined state and cannot be re-initialised
  without a full host power cycle (warm reboot may not suffice).
- **RX 5000 series (RDNA1) and newer** — Improved but not perfect. Some cards
  reset reliably, others exhibit the bug intermittently.
- **AMD 9000-series** — These require a special driver cycling sequence before
  `vfio-pci` can claim them. See the
  [amd_9000_StartStop.sh script](example-scripts.md#1-amd_9000_startstopsh)
  for details.
- **Mitigation**: The `amd_9000_StartStop.sh` script includes a workaround for
  the AMD GPU driver cycle. For other AMD cards, a host reboot between VM
  sessions is the most reliable approach.

### Checking Reset Capability

To see which reset methods your GPU supports:

```bash
cat /sys/bus/pci/devices/0000:26:00.0/reset_method
```text

Possible values: `flr` (function-level reset), `bus`, `pm` (power management),
`none`.

---

## 7. Verification Inside the Guest

Once the guest OS is running, confirm the GPU is accessible.

### Linux Guest

```bash
lspci -nn | grep -i vga
```text

If the GPU appears in the list, the passthrough is working at the PCI level.

Check the driver in use inside the guest:

```bash
lspci -nnk | grep -A3 VGA
```text

Install the vendor's driver (NVIDIA or AMD) inside the guest for full GPU
acceleration.

### Windows Guest

1. Open **Device Manager** (`devmgmt.msc`).
2. Look under **Display adapters** — the GPU should appear. It may show a
   warning icon (yellow triangle) if the driver is not installed or if the
   device encountered an error.
3. Install the vendor's Windows driver (NVIDIA GeForce Game Ready or AMD
   Adrenalin).
4. After installation, the GPU should show as working with no errors.

### Stress Test

Run a GPU benchmark or compute workload inside the guest to confirm the GPU can
sustain load:

- Linux: `glmark2`, `glxgears`, or `nvidia-smi` (NVIDIA only)
- Windows: `dxdiag`, FurMark, or a game benchmark

If the GPU works under load without crashing or resetting, passthrough is
functioning correctly.

---

## 8. Common Failure Patterns

### NVIDIA Error 43

**Symptom**: Windows Device Manager shows the GPU with error code 43 ("Windows
has stopped this device because it has reported problems").

**Causes**:

- The GPU detected that it is running inside a VM and disabled itself.
- Missing or corrupted VBIOS.
- The GPU was not properly reset between VM sessions.

**Fixes**:

1. **Hide KVM signature** — QEMU can mask the hypervisor signature from the
   guest. DKVM Manager applies `-cpu hv_vpindex,hv_reset,...` flags for Windows
   guests. Verify the VM configuration includes:

   ```xml
   <kvm>
     <hidden state='on'/>
   </kvm>
   ```

   Or check that `kvm_hidden=on` appears in the QEMU command line.

1. **Provide a valid VBIOS** — See [VBIOS ROM Considerations](#4-vbios-rom-considerations).
   A dumped or vendor-provided VBIOS often resolves error 43 on NVIDIA GPUs.

1. **Reboot the host** — If the GPU was previously used by the host or by
   another VM without a clean reset, a full power cycle may be needed.

### AMD Reset Bug

**Symptom**: After stopping the VM, any attempt to start it again (or any other
VM using the same GPU) fails. QEMU output shows:

```text
Failed to assign device
```text

Or the host kernel logs show:

```text
[ 1234.567] vfio-pci 0000:26:00.0: Failed to reset device
```text

**Cause**: The GPU did not reset properly after the VM stopped. Common on AMD
RX 400/500 and early RDNA cards.

**Fixes**:

- **Host reboot** — The only fully reliable workaround.
- **Driver cycling** — For AMD 9000-series, use the
  [amd_9000_StartStop.sh](example-scripts.md#1-amd_9000_startstopsh) script
  which DKVM Manager integrates.
- **Power cycle** — A full power-off (not just reboot) may be required for
  some cards. Unplug the PSU for 30 seconds.

### GPU Not Visible in Guest at All

**Symptom**: The guest OS does not list the GPU in `lspci` or Device Manager.

**Causes**:

- The GPU is not in the VM's PCI device list — check the VM configuration
  in DKVM Manager.
- The GPU is still bound to the host driver — verify `Kernel driver in use:
  vfio-pci` on the host (see [Step 3.5](#35-verify-vfio-pci-binding)).
- The GPU is in the host's IOMMU group but the group was not fully
  passed through. All devices in the group must be passed to the guest.
- OVMF firmware is missing or incompatible — see
  [Troubleshooting](troubleshooting.md#vm-wont-boot).

### VM Crashes on Start / Host Freezes

**Symptom**: Starting the VM causes QEMU to crash, or the host becomes
unresponsive.

**Causes**:

- The GPU is the host's primary display output and the host loses its console
  when QEMU takes the device. See [Primary vs Secondary GPU](#5-primary-vs-secondary-gpu).
- ACS override is not sufficient for the platform — try a different PCIe slot.
- The GPU shares an IOMMU group with a device critical to the host (e.g., NVMe
  SSD, USB controller). Pass all devices in the group or do not pass through.

### QEMU Shows "Failed to assign device"

**Symptom**: QEMU error on VM start:

```text
vfio: Cannot enable device: Invalid argument
Failed to assign device "0000:26:00.0"
```text

**Causes**:

- The device is not bound to `vfio-pci` — verify with `lspci -nnk`.
- Another process (e.g., display server on the host) still holds the device.
- The IOMMU group is not isolated and contains devices not passed through.
- The host kernel does not have VFIO support — check `lsmod | grep vfio`.

**Fixes**:

1. Confirm `vfio-pci` binds the device (see [Step 3.5](#35-verify-vfio-pci-binding)).
2. Check IOMMU groups and ensure all devices in the group are passed through
   (see [Non-Isolated Groups](#non-isolated-iommu-groups)).
3. Verify kernel modules are loaded:

   ```bash
   lsmod | grep vfio
   ```

   Expected: `vfio_pci`, `vfio_pci_core`, `vfio_virqfd`, `vfio_iommu_type1`,
   `vfio`.

---

## 9. Reference

| Step                         | Document                                                           |
| ---------------------------- | ------------------------------------------------------------------ |
| First-time DKVM setup        | [First-Boot Walkthrough](first-boot.md)                            |
| PCI passthrough in TUI       | [First-Boot Walkthrough §4.2](first-boot.md#42-pci-passthrough)    |
| AMD 9000-series driver cycle | [Example Scripts](example-scripts.md#1-amd_9000_startstopsh)       |
| Common problems              | [Troubleshooting](troubleshooting.md)                              |
| Architecture & boot flow     | [Architecture Reference](../contributor/architecture-reference.md) |
| DKVM terminology             | [CONTEXT](../../CONTEXT.md)                                        |
