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

configPassthroughPCIDevices=passthroughPCIDevices
configPassthroughUSBDevices=passthroughUSB
configDataFolder=/media/dkvmdata

err() {
  echo "ERROR $@"
  exit 1
}

buildMenuItemVMs() {
  menuItemsVMs=""
  itemNumber=0
  for VM in $(ls -1 $configDataFolder/|grep -v lost+found); do
    itemName=$VM
    menuItemsVMs[$itemNumber]="$itemName"
    let itemNumber++
  done
}

doStartTPM() {
  # Cleanup if an old was running
  if [ -n "$tpmPID" ]; then 
    kill $tpmPID >/dev/null 2>&1
    find /tmp/${tpmUUID}/ -type f -delete
    rmdir /tmp/${tpmUUID}
  fi
  tpmUUID=$(uuidgen)
  mkdir -p /tmp/${tpmUUID}
  /usr/bin/swtpm socket --tpmstate dir=/tmp/${tpmUUID},mode=0600 --ctrl type=unixio,path=/tmp/${tpmUUID}.sock,mode=0600 --log file=/tmp/tpm-${tpmUUID}.log --terminate --tpm2 &
  tpmPID=$!
}

doShowLog() {
  # CPU monitor
  (
    logFreq=cpu-freq.log
    IFS="
"
>$logFreq
    while [ true ]; do
      # Get current Mhz for all cores
      MHz=$(grep -i MHz /proc/cpuinfo | sed 's/\..*//g')
      coreCount=0
      for line in $MHz; do
        freq=$(echo "$line" | awk '{print $4}')
        echo "Core $coreCount @ $freq Mhz" >>$logFreq
        let coreCount++
      done
      # Also write qemu status
>qemu-running.log
      if pgrep -f qemu-system-x86_64 > /dev/null; then
        echo "Running @ $(pgrep qemu-system-x86_64)" > qemu-running.log
      else
        echo "Stopped" > qemu-running.log
      fi

      sleep 5
      >$logFreq
    done
  ) &
  pidofFreq=$!

  (
    IFS=$OLDIFS
    logUtil=cpu-util.log
    CPUs=$(cat /proc/stat | grep ^cpu | awk '{print $1}')
    getCounter() {
      local counters="$1"
      local counter="$2"
      echo $(echo $counters | awk "{print \$$counter"})
    }

    counterName=(user nice system idle iowait irq softirq steal guest guest_nice)
    declare -A lastCounters

    while :; do
      headerStr="CPU"
      for name in ${counterName[@]}; do
        headerStr+="\t${name}"
      done
      echo -e $headerStr >$logUtil
      first=1
      for CPU in $CPUs; do
        echo -en "$CPU" >>$logUtil
        counters=$(grep ^$CPU /proc/stat | head -n 1 | sed "s/$CPU//" | awk '{$1=$1};1')
        counterSum=$(echo -e "$counters" | sed 's/ /+/g' | bc -l)
        tmpLastCounters=(${lastCounters[$CPU]})

        lastCountersSum=$(echo -e "${tmpLastCounters[@]}" | sed 's/ /+/g' | bc -l)
        sumDelta=$(echo "$counterSum - $lastCountersSum" | bc -l)

        # Loop over counters
        tmpCountNr=0
        for counter in $counters; do
          # Get counter delta

          tmpCounterDelta=$(echo "$counter - ${tmpLastCounters[$tmpCountNr]}" | bc -l)
          tmpCounterDeltaPercent=$(LC_NUMERIC="en_US.UTF-8" printf %0.2f $(echo "100 * ($tmpCounterDelta / $sumDelta)" | bc -l))
          echo -en "\t$tmpCounterDeltaPercent" >>$logUtil

          let tmpCountNr++
        done

        # Remember counters for next iteration
        lastCounters[$CPU]="$counters"
        first=0
        echo >>$logUtil
      done
      sleep 5
    done
  ) 2>/dev/null &
  pidofCpuUtil=$!
  # Reset logfiles
