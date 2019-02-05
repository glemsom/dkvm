#!/bin/bash
disksize=512 #Disk size in MB
diskfile="usbdisk.img"
iso="alpine-standard-3.9.0-x86_64.iso"
bios=OVMF.fd
err() {
	echo "Error occured $@"
	exit 1
}

if [ ! -f "$iso" ]; then
	echo "Downloading Alpine Linux ISO"
	wget http://dl-cdn.alpinelinux.org/alpine/v3.9/releases/x86_64/${iso} || err "Cannot download iso"
fi

if [ ! -f "$bios" ]; then
	cp /usr/share/ovmf/OVMF.fd OVMF.fd || err "Cannot find OVMF.fd. Place this in the root folder"
fi

clear

# Creating disk
echo "Creating new disk in $diskfile @ ${disksize}MB"
dd if=/dev/zero of=$diskfile bs=1M count=$disksize || err "Cannot make $diskfile"

# Re-create scripts ISO
echo "Recreate stage01 and stage02 iso"
mkisofs -o stage01.iso stage01 || err "Cannot make stage01 iso"
mkisofs -o stage02.iso stage02 || err "Cannot make stage02 iso"


clear

echo "Starting qemu..."

echo '
* Login as root (no password)
* mkdir /media/sr1 && mount /dev/sr1 /media/sr1 && sh /media/sr1/runme.sh /dev/sda)
'

sudo qemu-system-x86_64 -m 1G -machine q35  \
	-drive if=none,format=raw,id=usbstick,file="$diskfile" \
	-usb -device usb-storage,drive=usbstick \
	-drive format=raw,media=cdrom,readonly,file="$iso" \
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

# Stage03 : Build custom DKVM kernel
sudo stage03/runme.sh

loopDevice=$(sudo losetup --show -f -P "$diskfile" 2>&1)
mkdir tmp_dkvm
sudo mount -o loop ${loopDevice}p1 tmp_dkvm

sudo mkdir tmp_dkvm/custom

# Inject new kernel
sudo cp stage03/kernel_files/dkvm_kernel/*vanilla tmp_dkvm/boot/

# Inject custom OVMF package
#sudo cp stage03/dkvm_files/*apk tmp_dkvm/root/
sudo cp stage03/dkvm_files/*apk tmp_dkvm/custom/

# Copy chrt from host OS
if [ ! -z "`which chrt`" ]; then
	sudo cp `which chrt` tmp_dkvm/custom/
fi



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

