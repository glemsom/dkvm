#!/bin/sh

VMS="ubuntu winblows"

# Simple menu implementation
# This should really be improved to be more dynamic....
if [ "$1" == "menu" ]; then
	reset && clear
	echo '
	###### VM Menu ########
	
	###### Normal run #####
	1: xubuntu 18.04
	2: Winblows 10
	#######################
	
	## Install procedure ##
	3: xubuntu 18.04 install
	4: Winblows 10 install
	#######################


	8: reboot
	9: shutdown'
	echo -n "Choice: "
	read -rsn1 input
	
	case $input in
		1)
			echo "Starting Ubuntu"
			$0 ubuntu native
		;;
		2)
			echo "Starting Winblows"
			$0 winblows native
		;;
		3)
			echo "Starting install for Ubuntu"
			$0 ubuntu install
		;;
		4)
			echo "Starting install for Winblows"
			$0 winblows install
		;;
		8)
			reboot
		;;
		9)
			poweroff
		;;
	esac
	exit 0
fi

if [ -z "$2" ]; then
	echo "Error, need two arguments"
        echo "Use $0 VM_NAME install : No passthrough, and load install ISO"
        echo "Use $0 VM_NAME native  : Passthrough, and use passthrough VGA display"
        echo "Use $0 VM_NAME nogpu   : No pasthrough, virtuel VGA"
	echo
	echo "Valid VMs: $VMS"
	exit 1
fi


######## Default values ##################                                                                                                                        
vga="std"                                                                                                                                                         
display="-display vnc=:0"                                                                                                                                         
mouse="-usb -device usb-tablet"                                                                                                                                   
#net="-net nic,model=e1000 -net bridge,br=br0"                                                                                                                    
net="-device virtio-net-pci,netdev=net0 -netdev bridge,id=net0"
pciExtra=""                                                                                                                                                       
vfio=""                                                                                                                                                           
##########################################   




#### Settings per VM ####################

case $1 in 
	ubuntu) 
		VM=ubuntu
		HARDDISK=/media/storage01/disks/ubuntu_system.raw
		FILESIZE=20G
		INSTALLCD=/media/storage01/home/glemsom/Downloads/xubuntu-18.04-desktop-amd64.iso
		#ROM=/media/storage02/gfx-560.rom
		# PCI address of the passtrough devices
		DEVICE1="02:00.0" #GPU
		DEVICE2="02:00.1" #GPU HDMI
		DEVICE3="03:00.0" #PCI USB Controller
		#MAC=$(printf 'DE:AD:BE:EF:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)))
		MAC="DE:AD:BE:EF:B8:D8"
		BIOS="/media/storage02/bios/ovmf/ubuntu/OVMF.fd"
		BIOS_VARS="/media/storage02/bios/ovmf/ubuntu/OVMF_VARS.fd"
		SMP="-smp sockets=1,cores=3,threads=2"
		CORELIST="3 9 4 10 5 11"
		MEM="-m 8192"
		#net="-net nic,model=e1000 -net bridge,br=br0" #Use e1000 for ubuntu, as virtio causes issues
		;;
	winblows) 
		VM=winblows
		HARDDISK=/media/storage01/disks/winblows_system.raw
		FILESIZE=50G # This is ONLY for the install disk
		HARDDISK2=/media/storage01/disks/winblows_disk2.raw
		HARDDISK3=/media/storage02/disks/winblows_disk3.raw
		INSTALLCD=/media/storage01/home/glemsom/Downloads/win10-final.iso # NOTE: Required baked in virtio drivers!
		# https://www.vultr.com/docs/how-to-create-a-windows-custom-iso-with-updates-using-ntlite
		#ROM=/media/storage02/gfx-970.rom
		# PCI address of the passtrough devices
		DEVICE1="02:00.0" #GPU
		DEVICE2="02:00.1" #GPU HDMI
		DEVICE3="03:00.0" #PCI USB Controller
		#MAC=$(printf 'DE:AD:BE:EF:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)))
		MAC="DE:AD:BE:EF:B8:D9"
		BIOS="/media/storage02/bios/ovmf/winblows/OVMF.fd"
		BIOS_VARS="/media/storage02/bios/ovmf/winblows/OVMF_VARS.fd"
		SMP="-smp sockets=1,cores=4,threads=2"
		CORELIST="2 8 3 9 4 10 5 11"
		MEM="-m 12288"
		;;

	*)
		echo "Unknown VM_NAME: $1"
		exit 1
		;;
esac
##########################################


