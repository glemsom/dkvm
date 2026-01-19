# Changelog

All notable changes to DKVM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Automatic extraction of version-specific release notes from `CHANGELOG.md` during GitHub Actions builds.

### Changed
- Renamed `setup.sh` to `build.sh` for better clarity of its purpose.
- Refined and cleaned up comments and steps in `scripts/runme.sh`.
- Updated documentation with clearer first-boot instructions and storage configuration details.
- Standardized tag trigger pattern in GitHub Actions to match `vX.Y.Z` or `vX.Y.Z-dev` format.
- Improved `cleanup.sh` to be more robust when cleaning up loop devices and temporary files.
- Optimized GitHub Release assets to include a single versioned ZIP file containing both the disk image and README.

## [v0.6.1] - 2026-01-18

### Added
- GitHub Actions workflow for automated builds on tag push
- Automatic GitHub Release creation with versioned disk images
- Versioned disk image output (dkvm-<version>.img format)
- Support for pre-release tags (e.g., v0.6.1-dev)
- CHANGELOG.md to track project changes

### Changed
- Unified build path by removing interactive QEMU step at end of setup.sh
- Build script now prints recommended QEMU command for manual verification
- Improved OVMF path discovery to support Ubuntu Noble (24.04 LTS)
- Version format now uses "v" prefix (e.g., v0.6.1 instead of 0.6.1)
- VERSION environment variable can override default version in setup.sh

### Fixed
- OVMF firmware file detection in GitHub Actions CI environment
- Package name for QEMU in Ubuntu (qemu-system-x86 vs qemu-system-x86_64)

## [v0.5.14] - 2026-01-17

### Initial Release
- Basic DKVM setup script for creating bootable USB images
- Alpine Linux based system with QEMU/KVM support
- VFIO passthrough configuration
- GRUB bootloader with custom kernel parameters
