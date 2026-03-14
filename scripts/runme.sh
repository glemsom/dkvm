#!/bin/sh
# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ FILE:  runme.sh
# ║
# ║ USAGE: runme.sh INSTALL_DISK
# ║
# ║ DKVM installation script for setting up Alpine Linux with
# ║ KVM virtualization support, GPU passthrough, and VFIO.
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ NAME: err
# ║ Display error message and spawn recovery shell
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
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

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Create bootable partition on target disk
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
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

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Format the newly created partition as FAT32
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
modprobe vfat
echo "Formatting usb disk"
mkfs.vfat -n dkvm "${installDisk}1"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Mount the USB disk for installation
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
mkdir -p /media/usb
mount "${installDisk}1" /media/usb || err "Cannot mount ${installDisk}1 to /media/usb"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Run Alpine Linux setup using answer file from ISO
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
setup-alpine -e -f /media/cdrom/answer.txt

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Make the USB disk bootable using Alpine ISO
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
setup-bootable /media/sr0 "${installDisk}1"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Setup persistent APK cache on USB for offline package management
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo "Creating persistent apk cache"
mkdir -p /media/usb/cache || err "Cannot create cache folder"
if [ ! -L /etc/apk/cache ]; then
	ln -s /media/usb/cache /etc/apk/cache || err "Cannot create apk cache symink"
fi

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Enable community repositories and install DKVM required packages
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo "Enable extra repositories"
sed -i '/^#.*v3.*community/s/^#/@community /' /etc/apk/repositories

apk update
apk upgrade
apk add ca-certificates wget util-linux bridge bridge-utils amd-ucode intel-ucode qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community qemu-hw-display-virtio-vga@community swtpm@community bash dialog bc nettle jq vim lvm2 lvm2-dmeventd e2fsprogs pciutils irqbalance hwloc-tools || err "Cannot install packages"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure GRUB with IOMMU and VFIO kernel parameters for DKVM
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
extraArgs="mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5 blacklist=amdgpu split_lock_detect=off"
[ -e /media/usb/boot/grub/grub.cfg.old ] && rm -f /media/usb/boot/grub/grub.cfg.old
cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/\(modules=[^ ]*\)/\1,vfio-pci/' | sed 's#initrd.*/boot/initramfs-lts#initrd /boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts#' >/media/usb/boot/grub/grub.cfg || err "Cannot patch grub"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Copy CPU microcode updates to boot partition
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
cp /boot/amd-ucode.img /media/usb/boot/ || echo "amd-ucode.img not found"
cp /boot/intel-ucode.img /media/usb/boot/ || echo "intel-ucode.img not found"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Update to latest LTS kernel in repository
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
update-kernel /media/usb/boot/

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure system services and network for DKVM
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
rc-update add lvm default
rc-update add local default
rc-update add ntpd default

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Enable root SSH login
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure QEMU bridge helper permissions
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo "allow br0" >/etc/qemu/bridge.conf
echo "set bell-style none" >>/etc/inputrc

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Load KVM and VFIO kernel modules for virtualization
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo "
kvm_intel
kvm_amd
vfio_iommu_type1
tun
vfio-pci
vfio" >>/etc/modules

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure VFIO and KVM module parameters
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo "options kvm-intel nested=1 enable_apicv=1
options kvm-amd nested=1 avic=1
options kvm ignore_msrs=1
blacklist snd_hda_intel
blacklist amdgpu
" >/etc/modprobe.d/vfio.conf

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Create local script to mount DKVM data folder from fstab
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
echo '#!/bin/sh
# Mount DKVM data folder from fstab
mkdir /media/dkvmdata
mount -a
' >>/etc/local.d/dkvm_folder.start
chmod +x /etc/local.d/dkvm_folder.start

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Install DKVM menu script to root home directory
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
cp /media/cdrom/dkvmmenu.sh /root/dkvmmenu.sh
chmod +x /root/dkvmmenu.sh
lbu include /root

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure TTY1 to auto-respawn dkvmmenu.sh on login
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
cp /etc/inittab /etc/inittab.bak
cat /etc/inittab.bak | sed 's#tty1::.*#tty1::respawn:/root/dkvmmenu.sh#' >/etc/inittab

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Finalize installation with APK cache and local backup
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
setup-apkcache /media/usb/cache
setup-lbu usb

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Update fstab with DKVM mount points
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
cat >/etc/fstab <<EOF
/dev/cdrom	/media/cdrom	iso9660	noauto,ro 0 0
LABEL=dkvm     /media/usb    vfat   noauto,ro 0 0
LABEL=dkvmdata /media/dkvmdata  ext4 defaults,discard,nofail 0 0
EOF

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Configure LVM discards and ACPI power button handling
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
sed 's/# issue_discards.*/issue_discards = 1/' -i /etc/lvm/lvm.conf
printf 'echo -e \x27{ "execute": "qmp_capabilities" }\\n{ "execute": "system_powerdown" }\x27 | timeout 5 nc localhost 4444' >/etc/acpi/PWRF/00000080

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Clean up APK cache and zero-fill free space
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
rm -rf /media/usb/cache/linux-*
for c in $(seq 1 10); do dd if=/dev/zero of=/media/usb/cache/linux-zero-fill bs=1M count=1024; done
rm -f /media/usb/cache/linux-zero-fill

apk cache -v sync
lbu commit -d -v

sync
sleep 2
echo "INSTALLATION COMPLETED"
poweroff
