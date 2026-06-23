---
name: Bug report
about: Report a problem to help improve DKVM
title: ""
labels: bug
assignees: ""
---

## Describe the Bug

A clear and concise description of what the bug is.

## To Reproduce

Steps to reproduce the behavior:
1. Boot DKVM '...'
2. Select '...' from the menu
3. See error

## Expected Behavior

A clear description of what you expected to happen.

## Environment

- **DKVM version** (from `/media/dkvm-release` or the filename): e.g., v0.7.39
- **Host hardware**: CPU, GPU, motherboard model
- **USB stick**: brand, size, write method (dd, balenaEtcher, etc.)

## Logs & Diagnostics

```
# Run these on the DKVM host and paste the output:
cat /proc/cmdline
dmesg | grep -i vfio
dmesg | grep -i iommu
lsblk -f
mount | grep dkvmdata
```

## Additional Context

Add any other context about the problem here (screenshots, config files, etc.).
