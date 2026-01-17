#!/bin/bash
# DKVM Setup
# Glenn Sommer <glemsom+dkvm AT gmail.com>
version=0.5.14
disksize=2048  #Disk size in MB
alpineVersion=3.23
alpineVersionMinor=2
alpineISO=alpine-standard-${alpineVersion}.${alpineVersionMinor}-x86_64.iso
ovmf_code=OVMF_CODE.fd
ovmf_vars=OVMF_VARS.fd
# qemu binary, might differ on other distrobutions
qemu=/usr/bin/qemu-system-x86_64

diskfile="usbdisk.img"

err() {
	echo "Error occured $*"
	exit 1
}

# Check dependencies
deps="wget expect mkisofs dd xorriso zip $qemu"

for dep in $deps; do
	command -v "$dep" >/dev/null 2>&1 || err "Missing dependency:$dep"
done

if [ ! -f "$alpineISO" ]; then
	echo "Downloading Alpine Linux ISO"
	wget "http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/releases/x86_64/${alpineISO}" -O "${alpineISO}" || err "Cannot download ISO"
fi
if [ ! -f "$ovmf_code" ]; then
	# Try to find OVMF_CODE
	tmpPaths="/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd /usr/share/ovmf/x64/OVMF_CODE.fd /usr/share/ovmf/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd"
	for tmpPath in $tmpPaths; do
		[ -f "$tmpPath" ] && cp "$tmpPath" "$ovmf_code" && foundCode=yes
	done
	# We did not find it
	[ ! "$foundCode" ] && err "Cannot find $ovmf_code. Please copy it to $ovmf_code"
fi

if [ ! -f "$ovmf_vars" ]; then
	# Try to find OVMF_VARS
	tmpPaths="/usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/ovmf/x64/OVMF_VARS.fd /usr/share/ovmf/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd"
	for tmpPath in $tmpPaths; do
		[ -f "$tmpPath" ] && cp "$tmpPath" "$ovmf_vars" && foundVars=yes
	done
	# We did not find it
	[ ! "$foundVars" ] && err "Cannot find $ovmf_vars. Please copy it to $ovmf_vars"
fi

clear

# Creating disk
echo "Creating new disk in $diskfile @ ${disksize}MB"
dd if=/dev/zero of="$diskfile" bs=1M count="$disksize" || err "Cannot make $diskfile"

# Re-create scripts ISO
echo "Recreate scripts iso"
mkisofs -o scripts.iso scripts || err "Cannot make scripts iso"

echo "Extracting kernel and initramfs from Alpine ISO"
mkdir -p alpine_extract
xorriso -osirrox on -indev "$alpineISO" -extract /boot/vmlinuz-lts alpine_extract/vmlinuz-lts 2>/dev/null || err "Cannot extract vmlinuz-lts"
xorriso -osirrox on -indev "$alpineISO" -extract /boot/initramfs-lts alpine_extract/initramfs-lts 2>/dev/null || err "Cannot extract initramfs-lts"


echo "Starting installation..."

sudo expect -c "set timeout -1
spawn $qemu -smp 4 -m 16G -machine q35  \
-drive if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on \
-drive if=pflash,format=raw,unit=1,file=$ovmf_vars \
-drive if=none,format=raw,id=usbstick,file="$diskfile" \
-usb -device usb-storage,drive=usbstick \
-kernel alpine_extract/vmlinuz-lts \
-initrd alpine_extract/initramfs-lts \
-append \"console=ttyS0,9600 modules=loop,squashfs modloop=/dev/sr0:/boot/modloop-lts quiet\" \
-drive format=raw,media=cdrom,readonly,file=${alpineISO} \
-drive format=raw,media=cdrom,readonly,file=scripts.iso \
-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
-device e1000,netdev=mynet0 \
-nographic \
-boot menu=on,splash-time=12000 \
-global ICH9-LPC.disable_s3=0 \
-global driver=cfi.pflash01,property=secure,value=off
expect \"login: \"
send \"root\n\"
expect \"localhost:~# \"
send \"mkdir -p /media/cdrom\n\"
send \"mount /dev/sr1 /media/cdrom\n\"
send \"sh /media/cdrom/runme.sh /dev/sda\n\"
send \"echo INSTALLATION DONE\n\"
expect \"INSTALLATION DONE\"
" || err "Error during installation"

#clear
#cp usbdisk.img usbdisk.img-save-stage02

loopDevice=$(sudo losetup --show -f -P "$diskfile" 2>&1)
mkdir tmp_dkvm
sudo mount -o loop "${loopDevice}p1" tmp_dkvm || err "Cannot mount ${loopDevice}p1"

ls -l tmp_dkvm
# Write version
echo -n "Version: "
echo $version | sudo tee tmp_dkvm/dkvm-release

# Cleanup mount
while mount | grep "${loopDevice}p1" -q; do
	echo "${loopDevice}p1 still mounted - trying to cleanup"
	mountPoint=$(mount | grep "${loopDevice}p1" | awk '{print $3}')
	sudo umount "${loopDevice}p1"
	sudo umount "$mountPoint"
	sudo losetup -D
	sleep 5
done
echo "${loopDevice}p1" unmounted
sudo rm -rf tmp_dkvm

echo "VM started, use vnc to check console or ssh on port 2222 (You need to set passwd)"
sudo "$qemu" -m 16G -machine q35 \
	-smp cpus=4,sockets=1,dies=1 \
	-drive if=pflash,format=raw,unit=0,file="$ovmf_code",readonly=on \
	-drive if=pflash,format=raw,unit=1,file="$ovmf_vars" \
	-global driver=cfi.pflash01,property=secure,value=off \
	-drive if=none,format=raw,id=usbstick,file="$diskfile" \
	-usb -device usb-storage,drive=usbstick \
	-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10,hostfwd=tcp::2222-:22  \
	-device e1000,netdev=mynet0 \
	-boot menu=on,splash-time=4000 \
	-global ICH9-LPC.disable_s3=0 -vnc 0.0.0.0:0 || err "Cannot start qemu"

# Cleanup
sleep 1
rm -rf alpine_extract
rm -f scripts.iso
