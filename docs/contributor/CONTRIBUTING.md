# Contributing to DKVM

First off, thank you for considering contributing to DKVM.

## Table of Contents

- [Environment Setup](#environment-setup)
- [Build Workflow](#build-workflow)
- [PR Process](#pr-process)
- [Coding Standards](#coding-standards)
- [DKVM Manager Dependency](#dkvm-manager-dependency)
- [Changelog Policy](#changelog-policy)

**Documentation changes**: If your PR includes documentation changes, also
update the relevant document(s) under `docs/`. See the
[Documentation section](#documentation-changes) for details.

## Testing Guidelines

Before submitting a PR, run the following checks:

### Shell scripts

Run ShellCheck on all shell scripts:

```bash
shellcheck scripts/*.sh examples/*.sh
```

### Documentation

If you changed documentation, verify rendering with markdownlint:

```bash
make lint-docs
```

### Build verification

For changes that affect the build system or scripts:

1. Run a full build: `make build`
2. Smoke-test the resulting image: `make run`
3. Verify the image boots and DKVM Manager starts (see
   [First-Boot Walkthrough](../user/first-boot.md))

### Functional testing

For changes to scripts or runtime behaviour:

- Test with at least one Linux guest and one Windows guest (if applicable)
- Verify PCI/USB passthrough works with your test hardware
- Check that `lbu commit` persists changes across a reboot

> **Note**: Some tests require physical hardware (GPU, USB devices) and cannot
> be automated. Document the hardware you tested with in the PR description.

## Documentation Changes

Pull requests that add, modify, or remove functionality **must** include
corresponding documentation updates in `docs/`. This includes:

- New features: add a how-to guide or reference entry
- Changed behaviour: update existing documents to match
- Removed features: mark as deprecated or remove references

Documentation follows the
[Diátaxis framework](https://diataxis.fr/):

| Type | Audience | Location |
|------|----------|----------|
| Tutorials | New users starting out | `docs/user/` |
| How-to Guides | Users solving specific problems | `docs/user/` |
| Reference | Developers and advanced users | `docs/contributor/` |
| Explanation | Users seeking deeper understanding | `docs/contributor/` and `CONTEXT.md` |

See `.markdownlint.yaml` for the project's Markdown style rules.

### Last-Updated Dates

Every documentation file in `docs/` must include a last-updated footer at the
end of the file:

```markdown
---

*Last updated: YYYY-MM-DD*
```

When your PR modifies a documentation file, update the date in its footer to
the current date. This helps readers assess how current the information is.

---

## Environment Setup

### Required Packages

Before building DKVM, verify your build environment has all required
dependencies:

```bash
make verify-deps
```

This checks for: `wget`, `expect`, `mkisofs`, `dd`, `xorriso`, `zip`,
`qemu-system-x86_64`, `losetup`, `mount`, `sudo`, and `tar`.

On Debian/Ubuntu systems:

```bash
sudo apt install wget expect xorriso zip qemu-system-x86 ovmf mtools
```

### Go Toolchain

If you plan to modify DKVM Manager (separate repo:
[glemsom/dkvmmanager](https://github.com/glemsom/dkvmmanager)), install
Go 1.21+.

DKVM itself does not require Go — the Makefile downloads a pre-built
DKVM Manager binary.

### Git Workflow

1.  Fork the repository on GitHub.
2.  Clone your fork locally:
    ```bash
    git clone git@github.com:<your-username>/dkvm.git
    cd dkvm
    ```
3.  Add the upstream remote:
    ```bash
    git remote add upstream git@github.com:glemsom/dkvm.git
    ```

---

## Build Workflow

DKVM uses a Makefile-based build system.

### Standard Build

```bash
make build
```

This will:

1.  Check all dependencies (`make verify-deps`).
2.  Find and copy OVMF firmware files (if needed).
3.  Download the Alpine Linux ISO (if not present).
4.  Extract kernel and initramfs from the ISO.
5.  Boot a temporary QEMU VM and run `scripts/runme.sh` via `expect`
    (`install.expect`) to automate installation.
6.  Generate `dkvm-<version>.img`.

### Smoke-Testing

Run the built image in QEMU:

```bash
make run
```

This boots the image with 8 GB RAM, UEFI, and user-mode networking
(SSH forwarded to `localhost:2222`).

---

## PR Process

1.  **Branch from `main`**: create a feature branch:
    ```bash
    git checkout -b my-feature main
    ```
2.  **Make changes** following the [coding standards](#coding-standards)
    below.
3.  **Update `CHANGELOG.md`** under `## [Unreleased]` (see
    [Changelog Policy](#changelog-policy)).
4.  **Commit your changes** with a descriptive message:
    ```bash
    git commit -m "area: brief description of change"
    ```
5.  **Push to your fork**:
    ```bash
    git push origin my-feature
    ```
6.  **Open a Pull Request** against the `main` branch of
    `glemsom/dkvm`.
7.  Address review feedback, if any.
8.  A maintainer merges the PR after approval.

---

## Coding Standards

### Shell Scripts

- Use `#!/bin/sh` shebang (Alpine uses BusyBox ash).
- Use the `err()` function for error handling (defined in
  `scripts/runme.sh`):
  ```sh
  err() {
      echo "ERROR" "$@"
      /bin/sh
  }
  ```
- Run `shellcheck` manually before submitting:
  ```bash
  shellcheck scripts/*.sh
  ```
  ShellCheck is not enforced in CI — it is a manual quality check.
- Use the box-comment style for file headers (see existing files for
  reference):

```
# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ FILE:  example.sh
# ║
# ║ USAGE: example.sh [options]
# ║
# ║ DESCRIPTION: What this script does.
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
```

### Markdown

- Use ATX headings (`#`, `##`, `###`).
- Maintain a consistent heading hierarchy (no skipped levels).
- Line-wrap prose at **80 characters**.
- Use fenced code blocks with language tags.

---

## DKVM Manager Dependency

DKVM Manager is a separate Go binary hosted at
[glemsom/dkvmmanager](https://github.com/glemsom/dkvmmanager).

The Makefile pins a specific release tag:

```makefile
DKVM_MANAGER_VERSION ?= v0.2.0
```

To update:

1.  Check the latest release tag on the
    [dkvmmanager releases page](https://github.com/glemsom/dkvmmanager/releases).
2.  Update `DKVM_MANAGER_VERSION` in the Makefile.
3.  Add a `CHANGELOG.md` entry under `## [Unreleased]`:
    ```
    ### Changed
    - Updated DKVM Manager to v0.2.0.
    ```

---

## Changelog Policy

Every meaningful change to the repository MUST have a corresponding
entry in `CHANGELOG.md` under the `## [Unreleased]` section.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Change Categories

- **Added** — new features
- **Changed** — changes to existing functionality
- **Deprecated** — soon-to-be removed features
- **Removed** — now removed features
- **Fixed** — bug fixes
- **Security** — vulnerability fixes

### Example

```markdown
## [Unreleased]

### Added
- New feature description.

### Changed
- Updated DKVM Manager to v0.1.30.
```

If `## [Unreleased]` does not exist yet, create it at the top of the
file, above the most recent release entry.

---

*Last updated: 2026-06-23*
