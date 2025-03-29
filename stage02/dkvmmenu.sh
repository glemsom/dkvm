#!/bin/bash
# DKVM Menu
# Glenn Sommer <glemsom+dkvm AT gmail.com>

version=$(cat /media/usb/dkvm-release)
# Change to script directory
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLDIFS=$IFS
IFS="
"
declare -a menuItems
declare -a menuItemsType
declare -a menuItemsVMs
menuAnswer=""

export configDataFolder=/media/dkvmdata
export configPassthroughPCIDevices=$configDataFolder/passthroughPCIDevices
export configPassthroughUSBDevices=$configDataFolder/passthroughUSBDevices
export configCPUTopology=$configDataFolder/cpuTopology
export configCustomStartStopScript=$configDataFolder/customStartStopScript

configBIOSCODE=/usr/share/OVMF/OVMF_CODE.fd
configBIOSVARS=/usr/share/OVMF/OVMF_VARS.fd

configReservedMemMB=$(( 1024 * 2 )) # 2GB


err() {
  echo "ERROR $@"
  exit 1
}

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

# Install OVMF BIOS if not already present
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

doStartTPM() {
  local vmFolder="$1"
  # Cleanup if an old was running
  if pgrep swtpm; then
    killall swtpm
  fi
  mkdir -p ${vmFolder}/tpm || err "Cannot create folder ${vmFolder}/tpm"
  /usr/bin/swtpm socket --tpmstate dir=${vmFolder}/tpm,mode=0600 --ctrl type=unixio,path=${vmFolder}/tpm.sock,mode=0600 --log file=${vmFolder}/tpm.log --terminate --tpm2 &
}

doShowStatus() {
  dialog --backtitle "$backtitle" \
    --title "Desktop VM" --prgbox "./dkvmlog.sh $configPassthroughUSBDevices $configPassthroughPCIDevices " 30 80
  clear
}

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
  local menuStr="$tmpFix --title '$title' --backtitle '$backtitle' --no-tags --no-cancel --menu 'Select option' 20 50 20 $menuStr --stdout"
  menuAnswer=$(eval "dialog $menuStr")
  if [ $? -eq 1 ]; then
    err "Main dialog canceled ?!"
  fi
}

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

getLastVMConfig() {
  basename $(find $configDataFolder -maxdepth 1 -type d -name "[0-9]" | sort | tail -n 1)
}

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

# Extra CPU options to qemu
CPUOPTS=kvm=off,hv_vendor_id=dkvm,hv-frequencies,hv-relaxed,hv-reset,hv-runtime,hv-spinlocks=0x1fff,hv-stimer,hv-synic,hv-time,hv-vapic,hv-vpindex,topoext=on,l3-cache=on
'
  # Find next dkvm_vmconfig.X
  local lastVMConfig=$(getLastVMConfig)
  if [ -z "$lastVMConfig" ]; then
    # First VM
    nextVMIndex=0
  elif [ $getLastVMConfig == 9 ]; then
    dialog --msgbox "All VM slots in use. Please clear up in ${configDataFolder}/[0-9]" 20 60
    exit 1
  else
    nextVMIndex=$(($lastVMConfig + 1))
  fi

  mkdir -p $configDataFolder/${nextVMIndex} || err "Cannot create VM folder"
  echo "$template" > $configDataFolder/${nextVMIndex}/vm_config || err "Cannot write VM Template"
  
  doEditVM "$configDataFolder/${nextVMIndex}/vm_config"
}

doEditVM() {
  if [ "$1" != "" ]; then
    # Edit VM directly
    vi "$1"
  else
    local VMFolders=$(find $configDataFolder -type d -maxdepth 1 -name "[0-9]")
    menuStr=""
    for VMFolder in $VMFolders; do
      local VMName=$(getConfigItem ${VMFolder}/vm_config NAME)
      local menuStr="$menuStr $(basename $VMFolder) '$VMName'"
    done
    local menuAnswer=$(eval "dialog --backtitle "'$backtitle'" --menu 'Choose VM to edit' 20 30 20 $menuStr" --stdout)

    [ "$menuAnswer" != "" ] && vi ${configDataFolder}/${menuAnswer}/vm_config
  fi
}

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
#
# Host CPUs reserves for Host OS.
# Recommended is to use at least 1 CPU (inclusing SMT/Hyperthreading core)
HOSTCPU=${HOSTCPU::-1}
# CPUs reserved for VM
# Recommended is all, expect for the CPUs for the host
VMCPU=${VMCPU::-1}
# Number of SMT/Hyperthreads to emulate in topology
# Recommended is to keep the same as host topology
CPUTHREADS=${CPUTHREADS}
EOF
  fi
}

