#!/bin/bash
# DKVM Menu
# Glenn Sommer <glemsom+dkvm AT gmail.com>

version=$(cat /media/usb/dkvm-release)
# Change to script directory
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -a menuItems
declare -a menuItemsType
declare -a menuItemsVMs
menuAnswer=""

export configDataFolder=/media/dkvmdata
export configPassthroughPCIDevices=$configDataFolder/passthroughPCIDevices
export configPassthroughUSBDevices=$configDataFolder/passthroughUSBDevices
export configCPUTopology=$configDataFolder/cpuTopology
export configCPUOptions=$configDataFolder/cpuOptions
export configCustomStartStopScript=$configDataFolder/customStartStopScript

configBIOSCODE=/usr/share/OVMF/OVMF_CODE.fd
configBIOSVARS=/usr/share/OVMF/OVMF_VARS.fd

configReservedMemMB=$(( 1024 * 4 )) # 4GB

# Sends a command to QEMU via QMP
doQMP() {
	local cmd=$1
	# Connect to QMP and send command
	echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "'$cmd'" }' | timeout 2 nc localhost 4444 2>/dev/null
}

# Returns the current status of the QEMU instance
waitForQMP() {
	local max_attempts=30
	local attempt=1
	echo "Waiting for QMP to become ready..." | doOut
	while [ $attempt -le $max_attempts ]; do
		echo -e '{ "execute": "qmp_capabilities" }' | timeout 1 nc localhost 4444 |& doOut
		if [ "${PIPESTATUS[1]}" -eq 0 ]; then
			echo "QMP is ready." | doOut
			return 0
		fi
		sleep 1
		let attempt++
	done
	err "QMP failed to become ready after $max_attempts seconds"
}

getQEMUStatus() {
	local resp=$(doQMP query-status)
	if [ -z "$resp" ]; then
		echo "disconnected" # Connection failed
	else
		echo "$resp" | grep return | tail -n 1 | jq -r .return.status 2>/dev/null
	fi
}

# Returns the thread IDs of the guest vCPUs
getQEMUThreads() {
	doQMP query-cpus-fast | tail -n1 | jq '.return[] | ."thread-id"' 2>/dev/null
}

# Displays information about USB devices being passed through
getUSBPassthroughDevices() {
	local file=$1
	if [ -f "$file" ]; then
		local usbDevices=$(cat "$file")
		for usbDevice in $usbDevices; do
			lsusb 2>/dev/null | grep "$usbDevice" # Show device info
		done
	else
		echo "No USB passthrough file found at $file"
	fi
}

# Displays information about PCI devices being passed through
getPCIPassthroughDevices() {
	local file=$1
	if [ -f "$file" ]; then
		local pciDevices=$(cat "$file")
		for pciDevice in $pciDevices; do
			lspci -s "$pciDevice" # Show device info
		done
	else
		echo "No PCI passthrough file found at $file"
	fi
}

# Main status monitoring loop
doLogViewerLoop() {
	local usbPassthroughFile=$1
	local pciPassthroughFile=$2
	local qemuStarted=false
	local shownUSBDevices=false
	local shownPCIDevices=false
	local shownThreads=false
	local loopCount=0

	echo "Waiting for QEMU to start..."
	
	while true; do
		local currentStatus=$(getQEMUStatus) # Get current QEMU status
		
		if ! $qemuStarted; then
			if [ "$currentStatus" == "running" ]; then
				echo "QEMU detected with status running"
				qemuStarted=true
			elif [ $loopCount -ge 30 ]; then
				echo "QEMU not detected within 30 seconds - aborting" # Timeout
				exit 1
			fi
		else
			# Show detailed information once QEMU is running
			if ! $shownThreads; then
				echo "QEMU Threads: " $(getQEMUThreads | tr '\n' ' ')
				shownThreads=true
			fi
			
			if ! $shownUSBDevices; then
				echo -e "\nUSB Devices passthrough:"
				getUSBPassthroughDevices "$usbPassthroughFile"
				shownUSBDevices=true
			fi
			
			if ! $shownPCIDevices; then
				echo -e "\nPCI Devices passthrough:"
				getPCIPassthroughDevices "$pciPassthroughFile"
				shownPCIDevices=true
			fi
			
			# Exit loop if QEMU stops or disconnects
			if [ "$currentStatus" != "running" ]; then
				echo "QEMU exited or disconnected (Status: $currentStatus)."
				exit 0
			fi
		fi
		
		sleep 1 # Wait for next polling cycle
		let loopCount++
	done
}

# --- LOG VIEWER ARGUMENT CHECK ---
if [ "$1" == "--logviewer" ]; then
	shift
	doLogViewerLoop "$@"
	exit 0
fi

err() {
	echo "ERROR $@"
	exit 1
}

