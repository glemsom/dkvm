# DKVM

Desktop KVM — an Alpine Linux based operating system that boots from USB and provides a minimal hypervisor environment with GPU/PCI passthrough capabilities.

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