doUSBConfig() {
  echo "USB Config" | doLog
  local USBDevices=$(lsusb 2>/dev/null)
  dialogStr=""

  for USBDevice in $USBDevices; do
    USBId=$(grep -Eo '(([0-9]|[a-f]){4}|:){3}' <<<$USBDevice)
    USBName=$(cut -d : -f 2- <<<$USBDevice | sed "s/.*$USBId //g")
    dialogStr+="\"$USBId\" \"$USBName\" off "
  done
  selectedDevices=$(eval dialog --stdout --scrollbar --checklist \"Select USB devices for passthrough\" 40 80 70 $dialogStr | tr ' ' '\n')

  [ -z "$selectedDevices" ] && exit 1

  echo "$selectedDevices" > $configPassthroughUSBDevices
}

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
    dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 20 60
}

doUpdateModprobe() {
  local ids="$1"
  mount -oremount,rw /media/usb || err "Cannot remount /media/usb"
  sed -i '/options vfio-pci.*/d' /etc/modprobe.d/vfio.conf
  echo -en "\noptions vfio-pci ids=$ids" >> /etc/modprobe.d/vfio.conf
  mount -oremount,ro /media/usb || err "Cannot remount /media/usb"
}

doPCIConfig() {
  local pciDevices=$(lspci)
  dialogStr=""
  declare -a deviceInfo

  OLDIFS=$IFS
  IFS="
"

  for pciDevice in $pciDevices; do
      pciID=$(cut -f 1  -d " " <<< $pciDevice)
      pciName=$(cut -f 2- -d " " <<< $pciDevice)

      # Build dialog
      dialogStr+="\"$pciID\" \"$pciName\" off "
  done

  selectedDevices=$(eval dialog --stdout --scrollbar --checklist \"Select PCI devices for passthrough\" 40 80 70 $dialogStr | tr ' ' '\n')
  echo "$selectedDevices" > $configPassthroughPCIDevices

  [ -z "$selectedDevices" ] && exit 1

  for selectedDevice in $selectedDevices; do
      vfioIds+=$(lspci -n -s $selectedDevice | grep -Eo '(([0-9]|[a-f]){4}|:){3}'),
  done
  dialog --yesno "Add vfio-pci.ids to /etc/modprobe.d/vfio?" 10 80
  if [ "$?" -eq "0" ]; then
    doUpdateModprobe $(tr ' ' ',' <<<$vfioIds | sed 's/,$//')
  fi
  dialog --yesno "Add vfio-pci.ids to kernel commandline?\nNOTE: This is often required for vfio to load before any graphical drivers" 10 80
  if [ "$?" -eq "0" ]; then
    doUpdateGrub vfio-pci.ids $(tr ' ' ',' <<<$vfioIds | sed 's/,$//')
  fi
  doSaveChanges
  
  
  IFS=$OLDIFS
}

doSaveChanges() {
  local changesTxt="Changes saved...
$(lbu commit)"
  dialog --backtitle "$backtitle" --msgbox "$changesTxt" 30 80
}

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
    menuOptions[7]="Save changes"
    
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
      doSaveChanges
    fi
    showMainMenu && doSelect
  else
    dialog --msgbox "TODO: Make this work..." 6 60
    showMainMenu && doSelect
  fi
}

realTimeTune() {
  # Move dirty page writeback to CPU0 only
  echo 1 > /sys/devices/virtual/workqueue/cpumask
  # Reduce vmstat collection
  echo 300 >/proc/sys/vm/stat_interval 2>/dev/null
  # Disable watchdog
  echo 0   >/proc/sys/kernel/watchdog 2>/dev/null
}

isGPU() {
  local device=$1
  return $(lspci -s $device | grep -q VGA)
}