# Scans the config directory for VM configurations and builds the menu list
buildMenuItemVMs() {
	shopt -s nullglob
	menuItemsVMs=""
	itemNumber=0
	for VMConfig in $configDataFolder/*/vm_config; do
		itemName=$(getConfigItem $VMConfig NAME)
		menuItemsVMs[$itemNumber]="$itemName"
		let itemNumber++
	done
	shopt -u nullglob
}

# Copys the OVMF UEFI firmware files to the VM directory if missing
doInstallBIOSFiles() {
	local VMFolder="$1"
	if [ ! -e ${VMFolder}/OVMF_CODE.fd ]; then
		echo "Installing ${VMFolder}/OVMF_CODE.fd" | doOut
		cp $configBIOSCODE "${VMFolder}/OVMF_CODE.fd" || err "Cannot install $configBIOSCODE -> ${VMFolder}/OVMF_CODE.fd"
	fi
	if [ ! -e ${VMFolder}/OVMF_VARS.fd ]; then
		echo "Installing ${VMFolder}/OVMF_VARS.fd" | doOut
		cp $configBIOSVARS "${VMFolder}/OVMF_VARS.fd" || err "Cannot install $configBIOSVARS -> ${VMFolder}/OVMF_VARS.fd"
	fi
}

# Starts the software TPM (swtpm) for the VM
doStartTPM() {
	local vmFolder="$1"
	# Cleanup if an old was running
	if pgrep swtpm; then
		killall swtpm
	fi
	mkdir -p ${vmFolder}/tpm || err "Cannot create folder ${vmFolder}/tpm"
	/usr/bin/swtpm socket --tpmstate dir=${vmFolder}/tpm,mode=0600 --ctrl type=unixio,path=${vmFolder}/tpm.sock,mode=0600 --log file=${vmFolder}/tpm.log --terminate --tpm2 &
}

# Displays the current log status in a dialog box
doShowStatus() {
	dialog --backtitle "$backtitle" \
		--title "Desktop VM" --prgbox "$0 --logviewer $configPassthroughUSBDevices $configPassthroughPCIDevices" 25 80
	clear
}

# cleaning up potential background processes and running custom stop scripts
cleanup(){
	if [ -e $configCustomStartStopScript ]; then
		. $configCustomStartStopScript
		if declare -F customVMStop >/dev/null; then
			customVMStop
		else
			err "customVMStop script missing from $configCustomStartStopScript"
		fi
	else
		echo "No custom configCustomStartStopScript defined" | doOut
	fi
}

# Handles logging, clearing logs, or showing the log viewer
doOut() {
	local TAILFILE=dkvm.log
	if [ "$1" == "clear" ]; then
		rm -f "$TAILFILE"
		touch "$TAILFILE"
	elif [ "$1" == "showlog" ]; then
		doShowStatus
		# Clean rutine
		# When exited, kill any remaining qemu
		cleanup
		exit 0 # Reload script
	else
		cat - >>"$TAILFILE"
	fi
}

# Compiles the list of menu items from available VMs and internal commands
buildItems() {

	buildMenuItemVMs

	menuItems=()
	menuItemsType=()
	VMMenuIndex=()

	for i in "${!menuItemsVMs[@]}"; do
		if [ ! -z "${menuItemsVMs[$i]}" ]; then
			VMMenuIndex+=($i)
			menuItems+=("Start ${menuItemsVMs[$i]}")
			menuItemsType+=("VM")
		fi
	done

	# Preconfigured items
	menuItems+=("Configure DKVM")
	menuItemsType+=("INT_CONFIG")

	menuItems+=("PowerOff / Restart")
	menuItemsType+=("INT_POWEROFF")

	menuItems+=("Drop to shell")
	menuItemsType+=("INT_SHELL")
}

# Displays the main interaction menu using the dialog utility
showMainMenu() {

	buildItems

	local title="DKVM Main menu"
	local menuStr=""
	# build menu
	for i in $(seq 0 $((${#menuItems[@]} - 1))); do
		local menuStr="$menuStr ${menuItemsType[$i]}-${VMMenuIndex[$i]} '${menuItems[$i]}'"
	done
	local ip=$(ip a | grep "inet " | grep -v "inet 127" | awk '{print $2}')
	backtitle="DKVM @ $ip   Version: $version"
	local menuStr="$tmpFix --title '$title' --backtitle '$backtitle' --no-tags --no-cancel --menu 'Select option' 0 0 20 $menuStr --stdout"
	menuAnswer=$(eval "dialog $menuStr")
	if [ $? -eq 1 ]; then
		err "Main dialog canceled ?!"
	fi
}

# Processes the user's selection from the main menu
doSelect() {
	local type=$(echo $menuAnswer | cut -d "-" -f 1)
	local item=$(echo $menuAnswer | cut -d "-" -f 2)

	if [[ $type == INT_* ]]; then
		mainHandlerInternal $type
	elif [ "$type" == "VM" ]; then
		mainHandlerVM $item
	else
		err "Unknown type : $type"
	fi
}

# Finds the highest numbered VM configuration folder to determine the next ID
getLastVMConfig() {
	basename $(find $configDataFolder -maxdepth 1 -type d -name "[0-9]" | sort | tail -n 1)
}

# Creates a new VM with a default template configuration
doAddVM() {
	local template='NAME=New VM

# Multiple harddisk can be configured
# Can be either a blockdevice, or a file
#HARDDISK=/dev/mapper/vg_nvme-lv_debian
#HARDDISK=/media/dkvmdata/disks/debian.raw

# CDROM ISO file
#CDROM=/media/dkvmdata/isos/debian-12.8.0-amd64-netinst.iso

# GPU ROM (Usually not needed)
#GPUROM=/media/dkvmdata/dummy.rom

# Enable an emulated graphics card, and setup VNC to listen.
# <IP>:<Display Numer>
# Example 0.0.0.0:0 will listen on all IPs, and use the first display (port 5900)
#VNCLISTEN=0.0.0.0:0

# MAC Address
MAC=DE:AD:BE:EF:66:61
'
	# Find next dkvm_vmconfig.X
	local lastVMConfig=$(getLastVMConfig)
	if [ -z "$lastVMConfig" ]; then
		# First VM
		nextVMIndex=0
	elif [ $getLastVMConfig == 9 ]; then
		dialog --msgbox "All VM slots in use. Please clear up in ${configDataFolder}/[0-9]" 0 0
		exit 1
	else
		nextVMIndex=$(($lastVMConfig + 1))
	fi

	mkdir -p $configDataFolder/${nextVMIndex} || err "Cannot create VM folder"
	echo "$template" > $configDataFolder/${nextVMIndex}/vm_config || err "Cannot write VM Template"

	doEditVM "$configDataFolder/${nextVMIndex}/vm_config"
}

# Opens the editor for the selected VM's configuration file
doEditVM() {
	if [ "$1" != "" ]; then
		# Edit VM directly
		vi "$1"
	else
		menuStr=""
		while read -r VMFolder; do
			[ -z "$VMFolder" ] && continue
			local VMName=$(getConfigItem ${VMFolder}/vm_config NAME)
			local menuStr="$menuStr $(basename $VMFolder) '$VMName'"
		done < <(find $configDataFolder -type d -maxdepth 1 -name "[0-9]")
		local menuAnswer=$(eval "dialog --backtitle "'$backtitle'" --menu 'Choose VM to edit' 0 0 20 $menuStr" --stdout)

		[ "$menuAnswer" != "" ] && vi ${configDataFolder}/${menuAnswer}/vm_config
	fi
}

# Detects CPU topology and proposes a split between Host and VM cores
# Typically reserves Core 0 and its thread sibling for the Host
writeOptimalCPULayout() {
	# Pick first core, and any SMT as the host core
	# TODO: What if we have more sockets / CCX?
	HOSTCPU=$(lscpu -p| grep -E '(^[0-9]+),0' | cut -d, -f1 | tr '\n' ',')
	VMCPU=$(lscpu -p| grep -v \# | grep -v -E '(^[0-9]+),0' | cut -d, -f1 | tr '\n' ',')
	CPUTHREADS=$(lscpu |grep Thread | cut -d: -f2|tr -d ' ')
	if [ ! -z "$HOSTCPU" ] && [ ! -z "$VMCPU" ]; then  
	cat > $configCPUTopology <<EOF
# This file is auto-generated upon first start-up.
# To regenerate, just delete this file
#
# To get more info about your CPU, use tools like lscpu and lstopo(hwloc-tools)
# $(lstopo --of console --no-io | sed 's/^/#/')
#
# Host CPUs reserves for Host OS.
# Minimum is to allocate at-least 1 core for the host (including SMT/Hyperthreading core)
# Recommended to to use at-least 2 cores for the host (including SMT/Hyperthreading core)
#
# HOSTCPU is the allocated cores for HOST OS
HOSTCPU=${HOSTCPU::-1}
# VMCPU is the allocated cores for the VM OS. Recommendation is to use all cores, except for the cores in-use by the host OS
VMCPU=${VMCPU::-1}
# Threads per core (This is usually 2 for modern CPUs)
CPUTHREADS=${CPUTHREADS}
EOF
	fi
}

# interactive selection of USB devices for passthrough
doUSBConfig() {
	echo "USB Config" | doOut # Log entry
	prevChoice=""
	if [ -e $configPassthroughUSBDevices ]; then
		prevChoice=$(cat $configPassthroughUSBDevices) # Get current selection
	fi

	local options=()
	# Get unique USB IDs and their names
	while read -r line; do
		USBId=$(echo "$line" | awk '{print $6}') # Extract ID
		USBName=$(echo "$line" | cut -d ' ' -f 7-) # Extract Name

		state=off
		while read -r prev; do
			if [ "$prev" = "$USBId" ]; then
				state=on # Mark as selected
				break
			fi
		done <<< "$prevChoice"
		options+=("$USBId" "$USBName" "$state")
	done < <(lsusb 2>/dev/null | sort -u -k6,6) # Sort by ID and take unique

	choice=$(dialog --backtitle "$backtitle" --separate-output --checklist "Select USB devices for passthrough:" 20 70 10 "${options[@]}" 2>&1 >/dev/tty) # Show dialog
	[ $? -ne 0 ] && return # Return if canceled

	echo "$choice" > $configPassthroughUSBDevices # Save selection
}

# Updates the GRUB configuration to add or remove kernel parameters
doUpdateGrub() {
		mount -oremount,rw /media/usb/ || err "Cannot remount /media/usb"
		local grubFile=/media/usb/boot/grub/grub.cfg
		local key="$1"
		local value="$2"

		[ ! -z "$key" ] || [ ! -z "$value" ] || err "VFIO ID's not found $key $value"
		# Get clean Linux line
		grubLinuxLineCleaned=$(sed -e "s/ ${key}=[^ ]*//g" <<< $(grep ^linux $grubFile))
		# Backup grub file
		cp ${grubFile} ${grubFile}.bak || err "Unable to backup GRUB config file"
		# Put in cleaned Linux line
		sed "s#^linux.*#$grubLinuxLineCleaned#g" -i $grubFile
		# Add key=value
		sed "/^linux.*/s/\$/ ${key}=${value}/" -i $grubFile || err "Unable to patch grub.cfg"
		mount -oremount,ro /media/usb/ || err "Cannot remount /media/usb"
		dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 0 0
}

