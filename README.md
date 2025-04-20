# DKVM
DKVM - Desktop KVM

DKVM is a minimal KVM hypervisor running from RAM.
The idea behind DKVM is to re-use the already well-known components on GNU/Linux systems to do network, storage and virtualization - and then run everything else inside a VM.
The scripts are for my personal use - so some adjustment is needed if you want to build this yourself.

To build, simply edit "setup.sh" and follow the instructions.

When done, dd the "usbdisk.img" file to a USB disk or similar.

My blog explains a little more about the process behind DKVM: [GlemSom Tech](https://glemsomtechs.blogspot.com/2018/07/dkvm-desktop-kvm.html)
