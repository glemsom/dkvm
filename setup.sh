#!/bin/bash
version=0.4.0
disksize=1024 #Disk size in MB
alpineVersion=3.17
alpineVersionMinor=2
alpineISO=alpine-standard-${alpineVersion}.${alpineVersionMinor}-x86_64.iso
ovmf_code=OVMF_CODE.fd
ovmf_vars=OVMF_VARS.fd
# qemu binary, might differ on other distrobutions
qemu=/usr/bin/qemu-system-x86_64

diskfile="usbdisk.img"

err() {
	echo "Error occured $@"
	exit 1
}

# Check dependencies
deps="expect mkisofs dd xorriso zip $qemu"

for dep in $deps; do
	which $dep || err "Missing $dep"
done

if [ ! -f "$alpineISO" ]; then
	echo "Downloading Alpine Linux ISO"
	wget http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/releases/x86_64/${alpineISO} -O ${alpineISO} || err "Cannot download ISO"
fi
if [ ! -f "$ovmf_code" ]; then
	# Try to find OVMF_CODE
	tmpPaths="/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd /usr/share/ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd"
	for tmpPath in $tmpPaths; do
		[ -f $tmpPath ] && cp "$tmpPath" $ovmf_code && foundCode=yes
	done
	# We did not find it
	[ ! $foundCode ] && err "Cannot find $ovmf_code. Please place it in the root folder"
fi

if [ ! -f "$ovmf_vars" ]; then
	# Try to find OVMF_VARS
	tmpPaths="/usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd"
	for tmpPath in $tmpPaths; do
		[ -f $tmpPath ] && cp "$tmpPath" $ovmf_vars && foundVars=yes
	done
	# We did not find it
	[ ! $foundVars ] && err "Cannot find $ovmf_vars. Please place it in the root folder"
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


echo "Patching stock Alpine ISO"
# Patch ISO to support console output
mkdir tmp_iso
mkdir tmp_iso_readonly
sudo mount -t iso9660 -o loop $alpineISO tmp_iso_readonly || err "Cannot mount Alpine ISO"
cd tmp_iso_readonly && tar cf - . | (cd ../tmp_iso; tar xfp -) || err "Cannot copy Alpine ISO content"
cd ../tmp_iso
chmod +xw boot/grub/ || err "Cannot modify permissions for grub"
chmod +w boot/syslinux/isolinux.bin || err "Cannot modify permissions for isolinux.bin"
sed -i 's/quiet/console=ttyS0,9600 quiet/' boot/grub/grub.cfg || err "Cannot patch grub.cfg"
cd .. && xorriso -as mkisofs -o ${alpineISO}.patched -isohybrid-mbr tmp_iso/boot/syslinux/isohdpfx.bin -c boot/syslinux/boot.cat  -b boot/syslinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img  -no-emul-boot -isohybrid-gpt-basdat  tmp_iso || err "Cannot build custom ISO"

echo "Starting stage01..."

sudo expect -c "set timeout -1
spawn $qemu -m 1G -machine q35 \
-drive if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on \
-drive if=pflash,format=raw,unit=1,file=$ovmf_vars \
-drive if=none,format=raw,id=usbstick,file=$diskfile \
-usb -device usb-storage,drive=usbstick \
-drive format=raw,media=cdrom,readonly,file=${alpineISO}.patched \
-drive format=raw,media=cdrom,readonly,file=stage01.iso \
-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
-device e1000,netdev=mynet0 \
-nographic \
-boot menu=on,splash-time=12000 \
-global ICH9-LPC.disable_s3=0 \
-global driver=cfi.pflash01,property=secure,value=off
expect \"login: \"
send \"root\n\"
expect \"localhost:~# \"
send whoami\n
send \"mkdir /media/sr1\n\"
send \"mount /dev/sr1 /media/sr1\n\"
send \"sh /media/sr1/runme.sh /dev/sda\n\"
send \"echo ALL DONE\n\"
expect \"ALL DONE\"
" || err "Error in stage01"

clear

echo "Starting stage02..."