# Updates the /etc/modprobe.d/vfio.conf file with the selected PCI IDs
doUpdateModprobe() {
	local ids="$1"
	mount -oremount,rw /media/usb || err "Cannot remount /media/usb"
	sed -i '/options vfio-pci.*/d' /etc/modprobe.d/vfio.conf
	echo -en "\noptions vfio-pci ids=$ids" >> /etc/modprobe.d/vfio.conf
	mount -oremount,ro /media/usb || err "Cannot remount /media/usb"
}

# interactive selection of PCI devices for passthrough
doPCIConfig() {
	echo "PCI Config" | doOut # Log entry
	prevChoice=""
	if [ -e $configPassthroughPCIDevices ]; then
		prevChoice=$(cat $configPassthroughPCIDevices) # Get current selection
	fi

	local options=()
	while read -r line; do
		pciID=$(echo "$line" | cut -f 1 -d " ") # PCI Address
		pciName=$(echo "$line" | cut -f 2- -d " ") # Device Name

		state=off
		while read -r prev; do
			if [ "$prev" = "$pciID" ]; then
				state=on # Mark as selected
				break
			fi
		done <<< "$prevChoice"
		options+=("$pciID" "$pciName" "$state")
	done < <(lspci)

	choice=$(dialog --backtitle "$backtitle" --separate-output --checklist "Select PCI devices for passthrough:" 20 70 10 "${options[@]}" 2>&1 >/dev/tty) # Show dialog
	[ $? -ne 0 ] && return # Return if canceled

	echo "$choice" > $configPassthroughPCIDevices # Save selection

	vfioIds=""
	while read -r selectedDevice; do
		[ -z "$selectedDevice" ] && continue
		vfioIds+=$(lspci -n -s $selectedDevice | grep -Eo '(([0-9]|[a-f]){4}|:){3}'),
	done <<< "$choice"
	vfioIds=$(echo $vfioIds | sed 's/,$//') # Clean trailing comma

	dialog --yesno "Add vfio-pci.ids to /etc/modprobe.d/vfio?" 0 0
	if [ "$?" -eq "0" ]; then
		doUpdateModprobe "$vfioIds" # Update modprobe
	fi
	dialog --yesno "Add vfio-pci.ids to kernel commandline?" 0 0
	if [ "$?" -eq "0" ]; then
		doUpdateGrub vfio-pci.ids "$vfioIds" # Update grub
	fi
	doSaveChanges # Save all changes
}

