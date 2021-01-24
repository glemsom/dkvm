#!/bin/sh

err() {
	echo "ERROR $@"
	/bin/bash
}

# Patch lbu.conf for USB media
echo "Patching /etc/lbu/lbu.conf for usb storage"
sed -i 's/.*LBU_MEDIA.*/LBU_MEDIA=usb/g' /etc/lbu/lbu.conf

echo "Creating persistent apk cache"
mount -o remount,rw /media/usb
mkdir /media/usb/cache

# Extra arguments for Linux kernel
#TODO : Get this from a config file instead?
extraArgs="nouveau.modeset=0 mitigations=off intel_iommu=on iommu=pt transparent_hugepage=never vfio-pci.ids=10de:13c2,10de:0fbb,1106:3483 elevator=noop default_hugepagesz=2M hugepagesz=2M isolcpus=2-11 nohz_full=2-11 rcu_nocbs=2-11"

# Patch syslinux (legacy boot)
cp /media/usb/boot/syslinux/syslinux.cfg /media/usb/boot/syslinux/syslinux.cfg.old
cat /media/usb/boot/syslinux/syslinux.cfg.old | sed 's/^MENU LABEL.*/MENU LABEL DKVM/g' | sed 's/lts/dkvm/g' | sed "/^APPEND/ s/$/ $extraArgs /" | sed 's/quiet//g' > /media/usb/boot/syslinux/syslinux.cfg

# Patch grub2 (uefi boot)
cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old
cat /media/usb/boot/grub/grub.cfg.old | sed 's/^menuentry .*{/menuentry "DKVM" {/g' | sed 's/lts/dkvm/g' | sed "/^linux/ s/$/ $extraArgs /" | sed 's/quiet//g' | sed 's/console=ttyS0,9600//g'> /media/usb/boot/grub/grub.cfg

mount -o remount,ro /media/usb
ln -s /media/usb/cache /etc/apk/cache

# Run alpine setup
setup-alpine

# Add extra repositories
echo "Enable extra repositories"
sed -i '/^#.*testing/s/^#/@testing /' /etc/apk/repositories
sed -i '/^#.*community/s/^#/@community /' /etc/apk/repositories

apk update
apk upgrade

# Install required tools
apk add util-linux bridge bridge-utils qemu-img@community mdadm bcache-tools qemu-system-x86_64@community bash dialog bc nettle


apk --no-cache add ca-certificates wget
wget -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
mount -o remount,rw /media/usb || err "Cannot remount /media/usb to readwrite"
mkdir -p /media/usb/custom

mount -o remount,ro /media/usb || err "Cannot remount /media/usb"

rc-update add mdadm-raid

echo "Patching openssh for root login"
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

/etc/init.d/sshd restart

# Disable stp for br0
echo "	bridge-stp 0" >> /etc/network/interfaces

# Allow br0 as bridge-device for qemu
echo "allow br0" > /etc/qemu/bridge.conf

echo "set bell-style none" >> /etc/inputrc

# Modules required for basic kvm/vfio setup
echo "#!/bin/sh
# Load modules
modprobe kvm_intel
modprobe vfio_iommu_type1
modprobe tun
modprobe vfio-pci
modprobe vfio
modprobe vhost_net
modprobe vhost_scsi
modprobe vhost_sock
rmmod pcspkr
" >>/etc/local.d/modules.start


chmod +x /etc/local.d/modules.start

rc-update add local default
rc-update add ntpd default

# keep .ssh under lbu version control
lbu include /root/.ssh

######### CUSTOM STUFF ##################
echo "options vfio-pci ids=10de:13c2,10de:0fbb,1106:3483 disable_vga=1
options kvm-intel nested=1 enable_apicv=1
options kvm ignore_msrs=1
" > /etc/modprobe.d/vfio.conf

echo '#!/bin/sh
# Load require modules
modprobe bcache
modprobe raid5

mkdir /media/storage01
mkdir /media/storage02

mdadm --assemble /dev/md0 --uuid "66134aaa:cd2da0da:352dceec:21ec6aa9"
mount /dev/md0p1 /media/storage01

echo /dev/sda2 > /sys/fs/bcache/register
echo /dev/sdb2 > /sys/fs/bcache/register


mount /dev/bcache0 /media/storage02/

mkdir /dev/hugepages

mount -t hugetlbfs none /dev/hugepages
' >> /etc/local.d/mount.start
chmod +x /etc/local.d/mount.start

echo '#!/bin/sh
apk add /media/usb/custom/*.apk' >> /etc/local.d/custom-apk.start
chmod +x /etc/local.d/custom-apk.start

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


apk -v cache clean
lbu commit -v
lbu commit -d -v

echo "Exiting stage02"
sleep 2
poweroff
