# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ FILE:  Makefile
# ║ AUTHOR: Glenn Sommer <glemsom+dkvm AT gmail.com>
# ║
# ║ DESCRIPTION: Build system for DKVM (Desktop KVM) - a minimal hypervisor that
# ║              runs entirely from RAM with GPU passthrough support
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ CONFIGURATION
# ║ DKVM release version
# ║ Disk image size in megabytes
# ║ Alpine Linux major and minor versions
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
VERSION ?= v0.6.3
DISK_SIZE ?= 2048
ALPINE_VERSION ?= 3.23
ALPINE_MINOR ?= 2

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DERIVED VARIABLES
# ║ Alpine ISO filename, UEFI firmware files, output disk image filename
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
ALPINE_ISO := alpine-standard-$(ALPINE_VERSION).$(ALPINE_MINOR)-x86_64.iso
OVMF_CODE := OVMF_CODE.fd
OVMF_VARS := OVMF_VARS.fd
DISK_FILE := dkvm-$(VERSION).img
QEMU := /usr/bin/qemu-system-x86_64

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DEPENDENCIES
# ║ Required tools that must be installed on the build system
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
DEPS := wget expect mkisofs dd xorriso zip $(QEMU) losetup mount sudo

.PHONY: all build verify-deps cleanup run help

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DEFAULT TARGET
# ║ Build the DKVM disk image when no target is specified
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
all: build

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: help
# ║ Display usage information and available build targets
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
help:
	@echo "DKVM Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  verify-deps  - Check that all required dependencies are installed"
	@echo "  build        - Build the DKVM disk image"
	@echo "  run          - Run the built image in QEMU"
	@echo "  cleanup      - Remove all generated files and clean up"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Configuration variables (can be set via environment or make args):"
	@echo "  VERSION=$(VERSION)"
	@echo "  DISK_SIZE=$(DISK_SIZE)"
	@echo "  ALPINE_VERSION=$(ALPINE_VERSION)"
	@echo "  ALPINE_MINOR=$(ALPINE_MINOR)"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: verify-deps
# ║ Check that all required build dependencies are installed and available
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
verify-deps:
	@echo "Checking dependencies..."
	@for dep in $(DEPS); do \
		if ! command -v "$$dep" >/dev/null 2>&1; then \
			echo "Error: Missing dependency: $$dep"; \
			exit 1; \
		fi; \
	done
	@echo "All dependencies found."

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: $(ALPINE_ISO)
# ║ Download Alpine Linux ISO from official mirror if not already present
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
$(ALPINE_ISO):
	@echo "Downloading Alpine Linux ISO..."
	wget "http://dl-cdn.alpinelinux.org/alpine/v$(ALPINE_VERSION)/releases/x86_64/$(ALPINE_ISO)" -O "$(ALPINE_ISO)"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: $(OVMF_CODE)