# Persists changes using lbu commit (Alpine Linux specific)
doSaveChanges() {
	local changesTxt="Changes saved...
$(lbu commit)"
	dialog --backtitle "$backtitle" --msgbox "$changesTxt" 0 0
}

# Handlers for internal menu commands (config, poweroff, etc.)
mainHandlerInternal() {
	local item="$1"
	if [ "$1" == "INT_SHELL" ]; then
		/bin/bash
	elif [ "$1" == "INT_POWEROFF" ]; then
		local menuStr="--title '$title' --backtitle '$backtitle' --no-tags --menu 'Select option' 20 50 20 1 Reboot 2 PowerOFF --stdout"
		local menuAnswer=$(eval "dialog $menuStr")
		if [ "$menuAnswer" == "1" ]; then
			reboot
		elif [ "$menuAnswer" == "2" ]; then
			poweroff
		else
			showMainMenu && doSelect
		fi
	elif [ "$1" == "INT_CONFIG" ]; then
		declare -a menuOptions
		menuOptions[1]="Add new VM"
		menuOptions[2]="Edit VM"
		menuOptions[3]="Edit CPU Topology"
		menuOptions[4]="Edit PCI Passthrough"
		menuOptions[5]="Edit USB Passthrough"
		menuOptions[6]="Edit Custom PCI reload script"
		menuOptions[7]="Edit CPU options"
		menuOptions[8]="Save changes"

		local itemString=""

		for item in "${!menuOptions[@]}"; do
			itemString+="$item '${menuOptions[$item]}' "
		done
		itemString=$(echo "$itemString" | sed 's/ $//')

		local menuStr="--title '$title' --backtitle '$backtitle' --no-tags --menu 'Select option' 20 50 20 $itemString  --stdout"
		local menuAnswer=$(eval "dialog $menuStr")

		if [ "$menuAnswer" == "1" ]; then
			doAddVM
		elif [ "$menuAnswer" == "2" ]; then
			doEditVM
		elif [ "$menuAnswer" == "3" ]; then
			[ ! -e $configCPUTopology ] && writeOptimalCPULayout
			vim $configCPUTopology
			doKernelCPUTopology
		elif [ "$menuAnswer" == "4" ]; then
			doPCIConfig
		elif [ "$menuAnswer" == "5" ]; then
			doUSBConfig
		elif [ "$menuAnswer" == "6" ]; then
			setupCustomStartStopScript
		elif [ "$menuAnswer" == "7" ]; then
			doEditCPUOptions
		elif [ "$menuAnswer" == "8" ]; then
			doSaveChanges
		fi
		showMainMenu && doSelect
	else
		dialog --msgbox "TODO: Make this work..." 6 60
		showMainMenu && doSelect
	fi
}

# Optimizes system parameters for real-time virtualization performance
realTimeTune() {
	# Reduce vmstat collection
	[ -e /proc/sys/vm/stat_interval ] && echo 300 >/proc/sys/vm/stat_interval 2>/dev/null
	# Disable watchdog
	[ -e proc/sys/kernel/watchdog ] && echo 0 >/proc/sys/kernel/watchdog 2>/dev/null
}

# Checks if a given PCI device address corresponds to a VGA/Display controller
isGPU() {
	local device=$1
	return $(lspci -s $device | grep -q VGA)
}

# Calculates the amount of memory available for the VM, leaving some for the host
getVMMemMB() {
	local reservedMemMB=$1
	local totalMemKB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	local totalMemMB=$(( $totalMemKB / 1024 ))

	VMMemMB=$(( $totalMemMB - $reservedMemMB ))
	echo $(( ${VMMemMB%.*} /2 * 2 ))
}


# Allocates hugepages based on the requested VM memory size
setupHugePages() {
	local VMMemMB=$1
	local pageSizeMB=2
	local required=$(( $VMMemMB / $pageSizeMB ))
	echo 1 > /proc/sys/vm/compact_memory
	echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag
	echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
	echo $(( $required + 8 )) > /proc/sys/vm/nr_hugepages
}

