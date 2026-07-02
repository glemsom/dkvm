# DKVM
<!-- markdownlint-disable MD013 -->

Desktop KVM - an Alpine Linux based operating system that boots from USB and provides a minimal hypervisor environment with GPU/PCI passthrough capabilities.

## Language

**DKVM**:
The Alpine-based operating system product that boots from a USB drive and runs entirely in RAM.
_Avoid_: Project, repo (those are the DKVM project / DKVM repo, not the OS itself)

**DKVM Manager**:
The Go TUI binary (`dkvmmanager`) that runs on tty1 and provides the configuration interface for CPU pinning, PCI/USB passthrough, VM creation, and system settings.
_Avoid_: Menu, TUI (it's the specific binary)

**DKVM Live**:
The running state of the DKVM operating system after boot. Everything runs from RAM; persistent data lives on the `DKVMDATA` partition.
_Avoid_: DKVM environment, booted system

**DKVMDATA**:
The label of the ext4 data partition that stores VM disk images, ISOs, TPM state, and VM configurations. Auto-mounted at `/media/dkvmdata`.
_Avoid_: Data partition, storage partition (always use the label)

**Host**:
The physical machine running DKVM (the USB-booted OS that hosts QEMU guests).
_Avoid_: Bare metal, physical host

**Guest**:
A virtual machine running under QEMU/KVM within DKVM.
_Avoid_: VM, virtual machine (interchangeable, but Guest is canonical)

**QEMU**:
The hypervisor used to run guest VMs. DKVM uses a custom build from
`glemsom/dkvm-qemu` with DKVM-specific patches.
_Avoid_: Emulator, virtualizer

**KVM**:
Kernel-based Virtual Machine — the Linux kernel module that accelerates QEMU
guest execution using hardware virtualization extensions (Intel VT-x / AMD SVM).
_Avoid_: (acronym, always expand on first use)

**OVMF**:
TianoCore UEFI firmware used to boot guests. DKVM copies OVMF_CODE.fd and
OVMF_VARS.fd from the host system during build.
_Avoid_: BIOS, firmware (OVMF is the specific implementation)

**IOMMU**:
I/O Memory Management Unit — hardware that maps device DMA addresses to system
memory. Required for PCI passthrough. Enabled via `intel_iommu=on` or
`amd_iommu=on` kernel parameters.
_Avoid_: IOMMU (always uppercase)

**VFIO**:
Virtual Function I/O — kernel framework for userspace device access. The
`vfio-pci` driver binds passthrough devices so QEMU can own them exclusively.
_Avoid_: vfio (always uppercase)

**lbu**:
Alpine Linux utility (`lbu commit`) that persists the running system overlay to
the USB stick. DKVM Manager runs `lbu commit` automatically on configuration
changes.
_Avoid_: Backup utility, save command (use lbu)

**swtpm**:
Software TPM daemon that provides a Trusted Platform Module to guest VMs.
Launched and managed by DKVM Manager per-VM.
_Avoid_: TPM emulator (use swtpm)

**QMP**:
QEMU Machine Protocol — a JSON-based management interface available on
localhost:4444 when a guest is running. Used for power management and
diagnostics.
_Avoid_: QEMU monitor (use QMP)

**br0**:
The default Linux bridge on the DKVM host, bound to the physical Ethernet
interface. Guest VMs attached to br0 receive LAN IPs via DHCP.
_Avoid_: Network bridge (use br0)
