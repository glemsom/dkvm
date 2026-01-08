#!/bin/bash

# cleanup.sh - Cleans up leftovers from an interrupted setup.sh run

# Variables used in setup.sh that we need to track
diskfile="usbdisk.img"
# We match the pattern for alpine iso to be version-agnostic
alpineISO_pattern="alpine-standard-*-x86_64.iso"
alpineISO=$(ls $alpineISO_pattern 2>/dev/null | head -n 1)

echo "Starting cleanup..."

# 1. Unmount temporary directories
# setup.sh mounts: tmp_iso_readonly, tmp_dkvm
DIRS="tmp_dkvm tmp_iso_readonly"

for dir in $DIRS; do
    if mountpoint -q "$dir"; then
        echo "Unmounting $dir..."
        sudo umount "$dir"
        if [ $? -ne 0 ]; then
             echo "Error: Could not unmount $dir. Force unmounting..."
             sudo umount -l "$dir"
        fi
    fi
done

# 2. Detach loop devices
echo "Checking for loop devices..."

cleanup_loop_device() {
    local target_file="$1"

    if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
        return
    fi

    # excessive grep to ensure we catch it
    local loopdevs=$(sudo losetup -j "$target_file" | awk -F: '{print $1}')

    for dev in $loopdevs; do
        if [ -n "$dev" ]; then
            echo "Found loop device $dev for $target_file"

            # Check if any partitions of this loop device are still mounted
            # This handles cases where ${loopDevice}p1 is mounted but not at our expected dir
             grep "$dev" /proc/mounts | awk '{print $2}' | while read -r mountpoint; do
                echo "Unmounting $mountpoint..."
                sudo umount "$mountpoint"
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


# 3. Remove temporary directories
# setup.sh creates: tmp_iso, tmp_iso_readonly, tmp_dkvm
TEMP_DIRS="tmp_dkvm tmp_iso tmp_iso_readonly"

for dir in $TEMP_DIRS; do
    if [ -d "$dir" ]; then
        echo "Removing directory $dir..."
        # Safety check: ensure we aren't deleting something important if variable is empty
        if [ -n "$dir" ]; then
            sudo rm -rf "$dir"
        fi
    fi
done

# 4. Remove intermediate files (leftovers)
# setup.sh creates: stage01.iso, stage02.iso, ${alpineISO}.patched, usbdisk.img, OVMF files
echo "Removing intermediate build files..."
rm -f stage01.iso stage02.iso "$diskfile" OVMF_CODE.fd OVMF_VARS.fd

if [ -n "$alpineISO" ]; then
    rm -f "$alpineISO"
    patched_iso="${alpineISO}.patched"
    if [ -f "$patched_iso" ]; then
         rm -f "$patched_iso"
         echo "Removed $patched_iso"
    fi
fi

echo "Cleanup complete."
