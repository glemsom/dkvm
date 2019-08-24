#!/bin/sh

if [ -z "$1" ]; then
	echo "Please use $0 INSTALL_DISK."
	echo "For example $0 /dev/sda"
	exit 1
else
	if [ -e $1 ]; then
		installDisk="$1"
	else
		echo "Error, $1 does not exist"
		exit 1
	fi
fi

# Create partition-table


echo "
n
p
1


t
c
p
a
1
w
" | fdisk "$installDisk"

clear

echo "Choose none for disks to use, and store configs"

setup-alpine -e -f /media/sr1/answer.txt

modprobe vfat
echo "Formatting usb disk"
mkdosfs ${installDisk}1
mkfs.vfat -n dkvm ${installDisk}1

echo "Making usb disk bootable"
setup-bootable /media/cdrom ${installDisk}1

echo "System will now poweroff, and restart with stage02 iso"
sleep 2

poweroff
