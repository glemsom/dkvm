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
export configCPUOptions=$configDataFolder/cpuOptions
export configCustomStartStopScript=$configDataFolder/customStartStopScript

configBIOSCODE=/usr/share/OVMF/OVMF_CODE.fd
configBIOSVARS=/usr/share/OVMF/OVMF_VARS.fd

configReservedMemMB=$(( 1024 * 4 )) # 4GB


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
    --title "Desktop VM" --prgbox "./dkvmlog.sh $configPassthroughUSBDevices $configPassthroughPCIDevices " 25 80
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
  local menuStr="$tmpFix --title '$title' --backtitle '$backtitle' --no-tags --no-cancel --menu 'Select option' 0 0 20 $menuStr --stdout"
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
    local menuAnswer=$(eval "dialog --backtitle "'$backtitle'" --menu 'Choose VM to edit' 0 0 20 $menuStr" --stdout)

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

doUSBConfig() {
  echo "USB Config" | doLog
  local USBDevices=$(lsusb 2>/dev/null)
  dialogStr=""

  for USBDevice in $USBDevices; do
    USBId=$(grep -Eo '(([0-9]|[a-f]){4}|:){3}' <<<$USBDevice)
    USBName=$(cut -d : -f 2- <<<$USBDevice | sed "s/.*$USBId //g")
    dialogStr+="\"$USBId\" \"$USBName\" off "
  done
  selectedDevices=$(eval dialog --stdout --scrollbar --checklist \"Select USB devices for passthrough\" 0 0 70 $dialogStr | tr ' ' '\n')

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
    dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 0 0
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

  selectedDevices=$(eval dialog --stdout --scrollbar --checklist \"Select PCI devices for passthrough\" 0 0 70 $dialogStr | tr ' ' '\n')
  echo "$selectedDevices" > $configPassthroughPCIDevices

  [ -z "$selectedDevices" ] && exit 1

  for selectedDevice in $selectedDevices; do
      vfioIds+=$(lspci -n -s $selectedDevice | grep -Eo '(([0-9]|[a-f]){4}|:){3}'),
  done
  dialog --yesno "Add vfio-pci.ids to /etc/modprobe.d/vfio?" 0 0
  if [ "$?" -eq "0" ]; then
    doUpdateModprobe $(tr ' ' ',' <<<$vfioIds | sed 's/,$//')
  fi
  dialog --yesno "Add vfio-pci.ids to kernel commandline?" 0 0
  if [ "$?" -eq "0" ]; then
    doUpdateGrub vfio-pci.ids $(tr ' ' ',' <<<$vfioIds | sed 's/,$//')
  fi
  doSaveChanges
  
  
  IFS=$OLDIFS
}

doSaveChanges() {
  local changesTxt="Changes saved...
$(lbu commit)"
  dialog --backtitle "$backtitle" --msgbox "$changesTxt" 0 0
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

realTimeTune() {
  # Reduce vmstat collection
  [ -e /proc/sys/vm/stat_interval ] && echo 300 >/proc/sys/vm/stat_interval 2>/dev/null
  # Disable watchdog
  [ -e proc/sys/kernel/watchdog ] && echo 0 >/proc/sys/kernel/watchdog 2>/dev/null
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
  OPTS="-name \"$VMNAME\",debug-threads=on -nodefaults -no-user-config -accel accel=kvm,kernel-irqchip=split -machine q35,mem-merge=off,vmport=off,dump-guest-core=off -qmp tcp:localhost:4444,server,nowait "
  #OPTS+=" -mem-prealloc -overcommit mem-lock=on,cpu-pm=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
  OPTS+=" -mem-prealloc -overcommit mem-lock=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
  OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"
  OPTS+=" -m ${VMMEMMB}M -mem-path /dev/hugepages"
  OPTS+=" -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -global kvm-pit.lost_tick_policy=discard "
  OPTS+=" -chardev socket,id=chrtpm,path=$configDataFolder/${VMID}/tpm.sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
  OPTS+=" -device virtio-serial-pci,id=virtio-serial0 -chardev socket,id=guestagent,path=/tmp/qga.sock,server,nowait -device virtserialport,chardev=guestagent,name=org.qemu.guest_agent.0"
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
  sleep 5 && addCPUs $VMCPU 2>&1 | doOut && continueVM &
  doOut showlog
}

continueVM() {
  echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "cont" }' | timeout 2 nc localhost 4444 > /dev/null 2>&1
}


getvCorePid() {
  local COREID=$1
  local DIEID=$2
  local THREADID=$3
  local PIDS=$(echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 0.5 nc localhost 4444 | tail -n1 | jq ".return[] | select(.\"props\".\"core-id\" == $COREID and .\"props\".\"die-id\" == $DIEID and .\"props\".\"thread-id\" == $THREADID) | .\"thread-id\"") 2>/dev/null
  echo "$PIDS"
}

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


addvCore() {
    local COREID=$1
    local DIE_ID=$2
    local THREAD_ID=$3
    local SOCKET=$4
    local HOSTCORE=$5
    echo "Adding vCore: Host Core Id: $HOSTCORE, ID=$COREID, Die ID= $DIE_ID, vCore ID=$COREID, vThread ID=$THREAD_ID"
    echo -e '{ "execute": "qmp_capabilities" }
    { "execute": "device_add", "arguments": { 
        "core-id": '$COREID', 
        "driver": "host-x86_64-cpu", 
        "id": "cpu-'${HOSTCORE}'", 
        "die-id": '$DIE_ID', 
        "socket-id": '$SOCKET', 
        "thread-id": '$THREAD_ID' } 
    }' | timeout 1 nc localhost 4444 | grep error
}

printarr() { declare -n __p="$1"; for k in "${!__p[@]}"; do printf "%s=%s\n" "$k" "${__p[$k]}" ; done ;  } 

addCPUs() {
  declare -A PROCESSED_SIBLING_LIST

  # The host cores to add to the VM as virtual cores
  echo "Adding CPUs for $1"

  OLDIFS=$IFS

  # Add cores to array of cores
  IFS=','
  read -r -a TMPHOSTCORES <<< $1
  IFS=$OLDIFS

  # Cleanup first core from array, as it is already pre-added to the VM
  if [ ${#TMPHOSTCORES[@]} -gt 0 ]; then
    TMPSIBLING=$(cat /sys/devices/system/cpu/cpu${TMPHOSTCORES[0]}/topology/thread_siblings_list | cut -d , -f2)
    FIRST_CORE=${TMPHOSTCORES[0]}
    # Get PID for core
    TMPPID=$(getvCorePid $FIRST_CORE 0 0)
    taskset -pc $FIRST_CORE $TMPPID
    PROCESSED_SIBLING_LIST[$FIRST_CORE,$TMPSIBLING]=0
    echo Already added core $FIRST_CORE with sibling $TMPSIBLING
    echo Processed siblings: $(printarr PROCESSED_SIBLING_LIST)
    unset 'TMPHOSTCORES[0]'
    HOSTCORES=("${TMPHOSTCORES[@]}") # Re-index the array
  fi
  echo "First core added"

  # Get number of dies in the host system
  DIES=$(cat /sys/devices/system/cpu/cpu*/topology/die_id | sort | uniq)

  VCORE=1 # Start from 1, as 0 is already attached to the VM

  for DIE in $DIES; do
    echo "Processing for die $DIE"
    for HOSTCORE in ${HOSTCORES[@]}; do
      local CUR_DIE_ID=$(cat /sys/devices/system/cpu/cpu${HOSTCORE}/topology/die_id)
      if [ $CUR_DIE_ID == $DIE ]; then
        echo "Current seen siblings:"
        printarr PROCESSED_SIBLING_LIST
        SIBLING_LIST=$(cat /sys/devices/system/cpu/cpu${HOSTCORE}/topology/thread_siblings_list)
        echo "Processing hostcore $HOSTCORE @ die $DIE with siblings_list $SIBLING_LIST"
        if [ ! -z ${PROCESSED_SIBLING_LIST[$SIBLING_LIST]} ]; then
          echo "    Host core $HOSTCORE already processed as sibling $SIBLING_LIST. Virtual core of sibling: ${PROCESSED_SIBLING_LIST[$SIBLING_LIST]}"
          addvCore ${PROCESSED_SIBLING_LIST[$SIBLING_LIST]} $CUR_DIE_ID 1 0 $HOSTCORE
          # Get the PID for the newly added vCore
          TMPPID=$(getvCorePid ${PROCESSED_SIBLING_LIST[$SIBLING_LIST]} $CUR_DIE_ID 1)
          taskset -pc $HOSTCORE $TMPPID
        else
          echo "    Host core $HOSTCORE not seen before as $SIBLING_LIST"
          echo "Result from sibling check:" ${PROCESSED_SIBLING_LIST[$SIBLING_LIST]}
          # Add this as-is to the VM
          addvCore $VCORE $CUR_DIE_ID 0 0 $HOSTCORE
          PROCESSED_SIBLING_LIST[$SIBLING_LIST]=$VCORE
          TMPPID=$(getvCorePid $VCORE $CUR_DIE_ID 0)
          taskset -pc $HOSTCORE $TMPPID
          let VCORE++
        fi
      fi
    done
    # Reset VCORE for next die (QEMU expects core_id to be reset)
    VCORE=0
  done
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
  dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 0 0
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

  dialog --cr-wrap --clear --msgbox "$txt" 0 0

  exit 1
}

doEditCPUOptions() {
  prevChoice=""
  if [ -e $configCPUOptions ]; then
    prevChoice=$(cat $configCPUOptions)
  fi

  # Setup CPU options
  local options=()
  for opt in "kvm=off" "hv-vendor-id=dkvm" "hv-frequencies" "hv-relaxed" \
            "hv-reset" "hv-runtime" "hv-spinlocks=0x1fff" "hv-stimer" "hv-synic" \
            "hv-time" "hv-vapic" "hv-vpindex" "topoext=on" "l3-cache=on" "x2apic=on"; do
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
    esac

    state=off
    for prev in $prevChoice; do
      if [ $prev = $opt ]; then
        state=on
      fi
    done

    options+=($opt $desc $state)
  done

  choice=$(dialog --checklist "Select CPU Options:" 20 70 8 "${options[@]}" 2>&1 >/dev/tty)

  echo $choice | tr ' ' '\n'> $configCPUOptions
}

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