# Main entry point for starting a VM. Constructs the QEMU command and manages the lifecycle.
mainHandlerVM() {
	local VMID=$1
	source $configCPUTopology
	clear
	doStartTPM $configDataFolder/${VMID}
	doInstallBIOSFiles $configDataFolder/${VMID}
	doOut "clear"
	local configFile=$configDataFolder/${VMID}/vm_config

	local VMNAME="$(getConfigItem $configFile NAME)"
	local VMHARDDISK=$(getConfigItem $configFile HARDDISK)
	local VMCDROM=$(getConfigItem $configFile CDROM)
	local VMGPUROM=$(getConfigItem $configFile GPUROM)
	local VMPASSTHROUGHPCIDEVICES=$(cat $configPassthroughPCIDevices)
	local VMPASSTHROUGHUSBDEVICES=$(cat $configPassthroughUSBDevices)
	local VMBIOS=$configDataFolder/${1}/OVMF_CODE.fd
	local VMBIOS_VARS=$configDataFolder/${1}/OVMF_VARS.fd
	local VMMEMMB=$(getVMMemMB $configReservedMemMB)
	local VMMAC=$(getConfigItem $configFile MAC)
	local VNCLISTEN=$(getConfigItem $configFile VNCLISTEN)
	local VMCPUOPTS=$(getConfigItem $configFile CPUOPTS)

	# Build qemu command
	# Basic Machine setup (Q35 chipset, KVM accel, Split IRQ chip)
	OPTS="-name \"$VMNAME\",debug-threads=on -nodefaults -no-user-config -accel accel=kvm,kernel-irqchip=split -machine q35,mem-merge=off,vmport=off,dump-guest-core=off -qmp tcp:localhost:4444,server,nowait "

	# Memory and Clock settings (Prealloc memory, lock memory to RAM, Localtime RTC)
	#OPTS+=" -mem-prealloc -overcommit mem-lock=on,cpu-pm=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
	OPTS+=" -mem-prealloc -overcommit mem-lock=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "

	# Networking (Sourced from bridge helper)
	OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"

	# Hugepages for better memory performance
	OPTS+=" -m ${VMMEMMB}M"

	# Disable S3/S4 sleep states
	OPTS+=" -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -global kvm-pit.lost_tick_policy=discard "

	# TPM Device (Linked to swtpm socket)
	OPTS+=" -chardev socket,id=chrtpm,path=$configDataFolder/${VMID}/tpm.sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"

	# QEMU Guest Agent (For host-guest communication)
	OPTS+=" -device virtio-serial-pci,id=virtio-serial0 -chardev socket,id=guestagent,path=/tmp/qga.sock,server,nowait -device virtserialport,chardev=guestagent,name=org.qemu.guest_agent.0"

	# Boot options and firmware config
	OPTS+=" -boot menu=on,splash-time=5000"
	OPTS+=" -fw_cfg opt/ovmf/X-PciMmio64Mb,string=65536"
	if [ -z "$VNCLISTEN" ]; then
		OPTS+=" -nographic -vga none"
	else
		OPTS+=" -vga std -vnc $VNCLISTEN"
	fi
	if [ ! -z "$VMCPU" ] && [ ! -z "$CPUTHREADS" ]; then
		local TMPALLCORES=$(echo $VMCPU | sed 's/,/ /g'|wc -w)
		local TMPCORES=$(echo ${TMPALLCORES}/${CPUTHREADS} | bc)
		local DIES=$(getNumDies $VMCPU)
		#OPTS+=" -smp threads=${CPUTHREADS},cores=${TMPCORES}"
		# Start with 1 cpu (required), and make room to add the others later
		OPTS+=" -smp cpus=1,threads=$CPUTHREADS,sockets=1,maxcpus=32,dies=$DIES"

		# Setup vNUMA nodes matching host NUMA nodes
		node_id=0
		local NODE_COUNT=$(echo $VMCPU | tr ',' '\n' | xargs -I{} sh -c 'basename /sys/devices/system/cpu/cpu$1/node* | sed s/node//' -- {} | sort -u | wc -l)
		local MEM_PER_NODE=$(( VMMEMMB / NODE_COUNT ))
		while read -r PHYS_NODE; do
			[ -z "$PHYS_NODE" ] && continue
			OPTS+=" -object memory-backend-memfd,id=mem${node_id},size=${MEM_PER_NODE}M,hugetlb=on,hugetlbsize=2M,prealloc=on"
			OPTS+=" -numa node,nodeid=${node_id},memdev=mem${node_id}"
			let node_id++
		done < <(echo $VMCPU | tr ',' '\n' | xargs -I{} sh -c 'basename /sys/devices/system/cpu/cpu$1/node* | sed s/node//' -- {} | sort -u)
	fi
	if [ ! -z "$VMBIOS" ] && [ ! -z "$VMBIOS_VARS" ]; then
		OPTS+=" -drive if=pflash,format=raw,readonly=on,file=${VMBIOS} -drive if=pflash,format=raw,file=${VMBIOS_VARS}"
	fi

	if [ ! -z "$VMHARDDISK" ]; then
		COUNT=0
		THREADCOUNT=0
		OPTS+=" -device virtio-scsi-pci,id=scsi"
		while read -r DISK; do
			[ -z "$DISK" ] && continue
			#OPTS+=" -object iothread,id=iothread${THREADCOUNT}"
			#OPTS+=" -object iothread,id=iothread$(( ${THREADCOUNT} + 1 ))"
			OPTS+=" -drive if=none,cache=none,aio=native,discard=unmap,detect-zeroes=unmap,format=raw,file=${DISK},id=drive${COUNT}"
			OPTS+=" -device scsi-hd,drive=drive${COUNT}"
			#OPTS+=" --device '{\"driver\":\"virtio-scsi-pci\",\"iothread-vq-mapping\":[{\"iothread\":\"iothread${THREADCOUNT}\"},{\"iothread\":\"iothread$(( ${THREADCOUNT} + 1 ))\"}],\"drive\":\"drive${COUNT}\"}'"
			let COUNT=COUNT+1
			let THREADCOUNT=THREADCOUNT+2
		done <<< "$VMHARDDISK"
	fi
	if [ ! -z "$VMCDROM" ]; then
		while read -r CD; do
			[ -z "$CD" ] && continue
			OPTS+=" -drive file=${CD},media=cdrom"
		done <<< "$VMCDROM"
	fi
	if [ ! -z "$VMPASSTHROUGHPCIDEVICES" ]; then
		# Use PCIE bus
		OPTS+=" -device pcie-root-port,id=root_port1,chassis=0,slot=0,bus=pcie.0"
		loopCount=0
		while read -r VMPASSTHROUGHPCIDEVICE; do
			[ -z "$VMPASSTHROUGHPCIDEVICE" ] && continue
			if isGPU $VMPASSTHROUGHPCIDEVICE; then # If this is a GPU adapter, set multifunction=on
				[ ! -z "$VMGPUROM" ] && GPUROMSTRING=",romfile=$VMGPUROM" || GPUROMSTRING=""
				OPTS+=" --device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE},bus=root_port1,addr=00.${loopCount},multifunction=on$GPUROMSTRING"
			else
				OPTS+=" -device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE},bus=root_port1,addr=00.${loopCount}"
			fi
			let loopCount++
		done <<< "$VMPASSTHROUGHPCIDEVICES"
	fi
	if [ ! -z "$VMPASSTHROUGHUSBDEVICES" ]; then
		while read -r VMPASSTHROUGHUSBDEVICE; do
			[ -z "$VMPASSTHROUGHUSBDEVICE" ] && continue
			local USBVendor=$(cut -d : -f 1 <<<$VMPASSTHROUGHUSBDEVICE)
			local USBProduct=$(cut -d : -f 2 <<<$VMPASSTHROUGHUSBDEVICE)
			OPTS+=" -device qemu-xhci -device usb-host,vendorid=0x${USBVendor},productid=0x${USBProduct}"
		done <<< "$VMPASSTHROUGHUSBDEVICES"
	fi

	if [ -e $configCPUOptions ]; then
		OPTS+=" -cpu host,$(doEchoCPUOptions)"
	else
		OPTS+=" -cpu host"
	fi
	doOut "clear"
	setupHugePages $VMMEMMB |& doOut
	echo "QEMU Options $OPTS" | doOut
	realTimeTune | doOut
	IRQAffinity | doOut
	reloadPCIDevices $VMPASSTHROUGHPCIDEVICES
	eval qemu-system-x86_64 -S $OPTS 2>&1 | doOut &
	waitForQMP && addCPUs $VMCPU 2>&1 | doOut && continueVM &
	doOut showlog
}

