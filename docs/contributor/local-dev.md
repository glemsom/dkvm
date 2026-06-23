# Local Development

This guide covers the day-to-day development workflow for iterating on DKVM
changes. It assumes you have read the [architecture document](architecture.md)
for build pipeline context.

> **Terminology**: See [CONTEXT.md](../../CONTEXT.md) for definitions of
> "DKVMDATA", "Guest", "Host", "lbu", and other project terms.

---

## Standard Build Loop

### Verify dependencies

Before starting, ensure your build environment has all required tools:

```bash
make verify-deps
```

Missing packages on Debian/Ubuntu:

```bash
sudo apt install wget expect xorriso zip qemu-system-x86 ovmf mtools
```

### Full build

The complete build downloads the Alpine ISO, extracts kernel/initramfs, boots a
temporary QEMU VM, and runs the installation scripts. This takes several
minutes:

```bash
make build
```

Output: `dkvm-<version>.img` — a bootable FAT32 disk image.

### Smoke-test in QEMU

Boot the built image locally to verify it works:

```bash
make run
```

This launches QEMU with 8 GB RAM, UEFI, and user-mode networking (SSH
forwarded to `localhost:2222`).

---

## Quick script-only iteration

When you only change `scripts/runme.sh` or `scripts/answer.txt`, you can skip
the ISO download, kernel extraction, and OVMF discovery phases. Rebuild only
the scripts ISO and re-run `install.expect`:

```bash
make scripts.iso && sudo expect install.expect \
  /usr/bin/qemu-system-x86_64 \
  OVMF_CODE.fd OVMF_VARS.fd \
  dkvm-<version>.img \
  alpine-standard-<ver>.iso \
  scripts.iso
```

> **Note:** This requires a completed `make build` first — the kernel,
> initramfs, OVMF files, and disk image from that run are reused.

---

## Inspecting a built image

Mount the `.img` file via loop device to inspect its contents:

```bash
sudo losetup --show -f -P dkvm-<version>.img
# → /dev/loop0
sudo mount /dev/loop0p1 /mnt
# Inspect contents: kernel, initramfs, scripts, dkvm-release
sudo umount /mnt
sudo losetup -d /dev/loop0
```

Check that the following are present:
- `vmlinuz-lts` — Alpine LTS kernel
- `initramfs-lts` — initramfs
- `scripts/` — DKVM setup scripts
- `dkvm-release` — version info file

---

## Cleanup

Remove all generated files (disk images, ISOs, temporary directories):

```bash
make cleanup
```

If loop devices remain attached (e.g., after a failed build), clean them up
manually:

```bash
# List attached loop devices
sudo losetup -a

# Detach a specific device
sudo losetup -d /dev/loop0

# Detach all loop devices
sudo losetup -D
```

## Build Troubleshooting

### `make build` fails with "Error during installation"

This usually means `install.expect` failed to complete the QEMU-based
installation. Common causes:

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| QEMU window appears briefly then disappears | Missing OVMF firmware | Run `make verify-deps` and check OVMF files exist |
| `expect: spawn id ... not open` | QEMU failed to start | Check `qemu-system-x86_64` is installed and working |
| Alpine ISO not found | Download interrupted | Remove `alpine-standard-*.iso` and re-run `make build` |
| Script hangs at "Starting installation..." | `install.expect` timeout | The build VM may need more time; try running `install.expect` manually |

### Loop devices not cleaned up after failed build

If `make build` is interrupted, loop devices may remain attached:

```bash
# List attached loop devices
sudo losetup -a

# Detach all loop devices
sudo losetup -D
```

### Permission errors

`make build` requires `sudo` for loop device and mount operations. Ensure your
user has `sudo` access and the `sudo` session has not expired.

### Slow build

The full build downloads an Alpine ISO (~200 MB), extracts kernel/initramfs, and
boots a QEMU VM to run the installation scripts. Expect 5–15 minutes depending
on network speed and host performance. For faster iteration on script-only
changes, use the [quick script-only iteration](#quick-script-only-iteration)
workflow.
---

## Reference

- [Architecture Document](architecture.md) — full build pipeline, boot sequence,
  persistence model, component map
- [CONTRIBUTING.md](CONTRIBUTING.md) — PR process, coding standards, changelog
  policy

---

*Last updated: 2026-06-23*
