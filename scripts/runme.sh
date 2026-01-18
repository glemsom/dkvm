#!/bin/sh

err() {
	echo "ERROR" "$@"
	/bin/sh
}

if [ -z "$1" ]; then
	echo "Please use $0 INSTALL_DISK."
	echo "For example $0 /dev/sda"
	exit 1
else
	if [ -e "$1" ]; then
		installDisk="$1"
	else
		echo "Error, $1 does not exist"
		exit 1
	fi
fi

# 1. Partition disk
echo "Creating partition-table"
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

# 2. Format disk
modprobe vfat
echo "Formatting usb disk"
mkfs.vfat -n dkvm "${installDisk}1"

# 3. Mount disk
mkdir -p /media/usb
mount "${installDisk}1" /media/usb || err "Cannot mount ${installDisk}1 to /media/usb"

# 4. Setup Alpine
# We use the answer file provided in the scripts ISO (cdrom)
setup-alpine -e -f /media/cdrom/answer.txt

# 5. Make disk bootable
echo "Making usb disk bootable"
# /media/sr0 is the Alpine ISO
setup-bootable /media/sr0 "${installDisk}1"

# 6. DKVM specific: Setup APK cache on USB
echo "Creating persistent apk cache"
mkdir -p /media/usb/cache || err "Cannot create cache folder"
# Check if symlink exists, if not create it
if [ ! -L /etc/apk/cache ]; then
	ln -s /media/usb/cache /etc/apk/cache || err "Cannot create apk cache symink"
fi


# 7. DKVM specific: Packages
echo "Enable extra repositories"
sed -i '/^#.*v3.*community/s/^#/@community /' /etc/apk/repositories
# Add new repository file with edge and testing enabled

apk update
apk upgrade
apk add ca-certificates wget util-linux bridge bridge-utils amd-ucode intel-ucode qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community qemu-hw-display-virtio-vga@community swtpm@community bash dialog bc nettle jq vim lvm2 lvm2-dmeventd e2fsprogs pciutils irqbalance hwloc-tools || err "Cannot install packages"

# 8. DKVM specific: GRUB and Kernel args
extraArgs="mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5 blacklist=amdgpu split_lock_detect=off"
[ -e /media/usb/boot/grub/grub.cfg.old ] && rm -f /media/usb/boot/grub/grub.cfg.old
cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/\(modules=[^ ]*\)/\1,vfio-pci/' | sed 's#initrd.*/boot/initramfs-lts#initrd /boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts#' > /media/usb/boot/grub/grub.cfg || err "Cannot patch grub"

# Copy microcode
cp /boot/amd-ucode.img /media/usb/boot/ || echo "amd-ucode.img not found"
cp /boot/intel-ucode.img /media/usb/boot/ || echo "intel-ucode.img not found"

# Update to latest LTS kernel in repository
update-kernel /media/usb/boot/

# 9. DKVM specific: Network and Services
rc-update add mdadm-raid
rc-update add lvm default
rc-update add local default
rc-update add ntpd default

# SSH setup
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

# QEMU bridge helper
echo "allow br0" > /etc/qemu/bridge.conf
echo "set bell-style none" >> /etc/inputrc

# Kernel modules
echo "
kvm_intel
kvm_amd
vfio_iommu_type1
tun
vfio-pci
vfio" >> /etc/modules

# VFIO config
echo "options kvm-intel nested=1 enable_apicv=1
options kvm-amd nested=1 avic=1
options kvm ignore_msrs=1
blacklist snd_hda_intel
blacklist amdgpu
" > /etc/modprobe.d/vfio.conf

# Local script for data folder
echo '#!/bin/sh
# Add DKVM Data folder (Mounted from fstab)
mkdir /media/dkvmdata
mount -a
' >> /etc/local.d/dkvm_folder.start
chmod +x /etc/local.d/dkvm_folder.start

# 10. Install dkvmmenu.sh
cp /media/cdrom/dkvmmenu.sh /root/dkvmmenu.sh
chmod +x /root/dkvmmenu.sh
lbu include /root

# TTY1 respawn
cp /etc/inittab /etc/inittab.bak
cat /etc/inittab.bak | sed 's#tty1::.*#tty1::respawn:/root/dkvmmenu.sh#' > /etc/inittab

# 11. Finalizing
setup-apkcache /media/usb/cache
setup-lbu usb

# Update fstab
cat > /etc/fstab <<EOF
/dev/cdrom	/media/cdrom	iso9660	noauto,ro 0 0
LABEL=dkvm     /media/usb    vfat   noauto,ro 0 0
LABEL=dkvmdata /media/dkvmdata  ext4 defaults,discard,nofail 0 0
EOF

# ACPI and LVM discards
sed 's/# issue_discards.*/issue_discards = 1/' -i /etc/lvm/lvm.conf
printf 'echo -e \x27{ "execute": "qmp_capabilities" }\\n{ "execute": "system_powerdown" }\x27 | timeout 5 nc localhost 4444' > /etc/acpi/PWRF/00000080

# Cleanup apk cache
rm -rf /media/usb/cache/linux-*
for c in $(seq 1 10); do dd if=/dev/zero of=/media/usb/cache/linux-zero-fill bs=1M count=1024; done
rm -f /media/usb/cache/linux-zero-fill


apk cache -v sync
lbu commit -d -v

sync
sleep 2
echo "INSTALLATION COMPLETED"
poweroff