# Resumes the paused VM via QMP
continueVM() {
	echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "cont" }' | timeout 2 nc localhost 4444 > /dev/null 2>&1
}


# Gets the host PID for a specific vCPU thread via QMP
getvCorePid() {
	local COREID=$1
	local DIEID=$2
	local THREADID=$3
	local PIDS=$(echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 0.5 nc localhost 4444 | tail -n1 | jq ".return[] | select(.\"props\".\"core-id\" == $COREID and .\"props\".\"die-id\" == $DIEID and .\"props\".\"thread-id\" == $THREADID) | .\"thread-id\"") 2>/dev/null
	echo "$PIDS"
}

# Counts the number of physical CPU dies
getNumDies() {
	local CPUS=$1
	local IFS=',' 
	read -r -a CPU_CORES <<< "$CPUS"
	local DIE_IDS=()

	# Iterate over each CPU core
	for CPU_CORE in "${CPU_CORES[@]}"; do
		# Check if the CPU core is valid
		if [[ -d "/sys/devices/system/cpu/cpu${CPU_CORE}" ]]; then
			# Get the die_id for the current CPU core
			local DIE_ID=$(cat "/sys/devices/system/cpu/cpu${CPU_CORE}/topology/die_id")

			# Add the die_id to the array if it's not already present
			local FOUND=false
			for EXISTING_DIE in "${DIE_IDS[@]}"; do
				if [[ "$EXISTING_DIE" == "$DIE_ID" ]]; then
					FOUND=true
					break
				fi
			done
			if [[ "$FOUND" == false ]]; then
				DIE_IDS+=("$DIE_ID")
			fi
		fi
	done

	# Count the number of unique DIE_IDS
	echo "${#DIE_IDS[@]}"
}


# Hotplugs a vCPU into the running VM
addvCore() {
	local COREID=$1
	local DIE_ID=$2
	local THREAD_ID=$3
	local SOCKET=$4
	local HOSTCORE=$5
	local NODE_ID=$6
	echo "Adding vCore: Host Core Id: $HOSTCORE, Guest Core ID=$COREID, Die ID=$DIE_ID, vThread ID=$THREAD_ID, Node ID=$NODE_ID"
	
	local qmp_args='{ 
		"core-id": '$COREID', 
		"driver": "host-x86_64-cpu", 
		"id": "cpu-'${HOSTCORE}'", 
		"die-id": '$DIE_ID', 
		"socket-id": '$SOCKET', 
		"thread-id": '$THREAD_ID',
		"node-id": '$NODE_ID'
	}'
	
	echo -e '{ "execute": "qmp_capabilities" }
	{ "execute": "device_add", "arguments": '$qmp_args' }' | timeout 1 nc localhost 4444 | grep error
}

# Helper to print associative arrays
printarr() { declare -n __p="$1"; for k in "${!__p[@]}"; do printf "%s=%s\n" "$k" "${__p[$k]}" ; done ;  } 

