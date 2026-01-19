#!/bin/bash
# DKVM Cleanup
# Glenn Sommer <glemsom+dkvm AT gmail.com>

# cleanup.sh - Cleans up leftovers from an interrupted build.sh run

set -e          # Exit on error
set -u          # Treat unset variables as an error
set -o pipefail # Exit on pipe failure

# Variables used in build.sh that we need to track
diskfile="dkvm-*.img"
# We match the pattern for alpine iso to be version-agnostic
alpineISO_pattern="alpine-standard-*-x86_64.iso"

# Better way to find the Alpine ISO without ls
# shellcheck disable=SC2206
iso_files=($alpineISO_pattern)
alpineISO=""
if [ -e "${iso_files[0]}" ]; then
	alpineISO="${iso_files[0]}"
fi

echo "Starting cleanup..."

# Unmount temporary directories
DIRS=("tmp_dkvm")

for dir in "${DIRS[@]}"; do
	if mountpoint -q "$dir"; then
		echo "Unmounting $dir..."
		if ! sudo umount "$dir"; then
			echo "Error: Could not unmount $dir. Force unmounting..."
			sudo umount -l "$dir"
		fi
	fi
done

# Detach loop devices
echo "Checking for loop devices..."

cleanup_loop_device() {
	local target_file="$1"

	if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
		return
	fi

	local loopdevs
	# excessive grep to ensure we catch it
	loopdevs=$(sudo losetup -j "$target_file" | awk -F: '{print $1}')

	for dev in $loopdevs; do
		if [ -n "$dev" ]; then
			echo "Found loop device $dev for $target_file"

			# Check if any partitions of this loop device are still mounted
			# This handles cases where ${loopDevice}p1 is mounted but not at our expected dir
			sudo grep "$dev" /proc/mounts | awk '{print $2}' | while read -r mount_pt; do
				echo "Unmounting $mount_pt..."
				sudo umount "$mount_pt"
			done

			echo "Detaching $dev..."
			sudo losetup -d "$dev"
		fi
	done
}

# Cleanup loop devices for the main disk file
cleanup_loop_device "$diskfile"

# Cleanup loop devices for the Alpine ISO
if [ -n "$alpineISO" ]; then
	cleanup_loop_device "$alpineISO"
fi


# Remove temporary directories
TEMP_DIRS=("tmp_dkvm" "alpine_extract")

for dir in "${TEMP_DIRS[@]}"; do
	if [ -d "$dir" ]; then
		echo "Removing directory $dir..."
		# Safety check: ensure we aren't deleting something important if variable is empty
		if [ -n "$dir" ]; then
			sudo rm -rf "$dir"
		fi
	fi
done

# Remove intermediate files (leftovers)
echo "Removing intermediate build files..."
rm -f scripts.iso ${diskfile} OVMF_CODE.fd OVMF_VARS.fd

if [ -n "$alpineISO" ]; then
	rm -f "$alpineISO"
fi

echo "Cleanup complete."

