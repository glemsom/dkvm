#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ FILE:       amd_9000_StartStop.sh
# ║
# ║ USAGE:      Start/stop script for AMD 9000 series GPU passthrough
# ║
# ║ COMPATIBLE: DKVM menu system
# ║
# ║ FEATURES:   • Dynamic driver detection and unbinding
# ║             • Device-specific amdgpu driver loading/unloading for VGA devices
# ║             • VFIO-PCI binding for passthrough devices
# ║             • iGPU protection setup
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Get the current driver for a PCI device
# ║ USAGE:       get_current_driver "0000:01:00.0"
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
get_current_driver() {
	local device=$1
	# shellcheck disable=SC2155  # Declare and assign separately - readability preferred for simple sysfs reads
	if [ -L /sys/bus/pci/devices/0000:${device}/driver ]; then
		basename "$(readlink /sys/bus/pci/devices/0000:${device}/driver)"
	else
		echo ""
	fi
}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Check if device is a VGA device
# ║ USAGE:       is_vga_device "0000:01:00.0"
# ║ RETURNS:     0 if VGA device, 1 otherwise
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
is_vga_device() {
	local device=$1
	# shellcheck disable=SC2155  # Declare and assign separately - readability preferred for simple sysfs reads
	local class=$(cat /sys/bus/pci/devices/0000:${device}/class 2>/dev/null)
	# VGA compatible controller: 0x0300xx
	# 3D controller: 0x0302xx
	[[ "$class" == 0x03* ]]
}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Unbind driver from device
# ║ USAGE:       unbind_driver "0000:01:00.0" "amdgpu"
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
unbind_driver() {
	local device=$1
	local driver=$2

	if [ -n "$driver" ] && [ -e "/sys/bus/pci/drivers/${driver}/unbind" ]; then
		echo "Unbinding driver '$driver' from 0000:${device}"
		echo "0000:${device}" >"/sys/bus/pci/drivers/${driver}/unbind" 2>/dev/null
	fi
}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Bind driver to device
# ║ USAGE:       bind_driver "0000:01:00.0" "vfio-pci"
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
bind_driver() {
	local device=$1
	local driver=$2

	if [ -e "/sys/bus/pci/drivers/${driver}/bind" ]; then
		echo "Binding driver '$driver' to 0000:${device}"
		echo "0000:${device}" >"/sys/bus/pci/drivers/${driver}/bind" 2>/dev/null
	fi
}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Start VM - bind passthrough devices to vfio-pci
# ║              Handles AMDGPU driver cycle for VGA devices
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
customVMStart() {
	echo "Starting custom AMD 9000 series passthrough script"

	# shellcheck disable=SC2154  # configPassthroughPCIDevices is provided by DKVM menu system
	devices=$(cat "/media/dkvmdata/passthroughPCIDevices")

	# Detect VGA device from passthrough devices
	VGA_DEVICE=""
	for device in $devices; do
		if is_vga_device "$device"; then
			VGA_DEVICE="$device"
			echo "Detected VGA device: 0000:${VGA_DEVICE}"
			break # Use first VGA device found
		fi
	done

	# Protect iGPU from amdgpu driver (before loading the module)
	for pci_device in /sys/bus/pci/devices/0000:*; do
		device=$(basename "$pci_device" | cut -d: -f2-)
		class=$(cat "${pci_device}/class" 2>/dev/null)

		# Check if it's a VGA device (class 0x03*)
		if [[ "$class" == 0x03* ]]; then
			# Check if it's NOT in the passthrough list
			if ! echo "$devices" | grep -q "$device"; then
				echo "Protecting iGPU 0000:${device} from amdgpu driver"
				echo "fake_driver" >"${pci_device}/driver_override"
			fi
		fi
	done

	# Load amdgpu module if VGA device detected (required before binding)
	if [ -n "$VGA_DEVICE" ]; then
		echo "Loading amdgpu kernel module"
		modprobe amdgpu
		sleep 1 # Let module initialize
	fi

	# Step 1: Unbind all passthrough devices from their current drivers
	for device in $devices; do
		current_driver=$(get_current_driver "$device")

		if [ -n "$current_driver" ]; then
			unbind_driver "$device" "$current_driver"
		fi

		# Clean up any existing VFIO IDs
		# shellcheck disable=SC2155  # Declare and assign separately - readability preferred for simple sysfs reads
		local pciVendor=$(cat "/sys/bus/pci/devices/0000:${device}/vendor" 2>/dev/null)
		local pciDevice=$(cat "/sys/bus/pci/devices/0000:${device}/device" 2>/dev/null)
		if [ -n "$pciVendor" ] && [ -n "$pciDevice" ]; then
			echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null
		fi
	done

	# Step 2: Special handling for VGA device (AMD 9000 series requires driver cycle)
	if [ -n "$VGA_DEVICE" ]; then
		echo "Performing AMDGPU driver cycle for VGA device 0000:${VGA_DEVICE}"

		# Bind amdgpu driver specifically to this device
		echo "Loading amdgpu driver on 0000:${VGA_DEVICE}"
		bind_driver "$VGA_DEVICE" "amdgpu"
		sleep 2 # Let the card initialize

		# Unbind amdgpu driver from the device
		echo "Unloading amdgpu driver from 0000:${VGA_DEVICE}"
		unbind_driver "$VGA_DEVICE" "amdgpu"
	fi

	sleep 2 # Let devices settle after configuration

	# Step 3: Bind all passthrough devices to vfio-pci
	for device in $devices; do
		# shellcheck disable=SC2155  # Declare and assign separately - readability preferred for simple sysfs reads
		local pciVendor=$(cat "/sys/bus/pci/devices/0000:${device}/vendor" 2>/dev/null)
		local pciDevice=$(cat "/sys/bus/pci/devices/0000:${device}/device" 2>/dev/null)

		if [ -n "$pciVendor" ] && [ -n "$pciDevice" ]; then
			echo "Binding vfio-pci to ${pciVendor}:${pciDevice} (0000:${device})"
			echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null
			sleep 2 # Let device settle
		fi
	done

	echo "Custom AMD 9000 series passthrough script completed"
}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ DESCRIPTION: Stop VM - unbind passthrough devices from vfio-pci
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
customVMStop() {
	echo "Starting custom AMD 9000 series stop script"

	# shellcheck disable=SC2154  # configPassthroughPCIDevices is provided by DKVM menu system
	devices=$(cat "$configPassthroughPCIDevices")

	# Unbind all devices from vfio-pci
	for device in $devices; do
		if [ -e "/sys/bus/pci/devices/0000:${device}/driver/unbind" ]; then
			echo "Unbinding vfio-pci from 0000:${device}"
			echo "0000:${device}" >"/sys/bus/pci/devices/0000:${device}/driver/unbind" 2>/dev/null
		fi

		# Remove VFIO IDs
		# shellcheck disable=SC2155  # Declare and assign separately - readability preferred for simple sysfs reads
		local pciVendor=$(cat "/sys/bus/pci/devices/0000:${device}/vendor" 2>/dev/null)
		local pciDevice=$(cat "/sys/bus/pci/devices/0000:${device}/device" 2>/dev/null)
		if [ -n "$pciVendor" ] && [ -n "$pciDevice" ]; then
			echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null
		fi
	done

	echo "Custom AMD 9000 series stop script completed"
}