# ║ Locate and copy UEFI firmware code from common system locations
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
$(OVMF_CODE):
	@echo "Looking for OVMF_CODE.fd..."
	@for path in /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd /usr/share/ovmf/x64/OVMF_CODE.fd /usr/share/ovmf/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/ovmf/OVMF.fd; do \
		if [ -f "$$path" ]; then \
			echo "Found at $$path"; \
			cp "$$path" "$(OVMF_CODE)"; \
			exit 0; \
		fi; \
	done; \
	echo "Error: Cannot find $(OVMF_CODE). Please copy it to $(OVMF_CODE)"; \
	exit 1

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: $(OVMF_VARS)
# ║ Locate and copy UEFI firmware variables template from system
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
$(OVMF_VARS):
	@echo "Looking for OVMF_VARS.fd..."
	@for path in /usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/ovmf/x64/OVMF_VARS.fd /usr/share/ovmf/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS_4M.fd; do \
		if [ -f "$$path" ]; then \
			echo "Found at $$path"; \
			cp "$$path" "$(OVMF_VARS)"; \
			exit 0; \
		fi; \
	done; \
	echo "Error: Cannot find $(OVMF_VARS). Please copy it to $(OVMF_VARS)"; \
	exit 1

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: scripts.iso
# ║ Create ISO image containing DKVM setup scripts for automated installation
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
scripts.iso: scripts/runme.sh scripts/dkvmmenu.sh scripts/answer.txt
	@echo "Creating scripts ISO..."
	mkisofs -o scripts.iso scripts

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: alpine_extract/vmlinuz-lts
# ║ Extract the Linux kernel (LTS version) from Alpine ISO for DKVM boot
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
alpine_extract/vmlinuz-lts: $(ALPINE_ISO)
	@echo "Extracting kernel from Alpine ISO..."
	@mkdir -p alpine_extract
	xorriso -osirrox on -indev "$(ALPINE_ISO)" -extract /boot/vmlinuz-lts alpine_extract/vmlinuz-lts 2>/dev/null

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: alpine_extract/initramfs-lts
# ║ Extract the initramfs image from Alpine ISO for DKVM boot
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
alpine_extract/initramfs-lts: $(ALPINE_ISO)
	@echo "Extracting initramfs from Alpine ISO..."
	@mkdir -p alpine_extract
	xorriso -osirrox on -indev "$(ALPINE_ISO)" -extract /boot/initramfs-lts alpine_extract/initramfs-lts 2>/dev/null

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: build
# ║ Main build target - creates bootable DKVM disk image with all components
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
build: verify-deps $(OVMF_CODE) $(OVMF_VARS) scripts.iso alpine_extract/vmlinuz-lts alpine_extract/initramfs-lts
	@echo "Creating disk image $(DISK_FILE) @ $(DISK_SIZE)MB..."
	@rm -f "$(DISK_FILE)"
	dd if=/dev/zero of="$(DISK_FILE)" bs=1M count=$(DISK_SIZE)
	@echo "Starting installation..."
	@sudo expect install.expect "$(QEMU)" "$(OVMF_CODE)" "$(OVMF_VARS)" "$(DISK_FILE)" "$(ALPINE_ISO)" "scripts.iso" || (echo "Error during installation"; exit 1)
	@echo "Writing version to disk..."
	@loopDevice=$$(sudo losetup --show -f -P "$(DISK_FILE)"); \
	mkdir -p tmp_dkvm; \
	sudo mount -o loop "$${loopDevice}p1" tmp_dkvm || (echo "Cannot mount $${loopDevice}p1"; exit 1); \
	echo "$(VERSION)" | sudo tee tmp_dkvm/dkvm-release > /dev/null; \
	while mount | grep "$${loopDevice}p1" -q; do \
		echo "$${loopDevice}p1 still mounted - trying to cleanup"; \
		mountPoint=$$(mount | grep "$${loopDevice}p1" | awk '{print $$3}'); \
		sudo umount "$${loopDevice}p1" 2>/dev/null || true; \
		sudo umount "$$mountPoint" 2>/dev/null || true; \
		sudo losetup -D; \
		sleep 1; \
	done; \
	echo "$${loopDevice}p1 unmounted"; \
	sudo rm -rf tmp_dkvm
	@echo "BUILD COMPLETED: $(DISK_FILE) is ready."
	@echo "To run the image: make run VERSION=$(VERSION)"
	@	rm -rf alpine_extract scripts.iso

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: run
# ║ Launch the built DKVM image in QEMU for testing
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
run: $(DISK_FILE) $(OVMF_CODE) $(OVMF_VARS)
	@echo "Running DKVM image $(DISK_FILE)..."
	@sudo $(QEMU) -m 4G -machine q35 \
	-drive if=pflash,format=raw,unit=0,file=$(OVMF_CODE),readonly=on \
	-drive if=pflash,format=raw,unit=1,file=$(OVMF_VARS) \
	-drive if=none,format=raw,id=usbstick,file=$(DISK_FILE) \
	-usb -device usb-storage,drive=usbstick \
	-netdev user,id=mynet0,hostfwd=tcp::2222-:22 \
	-device e1000,netdev=mynet0

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ TARGET: cleanup
# ║ Remove all generated files, disk images, and temporary directories
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
cleanup:
	@echo "Starting cleanup..."
	@echo "Unmounting temporary directories..."
	@for dir in tmp_dkvm alpine_extract; do \
		if mountpoint -q "$$dir" 2>/dev/null; then \
			echo "Unmounting $$dir..."; \
			sudo umount "$$dir" 2>/dev/null || sudo umount -l "$$dir" 2>/dev/null || true; \
		fi; \
	done
	@echo "Detaching loop devices..."
	@for file in $(DISK_FILE) $(ALPINE_ISO); do \
		if [ -f "$$file" ]; then \
			loopdevs=$$(sudo losetup -j "$$file" 2>/dev/null | awk -F: '{print $$1}'); \
			for dev in $$loopdevs; do \
				if [ -n "$$dev" ]; then \
					sudo grep "$$dev" /proc/mounts 2>/dev/null | awk '{print $$2}' | while read -r mount_pt; do \
						sudo umount "$$mount_pt" 2>/dev/null || true; \
					done; \
					sudo losetup -d "$$dev" 2>/dev/null || true; \
				fi; \
			done; \
		fi; \
	done
	@echo "Removing temporary directories..."
	@sudo rm -rf tmp_dkvm alpine_extract
	@echo "Removing intermediate files..."
	@rm -f scripts.iso $(OVMF_CODE) $(OVMF_VARS)
	@echo "Removing disk images..."
	@rm -f dkvm-*.img
	@echo "Removing Alpine ISO..."
	@rm -f $(ALPINE_ISO)
	@echo "Cleanup complete."