getVMMemMB() {
  local reservedMemMB=$1
  local totalMemKB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local totalMemMB=$(( $totalMemKB / 1024 ))

  VMMemMB=$(( $totalMemMB - $reservedMemMB ))
  echo $(( ${VMMemMB%.*} /2 * 2 ))
}


setupHugePages() {
  local VMMemMB=$1
  local pageSizeMB=2
  local required=$(( $VMMemMB / $pageSizeMB ))
  echo 1 > /proc/sys/vm/compact_memory
  echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag
  echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
  echo $(( $required + 8 )) > /proc/sys/vm/nr_hugepages
}

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
  OPTS="-name \"$VMNAME\",debug-threads=on -nodefaults -no-user-config -accel accel=kvm,kernel-irqchip=on -machine q35,mem-merge=off,vmport=off,dump-guest-core=off -qmp tcp:localhost:4444,server,nowait "
  #OPTS+=" -mem-prealloc -overcommit mem-lock=on,cpu-pm=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
  OPTS+=" -mem-prealloc -overcommit mem-lock=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
  OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"
  OPTS+=" -m ${VMMEMMB}M" #  -mem-path /dev/hugepages"
  OPTS+=" -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -global kvm-pit.lost_tick_policy=discard "
  OPTS+=" -chardev socket,id=chrtpm,path=$configDataFolder/${VMID}/tpm.sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
  OPTS+=" -device virtio-serial-pci,id=virtio-serial0 -chardev socket,id=guestagent,path=/tmp/qga.sock,server,nowait -device virtserialport,chardev=guestagent,name=org.qemu.guest_agent.0"
  if [ -z "$VNCLISTEN" ]; then
    OPTS+=" -nographic -vga none"
  else
    OPTS+=" -vnc $VNCLISTEN"
  fi
  if [ ! -z "$VMCPU" ] && [ ! -z "$CPUTHREADS" ]; then
    local TMPALLCORES=$(echo $VMCPU | sed 's/,/ /g'|wc -w)
    local TMPCORES=$(echo ${TMPALLCORES}/${CPUTHREADS} | bc)
    OPTS+=" -smp threads=${CPUTHREADS},cores=${TMPCORES}"
  fi
  if [ ! -z "$VMBIOS" ] && [ ! -z "$VMBIOS_VARS" ]; then
    OPTS+=" -drive if=pflash,format=raw,readonly=on,file=${VMBIOS} -drive if=pflash,format=raw,file=${VMBIOS_VARS}"
  fi

  if [ ! -z "$VMHARDDISK" ]; then
    COUNT=0
    THREADCOUNT=0
    for DISK in $VMHARDDISK; do
      OPTS+=" -object iothread,id=iothread${THREADCOUNT}"
      OPTS+=" -object iothread,id=iothread$(( ${THREADCOUNT} + 1 ))"
      OPTS+=" -drive if=none,cache=none,aio=native,discard=unmap,detect-zeroes=unmap,format=raw,file=${DISK},id=drive${COUNT}"
      OPTS+=" --device '{\"driver\":\"virtio-blk-pci\",\"iothread-vq-mapping\":[{\"iothread\":\"iothread${THREADCOUNT}\"},{\"iothread\":\"iothread$(( ${THREADCOUNT} + 1 ))\"}],\"drive\":\"drive${COUNT}\",\"queue-size\":1024,\"config-wce\":false}'"
      let COUNT=COUNT+1
      let THREADCOUNT=THREADCOUNT+2
    done
  fi
  if [ ! -z "$VMCDROM" ]; then
    for CD in $VMCDROM; do
      OPTS+=" -drive file=${CD},media=cdrom"
    done
  fi
  if [ ! -z "$VMPASSTHROUGHPCIDEVICES" ]; then
    # Use PCIE bus
    OPTS+=" -device pcie-root-port,id=root_port1,chassis=0,slot=0,bus=pcie.0"
    loopCount=0
    for VMPASSTHROUGHPCIDEVICE in $VMPASSTHROUGHPCIDEVICES; do
      if isGPU $VMPASSTHROUGHPCIDEVICE; then # If this is a GPU adapter, set multifunction=on
        [ ! -z "$VMGPUROM" ] && GPUROMSTRING=",romfile=$VMGPUROM" || GPUROMSTRING=""
        OPTS+=" --device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE},bus=root_port1,addr=00.${loopCount},multifunction=on$GPUROMSTRING"
      else
        OPTS+=" -device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE},bus=root_port1,addr=00.${loopCount}"
      fi
      let loopCount++
    done
  fi
  if [ ! -z "$VMPASSTHROUGHUSBDEVICES" ]; then
    for VMPASSTHROUGHUSBDEVICE in $VMPASSTHROUGHUSBDEVICES; do
      local USBVendor=$(cut -d : -f 1 <<<$VMPASSTHROUGHUSBDEVICE)
      local USBProduct=$(cut -d : -f 2 <<<$VMPASSTHROUGHUSBDEVICE)
      OPTS+=" -device qemu-xhci -device usb-host,vendorid=0x${USBVendor},productid=0x${USBProduct}"
    done
  fi
  if [ ! -z "$VMCPUOPTS" ]; then
    OPTS+=" -cpu host,${VMCPUOPTS}"
  else
    OPTS+=" -cpu host "
  fi
  doOut "clear"
  setupHugePages $VMMEMMB |& doOut
  echo "QEMU Options $OPTS" | doOut
  realTimeTune
  ( reloadPCIDevices "$VMPASSTHROUGHPCIDEVICES" ; echo "Starting QEMU" ; eval qemu-system-x86_64 $OPTS 2>&1 ) 2>&1 | doOut &
  vCPUpin &
  doOut showlog
}

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
    while read device; do
      local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
      local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
      if [ -e /sys/bus/pci/devices/0000:${device}/driver/unbind ]; then
        echo "0000:${device}" >/sys/bus/pci/devices/0000:${device}/driver/unbind 2>&1 | doOut
        sleep 1
      fi
      echo "Removing $pciVendor $pciDevice from vfio-pci" | doOut
      echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/remove_id 2>&1 | doOut
      sleep 1
      if [ -e "/sys/bus/pci/devices/0000:${device}/reset" ]; then
        echo "Resetting $device" | doOut
        echo 1 >"/sys/bus/pci/devices/0000:${device}/reset" 2>&1 | doOut
        sleep 1
      fi
    done <<< "$@"

    while read device; do
      local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
      local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
      echo "Registrating vfio-pci on ${pciVendor}:${pciDevice}" | doOut
      echo "$pciVendor $pciDevice" >/sys/bus/pci/drivers/vfio-pci/new_id 2>&1 | doOut
      sleep 1
    done <<< "$@"
  fi
}