sudo expect -c "set timeout -1
set log_user 1
spawn $qemu -m 1G -machine q35 \
-drive if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on \
-drive if=pflash,format=raw,unit=1,file=$ovmf_vars \
-global driver=cfi.pflash01,property=secure,value=off \
-drive if=none,format=raw,id=usbstick,file=$diskfile \
-usb -device usb-storage,drive=usbstick \
-drive format=raw,media=cdrom,readonly,file=stage02.iso \
-netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
-device e1000,netdev=mynet0 \
-nographic \
-boot menu=on,splash-time=12000 \
-global ICH9-LPC.disable_s3=0 \
-global driver=cfi.pflash01,property=secure,value=off
expect \"login: \"
send root\n
expect \"localhost:~# \"
send \"mount /media/cdrom\n\"
send \"/media/cdrom/runme.sh\n\"
expect \"Enter system hostname\"
send dkvm\n
expect \"Which one do you want to initialize\"
send br0\n
expect \"do you want add to bridge br0?\"
send eth0\n
expect \"Ip address for\"
send dhcp\n
expect \"Do you want to do any manual network configuration\"
send n\n
expect \"New password: \"
send dkvm4ever!\n
expect \"Retype password: \"
send dkvm4ever!\n
expect \"Which timezone are you in\"
send Europe/Copenhagen\n
expect \"HTTP/FTP proxy URL\"
send none\n
expect \"Which NTP client to run\"
sleep 2
send busybox\n\n
sleep 2
send \n\n
sleep 2
expect -- More
sleep 1
send \" \n\n\"
sleep 2
send \" \n\n\"
expect \"Enter mirror number\"
send 1\n
expect \"Setup a user\"
send no\n
expect \"Which ssh server? \"
send openssh\n
expect \"Allow root ssh login\"
send yes\n
expect \"Enter ssh key or URL for root\"
send none\n
expect \"Which disk(s) would you like to use?\"
send none\n
expect \"Enter where to store configs \"
send usb\n
expect \"Enter apk cache directory \"
send /media/usb/cache\n
expect \"Exiting stage02\"
" || err "Error in stage02"

#clear

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
	cd stage03
	zip -r release_${version}.zip release_${version} || err "Unable to create release zip file"
	cd ..
else
	#wget https://srv-file8.gofile.io/download/WbufzP/release_${version}.zip -O stage03/release_${version}
	mkdir stage03/release_${version}
	unzip stage03/release_${version}.zip -d stage03
fi

loopDevice=$(sudo losetup --show -f -P "$diskfile" 2>&1)
mkdir tmp_dkvm
sudo mount -o loop ${loopDevice}p1 tmp_dkvm || err "Cannot mount ${loopDevice}p1"

sudo mkdir tmp_dkvm/custom

# Inject new kernel
sudo cp stage03/release_${version}/dkvm_kernel/*dkvm tmp_dkvm/boot/ || err "Cannot inject DKVM kernel"

# Write version
echo $version | sudo tee tmp_dkvm/dkvm-release

# Cleanup mount
sudo umount tmp_dkvm
sudo umount ${loopDevice}p1
sudo losetup -D
sudo rm -rf stage03/kernel_files
sudo rm -rf stage03/dkvm_files
sudo rm -rf tmp_dkvm
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

sudo $qemu -m 1G -machine q35 \
		-drive if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on \
		-drive if=pflash,format=raw,unit=1,file=$ovmf_vars \
		-global driver=cfi.pflash01,property=secure,value=off \
        -drive if=none,format=raw,id=usbstick,file="$diskfile" \
        -usb -device usb-storage,drive=usbstick \
        -netdev user,id=mynet0,net=10.200.200.0/24,dhcpstart=10.200.200.10 \
        -device e1000,netdev=mynet0 \
		-boot menu=on,splash-time=12000 \
		-global ICH9-LPC.disable_s3=0 \
		-global driver=cfi.pflash01,property=secure,value=off || err "Cannot start qemu"

# Cleanup
sudo rm -rf stage03/release*
sudo rm -rf stage03/sbin
sudo rm -rf stage03/dl-cdn*
sudo rm -rf tmp_iso
sudo umount tmp_iso_readonly
