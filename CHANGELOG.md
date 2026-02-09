# Changelog

All notable changes to DKVM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.7.0] - 2026-02-09

### Added
- New Makefile-based build system for simplified project management.
- `install.expect` script for automated installation processes.

### Changed
- Migrated build process from `build.sh` and `cleanup.sh` to Makefile targets (`make build`, `make clean`).
- Updated build instructions in README.md to reflect the new Makefile workflow.

### Removed
- Deprecated `build.sh` and `cleanup.sh` scripts (functionality now in Makefile).

## [v0.6.3] - 2026-01-24

### Added
- Example start/stop script for AMD 9000 series CPUs with advanced CPU pinning and NUMA configuration.

### Changed
- Improved documentation in `verify_pinning.sh` to clarify SSH passwordless authentication requirement.

## [v0.6.2] - 2026-01-19

### Added
- Feature to set and persist the root SSH password directly from the DKVM configuration menu.
- Documentation for the `DKVMDATA` filesystem label requirement to enable automatic storage mounting at `/media/dkvmdata`.
- Automatic extraction of version-specific release notes from `CHANGELOG.md` during GitHub Actions builds.

### Changed
- Renamed `setup.sh` to `build.sh` for better clarity.
- Refined build process instructions in README.md by removing manual configuration of `setup.sh`.
- Improved `cleanup.sh` robustness for loop devices and temporary file handling.
- Optimized GitHub Release assets to include a single versioned ZIP file.
- Standardized tag trigger patterns in CI for `vX.Y.Z` consistency.

### Fixed
- Improved glob expansion handling in `cleanup.sh`.

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