setupCustomStartStopScript() {
  if [ -e $configCustomStartStopScript ]; then
    vi $configCustomStartStopScript
  else
    cat <<-'EOF' > $configCustomStartStopScript
customVMStart() {
  devices=$(cat $configPassthroughPCIDevices)
  echo Do stuff with $devices
}

customVMStop() {
  echo Do stuff here
}
EOF
  fi
  vi $configCustomStartStopScript
}

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


vCPUpin() {
  sleep 40 # Let QEMU start threads

  # Get QEMU threads
  QEMUTHREADS=$( ( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 10 nc localhost 4444 )| tail -n1 | jq '.return[] | ."thread-id"' )
  echo "Found QEMU threads: $QEMUTHREADS" | doOut
  if [ $CPUTHREADS -gt 1 ]; then
    # Group CPUs together
    LOOPCOUNT=0
    for tmpCPU in $(echo $VMCPU | tr , '\n'); do
      if echo "$tmpCPUPROCESSED" | grep ",${tmpCPU}," -q; then
        continue
      fi
      # First find the physical core
      PHYCORE=$(lscpu -p|grep ^${tmpCPU}, | cut -d , -f 2)
      [ -z "$PHYCORE" ] && continue

      # Find the sibling
      CPUSIBLING=$(lscpu -p|grep -E "(^[0-9]+),$PHYCORE," | grep -v ^$tmpCPU, | cut -d , -f 1 | head -n 1)
      [ -z "$CPUSIBLING" ] && continue
      echo "Pinning for CPU Pair $tmpCPU + $CPUSIBLING" | doOut
      
      # Find QEMU theads for core
      tmpQEMUTHREADS=$( ( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 2 nc localhost 4444 )| tail -n1 | jq ".return[] | select(.\"props\".\"core-id\" == $LOOPCOUNT) | .\"thread-id\"" )
      tmpThread=0
      for tmpQEMUTHREAD in $tmpQEMUTHREADS; do
        if [ "$tmpThread" == 1 ]; then
          taskset -pc ${CPUSIBLING} $tmpQEMUTHREAD | doOut
        else
          taskset -pc ${tmpCPU} $tmpQEMUTHREAD | doOut
        fi
        tmpThread=1
      done

      let LOOPCOUNT++
      tmpCPUPROCESSED+=",$tmpCPU,"
      tmpCPUPROCESSED+=",$CPUSIBLING,"
    done
  else
    LOOPCOUNT=0
    for tmpCPU in $(echo $VMCPU | tr , '\n'); do
      # First fine the physical core
      echo "Pinning for CPU  $tmpCPU" | doOut
      
      # Find QEMU theads for core
      tmpQEMUTHREADS=$( ( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 2 nc localhost 4444 )| tail -n1 | jq ".return[] | select(.\"props\".\"core-id\" == $LOOPCOUNT) | .\"thread-id\"" )
      for tmpQEMUTHREAD in $tmpQEMUTHREADS; do
          taskset -pc ${tmpCPU} $tmpQEMUTHREAD | doOut
      done

      let LOOPCOUNT++
      tmpCPUPROCESSED+=",$tmpCPU,"
    done
  fi

  # Do IRQ Affinity
  IRQAffinity
}