##### BIOS / HDDs ########################
bios="-drive if=pflash,format=raw,readonly,file=${BIOS} -drive if=pflash,format=raw,file=${BIOS_VARS}"
harddisk="-object iothread,id=iothread0 -drive if=none,id=drive0,cache=none,aio=native,format=raw,file=${HARDDISK} -device virtio-blk-pci,iothread=iothread0,drive=drive0"
if [ ! -z "$HARDDISK2" ]; then
        harddisk="$harddisk -drive if=none,id=drive1,cache=none,aio=native,format=raw,file=${HARDDISK2} -device virtio-blk-pci,iothread=iothread0,drive=drive1"
fi
if [ ! -z "$HARDDISK3" ]; then
        harddisk="$harddisk -drive if=none,id=drive2,cache=none,aio=native,format=raw,file=${HARDDISK3} -device virtio-blk-pci,iothread=iothread0,drive=drive2"
fi
##########################################



if [ "$2" == "install" ]; then
	echo "Installation start"
	# create installation file if not exist
	if [ ! -e "$HARDDISK" ]; then 
		qemu-img create -f raw "$HARDDISK" "$FILESIZE"
	fi
	# Prep for install
	cdrom="-cdrom ${INSTALLCD} -drive file=${DRIVERCD},media=cdrom,index=3"

elif [ "$2" == "native" ]; then
	echo "Native passthrough start"
	#devExtra=",x-vga=on,romfile=$ROM "
	vga="none"
	vfio=" -device vfio-pci,host=$DEVICE1,multifunction=on -device vfio-pci,host=$DEVICE2 -device vfio-pci,host=$DEVICE3"
	nographic=" -nographic"
	display=""
	mouse=""

elif [ "$2" == "nogpu" ]; then
	echo "NO GPU passthrough (safe mode) start"
	vga="std"
else
	echo "Use $0 install : No passthrough, and load install ISO"
	echo "Use $0 native  : Passthrough, and use passthrough VGA display"
	echo "Use $0 nogpu   : No pasthrough, virtuel VGA"
	exit 1
fi


for DEV in "0000:$DEVICE1" "0000:$DEVICE2" "0000:$DEVICE3"; do
	VENDOR=$(cat /sys/bus/pci/devices/${DEV}/vendor)
	DEVICE=$(cat /sys/bus/pci/devices/${DEV}/device)
	if [ -e /sys/bus/pci/devices/${DEV}/driver ]; then
		echo "$DEV" | tee /sys/bus/pci/devices/${DEV}/driver/unbind
		echo "Unloaded $DEV"
    else
        echo "No driver loaded for${VENDOR}:${DEVICE} @ $DEV"
    fi
	sleep 1
    if [ -e "/sys/bus/pci/devices/${DEV}/reset" ]; then
        echo "Resetting $DEV"
        echo 1 > "/sys/bus/pci/devices/${DEV}/reset"
    fi

    sleep 0.5
    echo "Registrating vfio-pci on ${VENDOR}:${DEVICE}"
    echo "$VENDOR $DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id
done



( sleep 15
	echo "Setting CPU affinity using cores: $CORELIST"
	THREADS=`( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus" }' | timeout -t 2 nc localhost 4444 | tr , '\n' ) | grep thread_id | cut -d : -f 2 | sed -e 's/}.*//g' -e 's/ //g'`

	IFS="
"

	# Setup CPU pinning
	COUNT=1
	for THREAD_ID in $THREADS; do
			CURCORE=$(echo $CORELIST | cut -d " " -f $COUNT)
			taskset -pc $CURCORE $THREAD_ID
			COUNT=$(( $COUNT + 1 ))
	done

) & 

echo "Starting qemu..."
echo " "

qemu-system-x86_64 \
-nodefaults \
-name $1 \
-enable-kvm \
$MEM \
-mem-prealloc \
-cpu host,kvm=off,hv_time,hv_relaxed,hv_spinlocks=0x1fff,hv_vpindex,hv_reset,hv_runtime,hv_crash,hv_vapic,hv_vendor_id="blows" \
$SMP \
-machine q35,accel=kvm \
-serial none \
-parallel none \
$bios \
$vfio \
-vga $vga \
$net \
$cdrom \
$harddisk \
$nographic \
-monitor stdio \
-rtc base=localtime,clock=host -no-hpet \
-qmp tcp:localhost:4444,server,nowait \
$display \
$mouse

#-device ivshmem-plain,memdev=ivshmem,bus=pcie.0 -object memory-backend-file,id=ivshmem,share=on,mem-path=/dev/shm/looking-glass,size=32M