>cpu-freq.log
>cpu-util.log
>qemu-running.log
  dialog --backtitle "$backtitle" \
    --title Log --begin 2 2 --tailboxbg dkvm.log 18 124 \
    --and-widget --title "CPU" --begin 21 2 --tailboxbg cpu-freq.log 20 22 \
    --and-widget --title "System load" --begin 21 26 --tailboxbg cpu-util.log 20 100 \
    --and-widget --title "Qemu status" --begin 42 2 --tailboxbg qemu-running.log 4 22 \
    --and-widget --begin 3 112 --keep-window --msgbox "Exit" 5 10 2>dialog.err

  kill -9 $pidofFreq $pidofCpuUtil 2>&1 > /dev/null
  clear
  exit
}

doOut() {
  local TAILFILE=dkvm.log
  if [ "$1" == "clear" ]; then
    rm -f "$TAILFILE"
    touch "$TAILFILE"
  elif [ "$1" == "showlog" ]; then
    #dialog --backtitle "$backtitle" --tailbox "$TAILFILE" 25 75
    doShowLog
    # When exited, kill any remaining qemu
    killall qemu-system-x86_64
    sleep 2
    killall -9 qemu-system-x86_64
    reset
    clear
    killall dkvmmenu.sh
    exit
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
  echo "$(ls -1 dkvm_vmconfig.[0-9] | sed 's/.*\.//' | tail -n 1)"
}

doAddVM() {
  # Find next dkvm_vmconfig.X
  local lastVMConfig=$(getLastVMConfig)
  let "lastVMConfig++"
  cp dkvm_vmconfig.sam dkvm_vmconfig.${lastVMConfig}
  vi dkvm_vmconfig.${lastVMConfig}

  showMainMenu && doSelect
}

doEditVM() {
  local lastVMConfig=$(getLastVMConfig)
  menuStr=""
  for i in $(seq 0 $lastVMConfig); do
    local name=$(grep NAME dkvm_vmconfig.${i} | sed 's/NAME=//')
    local menuStr="$menuStr $i '$name'"
  done
  local menuAnswer=$(eval "dialog --backtitle "'$backtitle'" --menu 'Choose VM' 20 30 20 $menuStr" --stdout)

  vi dkvm_vmconfig.${menuAnswer}

  showMainMenu && doSelect

}

setupCPULayout() {
  if [ ! -e cpuTopology ]; then
    writeOptimalCPULayout
  fi
  source cpuTopology
}