doKernelCPUTopology() {
  if [ ! -e $configCPUTopology ]; then
    err "No cpuTopology file found"
  else
    source $configCPUTopology
  fi
  clear
  mount -oremount,rw /media/usb/ || err "Cannot remount /media/usb"
  cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old || err "Cannot copy grub.cfg"
  cat /media/usb/boot/grub/grub.cfg.old | sed '/^menuentry "DKVM"/,/^}/s/\(linux.*\)isolcpus=[^ ]*/\1isolcpus='$VMCPU'/; \
                                          /isolcpus=[^ ]*/!s/\(linux.*\)$/\1 isolcpus='$VMCPU'/; \
                                          s/\(linux.*\)nohz_full=[^ ]*/\1nohz_full='$VMCPU'/; \
                                          /nohz_full=[^ ]*/!s/\(linux.*\)$/\1 nohz_full='$VMCPU'/; \
                                          s/\(linux.*\)rcu_nocbs=[^ ]*/\1rcu_nocbs='$VMCPU'/; \
                                          /rcu_nocbs=[^ ]*/!s/\(linux.*\)$/\1 rcu_nocbs='$VMCPU'/' > /media/usb/boot/grub/grub.cfg
  mount -oremount,ro /media/usb/ || err "Cannot remount /media/usb"
  dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 20 60
}

IRQAffinity() {
  # Replaced with irqbalance
  source $configCPUTopology

  # irqbalance will honor isolcpu - so everything will go on $HOSTCPU by default.
  # Manually exclude VFIO devices, as they prefer to be on the same core as the VM
  IRQLine=""
  for IRQ in $(grep vfio /proc/interrupts | cut -d ":" -f 1 | sed 's/ //g'); do
    IRQLine+=" --banirq=$IRQ"
  done
  echo "VFIO IRQ bans for irqbalance: $IRQLine" | doOut
  /usr/sbin/irqbalance --oneshot $IRQLine | doOut
}

doWarnDKVMData() {
  local txt
  txt+="DKVM relies on a mountpoint to store VM BIOS and TPM data.\n"
  txt+="DKVMData mountpoint should be formatted and mounted at /media/dkvmdata.\n"
  txt+="As an example could be a LVM volume with a ext4 filesystem.\n\n"
  txt+="Please use CTRL+ArrowRight to get a root-console, and setup\n"
  txt+="a mountpoint for DKVMData. (You might want to adjust /etc/fstab too)\n"

  dialog --cr-wrap --clear --msgbox "$txt" 20 80

  exit 1
}

mountpoint $configDataFolder || doWarnDKVMData

[ ! -e $configPassthroughUSBDevices ] && doUSBConfig
[ ! -e $configPassthroughPCIDevices ] && doPCIConfig
[ ! -e $configCPUTopology ] && writeOptimalCPULayout && vi $configCPUTopology && doKernelCPUTopology && doSaveChanges

showMainMenu
doSelect
