#!/bin/sh

err() {
	echo "ERROR $@"
	/bin/sh
}

# Check if /media/usb is mounted properly. If not, try to bind mount from sda1
# This handles cases where the USB drive is detected but not automatically mounted at the expected location
if ! mountpoint /media/usb; then
	echo "/media/usb not automounted - binding /dev/sda1"
	# Sometimes /dev/usbdisk is not correctly mounted under /media/usb
	# In our case, it will then be /dev/sda1
	mount --bind /media/sda1 /media/usb || err "Bind mount failed"
fi

# Setup a persistent APK cache on the USB drive to avoid redownloading packages
echo "Creating persistent apk cache"
mount -o remount,rw /media/usb || err "Cannot remount /media/usb as readwrite"
mkdir /media/usb/cache || err "Cannot create cache folder"

ln -s /media/usb/cache /etc/apk/cache

# Default arguments for Linux kernel
extraArgs="mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5 blacklist=amdgpu split_lock_detect=off"

# Updates GRUB config to include specific kernel arguments for virtualization (IOMMU, isolation, etc.)
[ -e /media/usb/boot/grub/grub.cfg.old ] && rm -f /media/usb/boot/grub/grub.cfg.old

cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/console=ttyS0,9600//g' | sed 's/\(modules=[^ ]*\)/\1,vfio-pci/' | sed 's#initrd.*/boot/initramfs-lts#initrd /boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts#' > /media/usb/boot/grub/grub.cfg || err "Cannot patch grub"

# Configure networking bridge (br0) for VM connectivity and run Alpine setup
brctl addbr br0
brctl addif br0 eth0

ip link set dev eth0 up

setup-alpine -e -f /media/cdrom/answer.txt

#/bin/bash
# Enable extra repositories (Edge, Community) for newer packages and QEMU/KVM tools
echo "Enable extra repositories"
sed -i '/^#.*v3.*community/s/^#/@community /' /etc/apk/repositories

# In case /dev/usbdisk was sda1, move it to usb
sed -i 's/sda1/usb/' /etc/apk/repositories

# Add new repository file with edge and testing enabled
#cp /etc/apk/repositories /etc/apk/repositories-edge
echo 'http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories-edge
#echo 'http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories-edge
echo 'http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories-edge

apk update
apk upgrade

# Install essential virtualization packages, tools, and firmware (QEMU, OVMF, SWTPM, etc.)
apk add ca-certificates wget util-linux bridge bridge-utils amd-ucode intel-ucode qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community qemu-hw-display-virtio-vga@community swtpm@community bash dialog bc nettle jq vim lvm2 lvm2-dmeventd e2fsprogs pciutils irqbalance hwloc-tools || err "Cannot install packages"

# Copy CPU microcode to USB boot directory
cp /boot/amd-ucode.img /media/usb/boot/ || echo "amd-ucode.img not found"
cp /boot/intel-ucode.img /media/usb/boot/ || echo "intel-ucode.img not found"

# Upgrade kernel from testing repo
# Not needed 3.23 is currently using the latest 6.18
# bash /usr/sbin/update-kernel -v -f stable --repositories-file /etc/apk/repositories-edge /media/usb/boot || err "Cannot update kernel"
#sed -i 's/lts/stable/g' /media/usb/boot/grub/grub.cfg || err "Unable to patch grub"
#umount /.modloop


# Backup changes using LBU (Local Backup Utility) to the USB drive
LBU_BACKUPDIR=/media/usb lbu commit || err "Cannot commit changes"

# Add startup services (RAID, LVM) to the default runlevel
# Add startup services
rc-update add mdadm-raid
rc-update add lvm default
#rc-update add irqbalance

# Enable root login via SSH for easier management
echo "Patching openssh for root login"
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

/etc/init.d/sshd restart

# Disable stp for br0
#echo "	bridge-stp 0" >> /etc/network/interfaces

# Allow QEMU to use br0 for bridge networking
echo "allow br0" > /etc/qemu/bridge.conf

echo "set bell-style none" >> /etc/inputrc

# Load necessary kernel modules for KVM and VFIO passthrough on boot
echo "
kvm_intel
kvm_amd
vfio_iommu_type1
tun
vfio-pci
vfio" >> /etc/modules


rc-update add local default
rc-update add ntpd default

# Ensure SSH keys are persisted across reboots
lbu include /root/.ssh

# Configure KVM and VFIO module options (Nested virt, AVIC, blacklist conflicting drivers)
######### CUSTOM STUFF ##################
echo "options kvm-intel nested=1 enable_apicv=1
options kvm-amd nested=1 avic=1
options kvm ignore_msrs=1
blacklist snd_hda_intel
blacklist amdgpu
" > /etc/modprobe.d/vfio.conf

echo '#!/bin/sh
# Add DKVM Data folder (Mounted from fstab)
mkdir /media/dkvmdata

# Mount what we can from fstab
mount -a
' >> /etc/local.d/dkvm_folder.start
chmod +x /etc/local.d/dkvm_folder.start

# Install main DKVM scripts to root's home directory
cp /media/cdrom/dkvmmenu.sh /root/dkvmmenu.sh

chmod +x /root/dkvmmenu.sh

lbu include /root

# Set DKVM menu to auto-start on tty1
cp /etc/inittab /etc/inittab.bak
cat /etc/inittab.bak | sed 's#tty1::.*#tty1::respawn:/root/dkvmmenu.sh#' > /etc/inittab

########################################

mount -o remount,rw /media/usb || err "Cannot remount /media/usb as readwrite"
apk cache -v sync
mount -o remount,ro /media/usb || err "Cannot remount /media/usb as readonly"

echo "Migrate to using disk label for APK cache"

umount /media/usb

# Update /etc/fstab for mount persistence (CDROM, USB, Hugepages, Data Partition)
cat > /etc/fstab <<EOF
/dev/cdrom	/media/cdrom	iso9660	noauto,ro 0 0
LABEL=dkvm     /media/usb    vfat   noauto,ro 0 0
# Hugepage mount
hugetlbfs	/dev/hugepages	hugetlbfs	defaults,pagesize=2M 0 0

# DKVM Data folder
# Create a partition/lvm volume or what-ever suits your needs,
# and add it here in fstab. (Destination must be /media/dkvmdata)
# You can use /etc/local.d/ to include any custom mounting.
# (Use Alt+RightArrow to get a root console)
LABEL=dkvmdata /media/dkvmdata  ext4 defaults,discard,nofail 0 0

EOF

# Issue discard by default(LVM)
sed 's/# issue_discards.*/issue_discards = 1/' -i /etc/lvm/lvm.conf

# Configure ACPI event handler to gracefully shut down the VM when the power button is pressed
echo $'echo -e \'{ "execute": "qmp_capabilities" }\\n{ "execute": "system_powerdown" }\' | timeout 5 nc localhost 4444' >  /etc/acpi/PWRF/00000080

setup-apkcache /media/usb/cache
setup-lbu usb

lbu commit -d -v

mount -o remount,ro /media/usb

sync
sleep 2
echo "Exiting stage02"
poweroff
