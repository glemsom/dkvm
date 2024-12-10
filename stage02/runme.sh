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

# Patch grub2 (uefi boot)
cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/console=ttyS0,9600//g'> /media/usb/boot/grub/grub.cfg


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
apk add ca-certificates wget util-linux bridge bridge-utils qemu-img@community qemu-hw-usb-host@community qemu-system-x86_64@community ovmf@community swtpm@community bash dialog bc nettle jq vim lvm2 lvm2-dmeventd e2fsprogs pciutils || err "Cannot install packages"

LBU_BACKUPDIR=/media/usb lbu commit || err "Cannot commit changes"

wget -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
mount -o remount,rw /media/usb || err "Cannot remount /media/usb to readwrite"
mkdir -p /media/usb/custom

mount -o remount,ro /media/usb || err "Cannot remount /media/usb"

# Add startup services
rc-update add mdadm-raid
rc-update add lvm default

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
# Add DKVM Data folder (Mounted from fstab)
mkdir /media/dkvmdata

# Mount what we can from fstab
mount -a
' >> /etc/local.d/dkvm_folder.start
chmod +x /etc/local.d/dkvm_folder.start

# Copy dkvmmenu over
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
# DKVM Data folder
# Create a partition/lvm volume or what-ever suits your needs,
# and add it here in fstab. (Destination must be /media/dkvmdata)
# You can use /etc/local.d/ to include any custom mounting.
# (Use Alt+RightArrow to get a root console)
LABEL=dkvmdata /media/dkvmdata  ext4 defaults,discard,nofail 0 0

EOF

# Issue discard by default(LVM)
sed 's/# issue_discards.*/issue_discards = 0/' -i /etc/lvm/lvm.conf

setup-apkcache /media/usb/cache
setup-lbu usb

lbu commit -d -v

echo "Exiting stage02"
sleep 2
poweroff
