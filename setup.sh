#!/bin/bash
version=0.2.5
disksize=512 #Disk size in MB
alpineVersion=3.10
alpineVersionMinor=2
alpineISO=alpine-standard-${alpineVersion}.${alpineVersionMinor}-x86_64.iso
bios=OVMF.fd

diskfile="usbdisk.img"

err() {
	echo "Error occured $@"
	exit 1
}

if [ ! -f "$alpineISO" ]; then
	echo "Downloading Alpine Linux ISO"
	wget http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/releases/x86_64/${alpineISO} -O ${alpineISO} || err "Cannot download ISO"
fi

if [ ! -f "$bios" ]; then
	if [ -f /usr/share/ovmf/OVMF.fd ]; then
		cp /usr/share/ovmf/OVMF.fd $bios || err "Cannot find OVMF.fd. Place this in the root folder"
	elif [ -f /usr/share/ovmf/x64/OVMF_CODE.fd ]; then
		cp /usr/share/ovmf/x64/OVMF_CODE.fd $bios || err "Cannot find OVMF_CODE.fd. Place this in the root folder, and rename it to $bios"
	else
		err "Unable to find OVMF.fd. Please place this in the root folder"
	fi
fi

clear

# Creating disk
echo "Creating new disk in $diskfile @ ${disksize}MB"
dd if=/dev/zero of=$diskfile bs=1M count=$disksize || err "Cannot make $diskfile"

# Re-create scripts ISO
echo "Recreate stage01 and stage02 iso"
mkisofs -o stage01.iso stage01 || err "Cannot make stage01 iso"
mkisofs -o stage02.iso stage02 || err "Cannot make stage02 iso"

sudo rm -rf stage03/release*
sudo rm -rf stage03/sbin

clear

echo "Starting qemu..."

echo '
* Login as root (no password)
* mkdir /media/sr1 && mount /dev/sr1 /media/sr1 && sh /media/sr1/runme.sh /dev/sda)
'

sudo qemu-system-x86_64 -m 1G -machine q35  \
	-drive if=none,format=raw,id=usbstick,file="$diskfile" \
	-usb -device usb-storage,drive=usbstick \
	-drive format=raw,media=cdrom,readonly,file="$alpineISO" \
	-drive format=raw,media=cdrom,readonly,file=stage01.iso \
	-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
	-device e1000,netdev=mynet0 \
	-bios "$bios" || err "Cannot start qemu"

clear

echo '
* Login as root (no password)
* mount /media/cdrom && /media/cdrom/runme.sh
* Network: br0 (use first adapter as member of the bridge-adapter)
* Disks to use: none
* Config: usb (should be autoselected)
* apk cache: /media/usb/cache
'
sudo qemu-system-x86_64 -m 1G -machine q35 \
        -drive if=none,format=raw,id=usbstick,file="$diskfile" \
        -usb -device usb-storage,drive=usbstick \
	-drive format=raw,media=cdrom,readonly,file=stage02.iso \
	-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
	-device e1000,netdev=mynet0 \
	-bios "$bios" || err "Cannot start qemu"

clear

if [ "$1" = "rebuild" ]; then
	# Stage03 : Build custom DKVM kernel
	sudo stage03/runme.sh
	mkdir stage03/release_${version}

	sudo cp -r stage03/kernel_files/dkvm_kernel stage03/release_${version}
	sudo cp -r stage03/dkvm_files/ stage03/release_${version}

	# Copy chrt from host OS
	if [ ! -z "`which chrt`" ]; then
		sudo cp `which chrt` stage03/release_${version}
	else
		err "Cannot find chrt. Please install this in your OS"
	fi

else
	echo "fetch from github"
	exit 1
	#TODO populate stage03 with files
fi

loopDevice=$(sudo losetup --show -f -P "$diskfile" 2>&1)
mkdir tmp_dkvm
sudo mount -o loop ${loopDevice}p1 tmp_dkvm

sudo mkdir tmp_dkvm/custom

# Inject new kernel
sudo cp stage03/kernel_files/dkvm_kernel/*vanilla tmp_dkvm/boot/

# Inject custom OVMF package
sudo cp stage03/dkvm_files/*apk tmp_dkvm/custom/

# Copy chrt from host OS
if [ ! -z "`which chrt`" ]; then
	sudo cp `which chrt` tmp_dkvm/custom/ || err "Cannot find chrt. Please install this in your OS"
fi

# Write version
echo $version > tmp_dkvm/dkvm-release


# Cleanup mount
sudo umount tmp_dkvm
sudo umount ${loopDevice}p1
sudo losetup -D
rm -rf stage03/kernel_files
rm -rf stage03/dkvm_files
rm -rf tmp_dkvm
sleep 5

while mount | grep ${loopDevice}p1 -q; do
	echo " ${loopDevice}p1 still mounted - trying to cleanup"
	mountPoint=$(mount | grep "${loopDevice}p1" | awk '{print $3}')
	sudo umount ${loopDevice}p1
	sudo umount "$mountPoint"
	sudo losetup -D
	sleep 5
done

echo '* Test boot - make sure you can login with root'

sudo qemu-system-x86_64 -m 1G -machine q35 \
        -drive if=none,format=raw,id=usbstick,file="$diskfile" \
        -usb -device usb-storage,drive=usbstick \
        -netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
        -device e1000,netdev=mynet0 \
        -bios "$bios" || err "Cannot start qemu"