# Pinning and hotplugging CPUs
# This function handles the complex mapping of Host Cores -> Guest vCPUs
# ensuring siblings (HyperThread pairs) are kept together.
addCPUs() {
	declare -A PROCESSED_SIBLING_LIST
	declare -A HOST_NODE_TO_GUEST_NODE

	# The host cores to add to the VM as virtual cores
	echo "Adding CPUs for $1"

	# Add cores to array of cores
	IFS=',' read -r -a TMPHOSTCORES <<< "$1"

	# Map physical host nodes to guest node IDs
	local node_idx=0
	while read -r PHYS_NODE; do
		[ -z "$PHYS_NODE" ] && continue
		HOST_NODE_TO_GUEST_NODE[$PHYS_NODE]=$node_idx
		let node_idx++
	done < <(echo $1 | tr ',' '\n' | xargs -I{} sh -c 'basename /sys/devices/system/cpu/cpu$1/node* | sed s/node//' -- {} | sort -u)

	# Cleanup first core from array, as it is already pre-added to the VM
	if [ ${#TMPHOSTCORES[@]} -gt 0 ]; then
		local FIRST_CORE=${TMPHOSTCORES[0]}
		local SIBLINGS=$(cat /sys/devices/system/cpu/cpu${FIRST_CORE}/topology/thread_siblings_list)
		local PHYS_NODE=$(basename /sys/devices/system/cpu/cpu${FIRST_CORE}/node* | sed 's/node//')
		local DIE_ID=$(cat /sys/devices/system/cpu/cpu${FIRST_CORE}/topology/die_id)
		local NODE_ID=${HOST_NODE_TO_GUEST_NODE[$PHYS_NODE]}
		
		# Get PID for core
		TMPPID=$(getvCorePid 0 0 0) # QEMU boots with core-id 0, die-id 0, thread-id 0
		taskset -pc $FIRST_CORE $TMPPID
		PROCESSED_SIBLING_LIST[$SIBLINGS]=0
		echo "Already pinned core $FIRST_CORE (part of $SIBLINGS) to vCore 0"
		unset 'TMPHOSTCORES[0]'
		HOSTCORES=("${TMPHOSTCORES[@]}") # Re-index the array
	fi
	echo "First core pinned"

	VCORE=1 # Start from 1 for the first die, as 0 is already attached

	while read -r DIE; do
		[ -z "$DIE" ] && continue
		echo "Processing for die $DIE"
		
		for HOSTCORE in ${HOSTCORES[@]}; do
			local CUR_DIE_ID=$(cat /sys/devices/system/cpu/cpu${HOSTCORE}/topology/die_id)
			if [ "$CUR_DIE_ID" == "$DIE" ]; then
				local SIBLING_LIST=$(cat /sys/devices/system/cpu/cpu${HOSTCORE}/topology/thread_siblings_list)
				local PHYS_NODE=$(basename /sys/devices/system/cpu/cpu${HOSTCORE}/node* | sed 's/node//')
				local NODE_ID=${HOST_NODE_TO_GUEST_NODE[$PHYS_NODE]}
				echo "Processing hostcore $HOSTCORE @ die $DIE (host node $PHYS_NODE -> guest node $NODE_ID) with siblings_list $SIBLING_LIST"
				
				if [ ! -z "${PROCESSED_SIBLING_LIST[$SIBLING_LIST]}" ]; then
					local GUEST_CORE_ID=${PROCESSED_SIBLING_LIST[$SIBLING_LIST]}
					echo "    Host core $HOSTCORE is a sibling. Adding as thread 1 of guest core $GUEST_CORE_ID"
					addvCore $GUEST_CORE_ID $CUR_DIE_ID 1 0 $HOSTCORE $NODE_ID
					TMPPID=$(getvCorePid $GUEST_CORE_ID $CUR_DIE_ID 1)
					taskset -pc $HOSTCORE $TMPPID
				else
					echo "    Host core $HOSTCORE is a new core. Adding as thread 0 of guest core $VCORE"
					addvCore $VCORE $CUR_DIE_ID 0 0 $HOSTCORE $NODE_ID
					PROCESSED_SIBLING_LIST[$SIBLING_LIST]=$VCORE
					TMPPID=$(getvCorePid $VCORE $CUR_DIE_ID 0)
					taskset -pc $HOSTCORE $TMPPID
					let VCORE++
				fi
			fi
		done
		# Reset VCORE for next die (QEMU expects core_id to be reset per die)
		VCORE=0
	done < <(echo $1 | tr ',' '\n' | xargs -I{} cat /sys/devices/system/cpu/cpu{}/topology/die_id | sort -u)
}

# Unbinds PCI devices from their host drivers and binds them to vfio-pci for passthrough
reloadPCIDevices() {
	if [ -e $configCustomStartStopScript ]; then
		. $configCustomStartStopScript
		if declare -F customVMStart >/dev/null; then
			customVMStart
		else
			echo "Unable to find function customVMStart() in $configCustomStartStopScript" | doOut
			return 1
		fi
	else
		for device in $@; do
			local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
			local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
			if [ -e /sys/bus/pci/devices/0000:${device}/driver/unbind ]; then
				echo "Unbinding 0000:${device}" | doOut
				echo "0000:${device}" >/sys/bus/pci/devices/0000:${device}/driver/unbind 2>&1 | doOut
				sleep 1
			fi
			echo "Removing $pciVendor $pciDevice from vfio-pci" | doOut
			echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/remove_id 2>&1 | doOut
			if [ -e "/sys/bus/pci/devices/0000:${device}/reset" ]; then
				echo "Resetting $device" | doOut
				echo 1 >"/sys/bus/pci/devices/0000:${device}/reset" 2>&1 | doOut
				sleep 1
			fi
		done

		for device in $@; do
			local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
			local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
			echo "Registrating vfio-pci on ${pciVendor}:${pciDevice}" | doOut
			echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/new_id 2>&1 | doOut
			sleep 0.5
		done
	fi
}

# Creates or edits the user-defined start/stop script
setupCustomStartStopScript() {
	if [ -e $configCustomStartStopScript ]; then
		vi $configCustomStartStopScript
	else
		cat <<-'EOF' > $configCustomStartStopScript
# Sample startStopScript
# Look at examples at https://github.com/glemsom/dkvm/tree/master/examples
customVMStart() {
	echo "Starting custom start script"
	echo "Done with custom start script"
}

customVMStop() {
	echo "Starting custom stop script"
	echo "Done with custom stop script"
}
EOF
	fi
	vi $configCustomStartStopScript
}

# Reads a specific key-value pair from a config file
getConfigItem() {
	local configFile="$1"
	local item="$2"

	if [ -f "$configFile" ]; then
		local value=$(cat "$configFile" | grep "^${item}=" | sed "s/${item}=//g")
	else
		err "Configuration file $configFile not found"
	fi

	echo "$value"
}

# Configure kernel parameters (isolcpus, nohz_full, rcu_nocbs) to isolate VM cores from the host scheduler
doKernelCPUTopology() {
	if [ ! -e $configCPUTopology ]; then
		err "No cpuTopology file found"
	else
		source $configCPUTopology
	fi
	clear
	mount -oremount,rw /media/usb/ || err "Cannot remount /media/usb"
	cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old || err "Cannot copy grub.cfg"
	cat /media/usb/boot/grub/grub.cfg.old | sed '/^menuentry "DKVM"/,\|^}|s|\(linux.*\)isolcpus=[^ ]*|\1isolcpus=domain,managed_irq,'$VMCPU'|; \
																					 /isolcpus=[^ ]*/!s|\(linux.*\)$|\1 isolcpus=domain,managed_irq,'$VMCPU'|; \
																					 s|\(linux.*\)nohz_full=[^ ]*|\1nohz_full='$VMCPU'|; \
																					 /nohz_full=[^ ]*/!s|\(linux.*\)$|\1 nohz_full='$VMCPU'|; \
																					 s|\(linux.*\)rcu_nocbs=[^ ]*|\1rcu_nocbs='$VMCPU'|; \
																					 /rcu_nocbs=[^ ]*/!s|\(linux.*\)$|\1 rcu_nocbs='$VMCPU'|' > /media/usb/boot/grub/grub.cfg

	mount -oremount,ro /media/usb/ || err "Cannot remount /media/usb"
	dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 0 0
}

# Masks VFIO interrupts from irqbalance to prevent them from landing on non-VM cores (or vice-versa)
IRQAffinity() {
	# Replaced with irqbalance
	source $configCPUTopology

	# irqbalance will honor isolcpu - so everything will go on $HOSTCPU by default.
	# Manually exclude VFIO devices, as they prefer to be on the same core as the VM
	IRQLine=""
	while read -r IRQ; do
		[ -z "$IRQ" ] && continue
		IRQLine+=" --banirq=$IRQ"
	done < <(grep vfio /proc/interrupts | cut -d ":" -f 1 | sed 's/ //g')
	echo "VFIO IRQ bans for irqbalance: $IRQLine" | doOut
	/usr/sbin/irqbalance --oneshot $IRQLine | doOut
}

# Displays a warning if the DKVM data directory is not mounted
doWarnDKVMData() {
	local txt
	txt+="DKVM relies on a mountpoint to store VM BIOS and TPM data.\n"
	txt+="DKVMData mountpoint should be formatted and mounted at /media/dkvmdata.\n"
	txt+="As an example could be a LVM volume with a ext4 filesystem.\n\n"
	txt+="Please use CTRL+ArrowRight to get a root-console, and setup\n"
	txt+="a mountpoint for DKVMData. (You might want to adjust /etc/fstab too)\n"

	dialog --cr-wrap --clear --msgbox "$txt" 0 0

	exit 1
}

# Dialog for selecting CPU features/flags
doEditCPUOptions() {
	prevChoice=""
	if [ -e $configCPUOptions ]; then
		prevChoice=$(cat $configCPUOptions)
	fi

	# Setup CPU options
	local options=()
	for opt in "kvm=off" "hv-vendor-id=dkvm" "hv-frequencies" "hv-relaxed" \
						"hv-reset" "hv-runtime" "hv-spinlocks=0x1fff" "hv-stimer" "hv-synic" \
						"hv-time" "hv-vapic" "hv-vpindex" "topoext=on" "l3-cache=on" "x2apic=on" \
						"migratable=off" "invtsc=on"; do
		desc=" "
		case $opt in
			kvm=off )             desc="Hide KVM Hypervisor signature" ;;
			hv-vendor-id=dkvm )   desc="Set custom hardware vendor ID" ;;
			hv-frequencies )      desc="Provides HV_X64_MSR_TSC_FREQUENCY" ;;
			hv-relaxed )          desc="Disable watchdog timeouts" ;;
			hv-reset )            desc="Provides HV_X64_MSR_RESET" ;;
			hv-runtime )          desc="Provides HV_X64_MSR_RUNTIME" ;;
			hv-spinlocks=0x1fff ) desc="Paravirtualized spinlocks" ;;
			hv-stimer )           desc="Enables Hyper-V synthetic timers" ;;
			hv-synic )            desc="Enables Hyper-V Synthetic interrupt controller" ;;
			hv-time )             desc="Enables two Hyper-V-specific clocksources" ;;
			hv-vapic )            desc="Provides VP Assist page MSR" ;;
			hv-vpindex )          desc="Provides HV_X64_MSR_VP_INDEX MSR" ;;
			topoext=on )          desc="Enable topology extension" ;;
			l3-cache=on )         desc="Enable L3 layout cache" ;;
			x2apic=on )           desc="Enable x2APIC mode" ;;
			migratable=off )      desc="Disable migration support" ;;
			invtsc=on )           desc="Set invtsc flag" ;;
		esac

		state=off
		while read -r prev; do
			if [ "$prev" = "$opt" ]; then
				state=on
			fi
		done <<< "$prevChoice"

		options+=("$opt" "$desc" "$state")
	done

	choice=$(dialog --backtitle "$backtitle" --separate-output --checklist "Select CPU Options:" 20 70 8 "${options[@]}" 2>&1 >/dev/tty)

	echo "$choice" > $configCPUOptions
}

# outputs the selected CPU options as a comma-separated string for QEMU
doEchoCPUOptions() {
	if [ -e $configCPUOptions ]; then
		cat $configCPUOptions | tr '\n' ',' | sed 's/,*$//g'
	fi
}

mountpoint $configDataFolder || doWarnDKVMData

[ ! -e $configPassthroughUSBDevices ] && doUSBConfig
[ ! -e $configPassthroughPCIDevices ] && doPCIConfig
[ ! -e $configCPUTopology ] && writeOptimalCPULayout && vi $configCPUTopology && doKernelCPUTopology && doSaveChanges

showMainMenu
doSelect
