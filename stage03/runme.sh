#!/bin/bash
set -x
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

workdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
chroot_dir=${workdir}/Alpine_chroot
mirror=http://nl.alpinelinux.org/alpine/
branch=v3.8

( umount ${chroot_dir}/dev/pts; sudo umount ${chroot_dir}/dev/; sudo umount ${chroot_dir}/sys; sudo umount ${chroot_dir}/proc ) 2>/dev/null
rm -rf "$chroot_dir"

wget -r -l1 -np ${mirror}/${branch}/main/x86_64/ -A "apk-tools-static*" -P ${workdir}/

tar -xzf ${workdir}/*/alpine/${branch}/main/x86_64/apk-tools-static-*.apk -C ${workdir}


mkdir ${chroot_dir}
${workdir}/sbin/apk.static -X ${mirror}/${branch}/main -U --allow-untrusted --root "${chroot_dir}" --initdb add alpine-base

cp /etc/resolv.conf ${chroot_dir}/etc/
mkdir -p ${chroot_dir}/root

mkdir -p ${chroot_dir}/etc/apk
echo "${mirror}/${branch}/main" > ${chroot_dir}/etc/apk/repositories

# HACK ##########
#rm -rf "${chroot_dir}"
#cp -rp "${chroot_dir}-save" "${chroot_dir}"
#################
mount -t proc none ${chroot_dir}/proc
mount -o bind /sys ${chroot_dir}/sys
mount -o bind /dev ${chroot_dir}/dev
mount -o bind /dev/pts ${chroot_dir}/dev/pts

cat <<EOF > $chroot_dir/runme.sh
#!/bin/sh
apk add alpine-sdk bash squashfs-tools
adduser alpine -D
echo alpine:alpine | chpasswd
echo "alpine	ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
addgroup alpine abuild
addgroup alpine adm
addgroup alpine wheel
EOF

# Enter chroot
chroot ${chroot_dir} /bin/sh /runme.sh

cat <<EOF > ${chroot_dir}/home/alpine/runme.sh
#!/bin/bash
set -x
function err() {
  echo "Unknown error - bailing out to shell $@"
  /bin/bash
}

cd /home/alpine
export PATH=/sbin:/usr/sbin:${PATH}
# REPLACE ME !!
git config --global user.name "Glenn Sommer"
git config --global user.email "glemsom@gmail.com"
################################################
git clone https://github.com/glemsom/aports.git
abuild-keygen -a -i -n

cd /home/alpine/aports
git checkout 3.8-stable
cd main/linux-vanilla

# Get current kernel version
KERNELVER=\$(grep pkgver APKBUILD | head -n 1 | cut -d = -f 2)
PKGREL=\$(grep pkgrel APKBUILD | head -n 1 | cut -d = -f 2)
#/bin/bash
abuild -r || err

sudo apk add /home/alpine/packages/main/x86_64/linux-vanilla-\${KERNELVER}-r\${PKGREL}.apk
mkdir /home/alpine/dkvm_kernel && cd /home/alpine/dkvm_kernel

sudo sed -i 's/usb/usb squashfs/' /etc/mkinitfs/mkinitfs.conf || err
sudo mkinitfs \${KERNELVER}-\${PKGREL}-vanilla || err "Cannot build initrd"
cp /boot/*vanilla .

mkdir -p modloop_files/modules
sudo cp -rp /lib/modules/\${KERNELVER}-\${PKGREL}-vanilla modloop_files/modules || err "Cannot copy modules"
sudo cp -rp /lib/firmware modloop_files/modules || err "Cannot copy firmware"

mksquashfs modloop_files modloop-vanilla

EOF
chmod +x ${chroot_dir}/home/alpine/runme.sh

chroot ${chroot_dir} /bin/su - alpine -c "/home/alpine/runme.sh"

mkdir ${workdir}/kernel_files
cp -r ${chroot_dir}/home/alpine/dkvm_kernel ${workdir}/kernel_files

umount ${chroot_dir}/dev/pts
umount ${chroot_dir}/dev
umount ${chroot_dir}/sys
umount ${chroot_dir}/proc

rm -rf "${chroot_dir}"
rm -rf sbin
