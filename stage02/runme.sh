#!/bin/sh

err() {
	echo "ERROR $@"
	/bin/sh
}


echo "Creating persistent apk cache"

mount -o remount,rw /media/usb
mkdir /media/usb/cache

# Extra arguments for Linux kernel
#TODO : Get this from a config file instead?
extraArgs="nofb consoleblank=0 vga=0 nomodeset i915.modeset=0 nouveau.modeset=0 mitigations=off intel_iommu=on amd_iommu=on iommu=pt elevator=noop waitusb=5"

# Patch syslinux (legacy boot)
cp /media/usb/boot/syslinux/syslinux.cfg /media/usb/boot/syslinux/syslinux.cfg.old
cat /media/usb/boot/syslinux/syslinux.cfg.old | sed 's/^MENU LABEL.*/MENU LABEL DKVM/g' | sed "/^APPEND/ s/$/ $extraArgs /" | sed 's/quiet//g' > /media/usb/boot/syslinux/syslinux.cfg

# Patch grub2 (uefi boot)
cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/console=ttyS0,9600//g'> /media/usb/boot/grub/grub.cfg

# Switch to edge kernel
#sed -i 's/lts/edge/g' /media/usb/boot/grub/grub.cfg

#mount -o remount,ro /media/usb
ln -s /media/usb/cache /etc/apk/cache

# Add br0

brctl addbr br0
brctl addif br0 eth0

ip link set dev eth0 up

mount /media/cdrom
setup-alpine -e -f /media/cdrom/answer.txt

#/bin/bash
# Add extra repositories
echo "Enable extra repositories"
sed -i '/^#.*v3.*community/s/^#/@community /' /etc/apk/repositories


apk update
apk upgrade

# Install required tools
apk add util-linux bridge bridge-utils qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community swtpm@community bash dialog bc nettle jq vim lvm2 e2fsprogs pciutils || err "Cannot install packages"

# Install edge kernel
# Create reposotiry file for edge
#cp /etc/apk/repositories /etc/apk/repositories-edge
#sed -i 's/@community //' /etc/apk/repositories-edge

#update-kernel -f edge --repositories-file /etc/apk/repositories-edge /media/usb/boot


LBU_BACKUPDIR=/media/usb lbu commit || err "Cannot commit changes"

apk add ca-certificates wget
wget -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
mount -o remount,rw /media/usb || err "Cannot remount /media/usb to readwrite"
mkdir -p /media/usb/custom

mount -o remount,ro /media/usb || err "Cannot remount /media/usb"

rc-update add mdadm-raid

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
" > /etc/modprobe.d/vfio.conf

echo '#!/bin/sh
# Setup mounts

mkdir /media/iso
mkdir /media/bios

lvchange -ay vg_nvme

mount /dev/mapper/vg_nvme-bios /media/bios
mount /dev/mapper/vg_nvme-iso /media/iso
' >> /etc/local.d/mount.start
chmod +x /etc/local.d/mount.start


cp /media/cdrom/dkvmmenu.sh /root/dkvmmenu.sh

# Copy any VM config
cp /media/cdrom/dkvm_* /root/

# Rename files
for f in /root/dkvm_vmc*; do
    mv "$f" `echo $f | sed 's/vmc/vmconfig/g'`
done

chmod +x /root/dkvmmenu.sh

lbu include /root

# Patch inittab to start vm_start.sh
cp /etc/inittab /etc/inittab.bak
cat /etc/inittab.bak | sed 's#tty1::.*#tty1::respawn:/root/dkvmmenu.sh#' > /etc/inittab

########################################

mount -o remount,rw /media/usb

apk cache -v sync

mount -o remount,ro /media/usb

echo "Migrate to using disk label for APK cache"

umount /media/usb
cat > /etc/fstab <<EOF
/dev/cdrom	/media/cdrom	iso9660	noauto,ro 0 0
LABEL=dkvm     /media/usb    vfat   noauto,ro 0 0
EOF

setup-apkcache /media/usb/cache
setup-lbu usb

lbu commit -d -v

echo "Exiting stage02"
sleep 2
poweroff