writeOptimalCPULayout() {
  # Pick first core, and any SMT as the host core
  # TODO: What if we have more sockets / CCX?
  HOSTCPU=$(lscpu -p| grep -E '(^[0-9]+),0' | cut -d, -f1 | tr '\n' ',')
  VMCPU=$(lscpu -p| grep -v \# | grep -v -E '(^[0-9]+),0' | cut -d, -f1 | tr '\n' ',')
  CPUTHREADS=$(lscpu |grep Thread | cut -d: -f2|tr -d ' ')
  if [ ! -z "$HOSTCPU" ] && [ ! -z "$VMCPU" ]; then  
  cat > cpuTopology <<EOF
# This file is auto-generated upon first start-up.
# To regenerate, just delete this file
#
# Host CPUs reserves for Host OS.
# Recommended is to use 1 CPU (inclusing SMT/Hyperthreading core)
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
  local USBDevices=$(lsusb)
  dialogStr=""

  for USBDevice in $USBDevices; do
    USBId=$(grep -Eo '(([0-9]|[a-f]){4}|:){3}' <<<$USBDevice)
    USBName=$(cut -d : -f 2- <<<$USBDevice | sed "s/.*$USBId //g")
    dialogStr+="\"$USBId\" \"$USBName\" off "
  done
  selectedDevices=$(eval dialog --stdout --scrollbar --checklist \"Select USB devices for passthrough\" 40 80 70 $dialogStr | tr ' ' '\n')

  [ -z "$selectedDevices" ] && break

  echo "$selectedDevices" > $configPassthroughUSB
}

updateGrub() {
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

  [ -z "$selectedDevices" ] && break

  for selectedDevice in $selectedDevices; do
      vfioIds+=$(lspci -n -s $selectedDevice | grep -Eo '(([0-9]|[a-f]){4}|:){3}'),
  done

  updateGrub vfio-pci.ids $(tr ' ' ',' <<<$vfioIds | sed 's/,$//')
  doSaveChanges
  IFS=$OLDIFS
}

doSaveChanges() {
  local changesTxt="Changes saved...
$(lbu diff)
$(lbu commit)"

  dialog --backtitle "$backtitle" --msgbox "$changesTxt" 30 80

  showMainMenu && doSelect
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
    menuOptions[6]="Save changes"
    
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
      setupCPULayout
      vim cpuTopology
      configureKernelCPUTopology
    elif [ "$menuAnswer" == "4" ]; then
      doPCIConfig
    elif [ "$menuAnswer" == "5" ]; then
      doUSBConfig
    elif [ "$menuAnswer" == "6" ]; then
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

mainHandlerVM() {
  clear
  doStartTPM
  doOut "clear"
  #local configFile="dkvm_vmconfig.${1}"
  local configFile=$configDataFolder/${1}/dkvm_vmconfig

  local VMNAME="$(getConfigItem $configFile NAME)"
  local VMHARDDISK=$(getConfigItem $configFile HARDDISK)
  local VMCDROM=$(getConfigItem $configFile CDROM)
  local VMPASSTHROUGHPCIDEVICES=$(cat $configPassthroughPCIDevices)
  local VMPASSTHROUGHUSBDEVICES=$(cat $configPassthroughUSBDevices)
  local VMBIOS=$(getConfigItem $configFile BIOS)
  local VMBIOS_VARS=$(getConfigItem $configFile BIOS_VARS)
  local VMMEM=$(getConfigItem $configFile MEM)
  local VMMAC=$(getConfigItem $configFile MAC)
  local VMCPUOPTS=$(getConfigItem $configFile CPUOPTS)
  local VMEXTRA=$(getConfigItem $configFile EXTRA)

  # Build qemu command
  OPTS="-nodefaults -no-user-config -accel accel=kvm,kernel-irqchip=on -machine q35,mem-merge=off,vmport=off,dump-guest-core=off -qmp tcp:localhost:4444,server,nowait "
  OPTS+=" -mem-prealloc -overcommit mem-lock=on -rtc base=localtime,clock=vm,driftfix=slew -serial none -parallel none "
  OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"
  OPTS+=" -m $VMMEM"
  OPTS+=" -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -global kvm-pit.lost_tick_policy=discard "
  OPTS+="  -chardev socket,id=chrtpm,path=/tmp/${tpmUUID}.sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0" #TOOD We need a persistent config
  OPTS+=" $VMEXTRA "
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
    for DISK in $VMHARDDISK; do
      # Do we need virtio,id=driveX here ?
      #OPTS+=" -drive if=virtio,cache=none,aio=native,format=raw,file=${DISK}"
      #OPTS+=" -drive if=virtio,format=raw,file=${DISK}"
      OPTS+=" -drive if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=raw,file=${DISK}"
      #
      #OPTS+=" -drive if=none,id=drive${COUNT},cache=directsync,aio=native,format=raw,file=${DISK} -device virtio-blk-pci,drive=drive${COUNT},scsi=off"
      let COUNT=COUNT+1
    done
  fi
  if [ ! -z "$VMCDROM" ]; then
    for CD in $VMCDROM; do
      OPTS+=" -drive file=${CD},media=cdrom"
    done
  fi
  if [ ! -z "$VMPASSTHROUGHPCIDEVICES" ]; then
    # Use PCIE bus
    loopCount=0
    for VMPASSTHROUGHPCIDEVICE in $VMPASSTHROUGHPCIDEVICES; do
    let loopCount++
      if isGPU $VMPASSTHROUGHPCIDEVICE; then # If this is a GPU adapter, set multifunction=on
        OPTS+=" -device pcie-root-port,multifunction=on,slot=$loopCount,bus=pcie.0 -device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE}"
      else
        OPTS+=" -device pcie-root-port,slot=$loopCount,bus=pcie.0 -device vfio-pci,host=${VMPASSTHROUGHPCIDEVICE}"
      fi
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
  echo "QEMU Options $OPTS" | doOut
  IRQAffinity
  realTimeTune
  ( reloadPCIDevices "$VMPASSTHROUGHPCIDEVICES" ; echo "Starting QEMU" ; eval qemu-system-x86_64 $OPTS 2>&1 ) 2>&1 | doOut &
  vCPUpin &
  doOut showlog
}

reloadPCIDevices() {
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
      echo "Resetting $device"
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
  sleep 10 # Let QEMU start threads
  # Load topology setup
  source cpuTopology

  # Get QEMU threads
  QEMUTHREADS=$( ( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus-fast" }' | timeout 2 nc localhost 4444 )| tail -n1 | jq '.return[] | ."thread-id"' )
  echo "Found QEMU threads: $QEMUTHREADS" | doOut
  if [ $CPUTHREADS -gt 1 ]; then
    # Group CPUs together
    LOOPCOUNT=0
    for tmpCPU in $(echo $VMCPU | tr , '\n'); do
      if echo "$tmpCPUPROCESSED" | grep ",${tmpCPU}," -q; then
        continue
      fi
      # Find siblling
      # First fine the physical core
      PHYCORE=$(lscpu -p|grep ^${tmpCPU}, | cut -d , -f 2)
      [ -z "$PHYCORE" ] && continue

      # Find the sibling
      CPUSIBLING=$(lscpu -p|grep -E "(^[0-9]+),$PHYCORE" | grep -v ^$tmpCPU | cut -d , -f 1)
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
}

configureKernelCPUTopology() {
  if [ ! -e cpuTopology ]; then
    err "No cpuTopology file found"
  else
    source cpuTopology
  fi
  clear
  mount -oremount,rw /media/usb/ || err "Cannot remount /media/usb"
  cp /media/usb/boot/grub/grub.cfg /media/usb/boot/grub/grub.cfg.old || err "Cannot copy grub.cfg"
  cat /media/usb/boot/grub/grub.cfg.old | sed -e "s%\(isolcpus=\)[^[:space:]]\+%\1${VMCPU}%g" -e "s%\(nohz_full=\)[^[:space:]]\+%\1${VMCPU}%g" -e "s%\(rcu_nocbs=\)[^[:space:]]\+%\1${VMCPU}%g" > /media/usb/boot/grub/grub.cfg
  mount -oremount,ro /media/usb/ || err "Cannot remount /media/usb"
  dialog --title "Restart required" --msgbox "You need to restart your computer for the kernel settings to take effect." 20 60
}

IRQAffinity() {
  source cpuTopology
  IRQCORE=$HOSTCPU
  echo "IRQ Cores: $IRQCORE" | doOut

  # Move all irq away from VM CPUs
  for IRQ in $(cat /proc/interrupts | grep "^ ..:" | grep -v "timer\|rtc\|acpi\|dmar\|mei_me" | awk '{print $1}' | tr -d ':'); do
    if [ -d /proc/irq/${IRQ} ]; then
      echo "Moving IRQ $IRQ to $IRQCORE" | doOut
      ( echo "$IRQCORE" > /proc/irq/${IRQ}/smp_affinity_list 2>&1 ) | doOut
    fi
  done

  # Also move all other threads we can away from the VM CPUs
  echo "Moving non-vm relates tasks to $IRQCORE" | doOut
  for PID in $(ps | awk '{print $1}' | grep -v PID); do
    taskset -pc $IRQCORE $PID 2>/dev/null | doOut
  done
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

setupCPULayout
[ ! -e $configPassthroughUSB ] && doUSBConfig
[ ! -e $configPassthroughPCIDevices ] && doPCIConfig
mountpoint -q /media/dkvmdata || doWarnDKVMData

showMainMenu
doSelect
