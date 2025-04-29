#!/bin/sh

err() {
	echo "ERROR $@"
	/bin/sh
}

sleep 5

if ! mountpoint /media/usb; then
	echo "/media/usb not automounted - binding /dev/sda1"
	# Sometimes /dev/usbdisk is not correctly mounted under /media/usb
	# In our case, it will then be /dev/sda1
	mount --bind /media/sda1 /media/usb || err "Bind mount failed"
fi

echo "Creating persistent apk cache"
mount -o remount,rw /media/usb || err "Cannot remount /media/usb as readwrite"
mkdir /media/usb/cache || err "Cannot create cache folder"

ln -s /media/usb/cache /etc/apk/cache

# Default arguments for Linux kernel
#extraArgs="nofb consoleblank=0 vga=0 nomodeset i915.modeset=0 nouveau.modeset=0 mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5"
extraArgs="mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5 blacklist=amdgpu"

# Patch grub2 (uefi boot)
[ -e /media/usb/boot/grub/grub.cfg.old ] && rm -f /media/usb/boot/grub/grub.cfg.old

cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/console=ttyS0,9600//g' | sed 's/\(modules=[^ ]*\)/\1,vfio-pci/'  > /media/usb/boot/grub/grub.cfg || err "Cannot patch grub"

# Edge kernel
# Disabled for now. We will manually inject a new kernel
#sed -i 's/lts/edge/g' /media/usb/boot/grub/grub.cfg || err "Unable to patch grub"
# Add br0
brctl addbr br0
brctl addif br0 eth0

ip link set dev eth0 up

setup-alpine -e -f /media/cdrom/answer.txt

#/bin/bash
# Add extra repositories
echo "Enable extra repositories"
sed -i '/^#.*v3.*community/s/^#/@community /' /etc/apk/repositories

# In case /dev/usbdisk was sda1, move it to usb
sed -i 's/sda1/usb/' /etc/apk/repositories

apk update
apk upgrade

# Install required tools
apk add ca-certificates wget util-linux bridge bridge-utils qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community qemu-hw-display-virtio-vga@community swtpm@community bash dialog bc nettle jq vim lvm2 lvm2-dmeventd e2fsprogs pciutils irqbalance hwloc-tools || err "Cannot install packages"

# Create reposotiry file for edge
# Disabled for now. We will manually inject a new kernel
#cp /etc/apk/repositories /etc/apk/repositories-edge
#sed -i 's/@community //' /etc/apk/repositories-edge

# Upgrade kernel
# Disabled for now. We will manually inject a new kernel
#update-kernel -f edge --repositories-file /etc/apk/repositories-edge /media/usb/boot
#umount /.modloop

LBU_BACKUPDIR=/media/usb lbu commit || err "Cannot commit changes"

# Add startup services
rc-update add mdadm-raid
rc-update add lvm default
#rc-update add irqbalance

echo "Patching openssh for root login"
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

/etc/init.d/sshd restart

# Disable stp for br0
#echo "	bridge-stp 0" >> /etc/network/interfaces

# Allow br0 as bridge-device for qemu
echo "allow br0" > /etc/qemu/bridge.conf

echo "set bell-style none" >> /etc/inputrc

# Modules required for basic kvm/vfio setup
echo "#!/bin/sh
# Load modules
modprobe kvm_intel
modprobe kvm_amd
modprobe vfio_iommu_type1
modprobe tun
modprobe vfio-pci
modprobe vfio
rmmod pcspkr
" >>/etc/local.d/modules.start


chmod +x /etc/local.d/modules.start

rc-update add local default
rc-update add ntpd default

# keep .ssh under lbu version control
lbu include /root/.ssh

######### CUSTOM STUFF ##################
echo "options kvm-intel nested=1 enable_apicv=1
options kvm-amd nested=1
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

# Copy dkvmmenu and status over
cp /media/cdrom/dkvmmenu.sh /root/dkvmmenu.sh
cp /media/cdrom/dkvmlog.sh /root/dkvmlog.sh

chmod +x /root/dkvmmenu.sh
chmod +x /root/dkvmlog.sh

lbu include /root

# Patch inittab to start dkvmmenu.sh
cp /etc/inittab /etc/inittab.bak
cat /etc/inittab.bak | sed 's#tty1::.*#tty1::respawn:/root/dkvmmenu.sh#' > /etc/inittab

########################################

mount -o remount,rw /media/usb || err "Cannot remount /media/usb as readwrite"
apk cache -v sync
mount -o remount,ro /media/usb || err "Cannot remount /media/usb as readonly"

echo "Migrate to using disk label for APK cache"

umount /media/usb

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

# Passthrouch ACPI Power Button to Desktop VM
echo $'echo -e \'{ "execute": "qmp_capabilities" }\\n{ "execute": "system_powerdown" }\' | timeout 5 nc localhost 4444' >  /etc/acpi/PWRF/00000080

setup-apkcache /media/usb/cache
setup-lbu usb

lbu commit -d -v

mount -o remount,ro /media/usb

sync
sleep 2
echo "Exiting stage02"
poweroff
