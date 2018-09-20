#!/bin/bash
# DKVM Menu
# Glenn Sommer <glemsom+dkvm AT gmail.com>


version="0.1.1"
# Change to script directory
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

IFS="
"
declare -a menuItems
declare -a menuItemsType
declare -a menuItemsVMs
menuAnswer=""

err() {
    echo "ERROR $@"
    exit 1
}

buildMenuItemVMs() {
    menuItemsVMs=""
    for cfile in dkvm_vmconfig.[0-9]; do
        if [ "$cfile" == "dkvm_vmconfig.[0-9]" ]; then
            err "No VM configs found. Look at dkvm_vmconfig.sam"
        fi

        # Build VM items for menu
        itemNumber=$(echo "$cfile" | sed 's/.*\.//')
        itemName=$(cat "$cfile" | grep ^NAME | sed 's/NAME=//')
        menuItemsVMs[$itemNumber]="$itemName"
    done
}

doOut() {
    local TAILFILE=dkvm.log
    if [ "$1" == "clear" ]; then
        rm -f "$TAILFILE"
        touch "$TAILFILE"
    elif [ "$1" == "showlog" ]; then
        dialog --backtitle "$backtitle" --tailbox "$TAILFILE" 25 75
        # When exited, kill any remaining qemu
        killall qemu-system-x86_64
        sleep 2
        killall -9 qemu-system-x86_64
        reset
        clear
        killall dkvmmenu.sh
        exit
    else
        cat - >> "$TAILFILE"
    fi
}

buildItems() {

    buildMenuItemVMs

    menuItems=()
    menuItemsType=()

    for vm in ${menuItemsVMs[*]}; do
        menuItems+=("Start $vm")
        menuItemsType+=("VM")
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
    for i in `seq 0 $(( ${#menuItems[@]} - 1 ))`; do
        local menuStr="$menuStr ${menuItemsType[$i]}-${i} '${menuItems[$i]}'"
    done
    local ip=$(ip a | grep "inet " | grep -v "inet 127" | awk '{print $2}')
    backtitle="DKVM @ $ip   Version: $version"
    local menuStr="--title '$title' --backtitle '$backtitle' --no-tags --no-cancel --menu 'Select option' 20 50 20 $menuStr --stdout"
    menuAnswer=$(eval "dialog $menuStr")
    if [ $? -eq 1 ]; then
        err "Main dialog cancled ?!"
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
    for i in `seq 0 $lastVMConfig`; do
        local name=$(grep NAME dkvm_vmconfig.${i} | sed 's/NAME=//')
        local menuStr="$menuStr $i '$name'"
    done
    local menuAnswer=$(eval "dialog --backtitle "'$backtitle'" --menu 'Choose VM' 20 30 20 $menuStr" --stdout)

    vi dkvm_vmconfig.${menuAnswer}

    showMainMenu && doSelect

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
        local menuStr="--title '$title' --backtitle '$backtitle' --no-tags --menu 'Select option' 20 50 20 1 'Add new VM' 2 'Edit VM' 3 'Save Changes' --stdout"
        local menuAnswer=$(eval "dialog $menuStr")

        if [ "$menuAnswer" == "1" ]; then
            doAddVM
        elif [ "$menuAnswer" == "2" ]; then
            doEditVM
        elif [ "$menuAnswer" == "3" ]; then
            doSaveChanges
        fi
        showMainMenu && doSelect
    else
        dialog --msgbox "TODO: Make this work..." 6 60
        showMainMenu && doSelect
    fi
}

realTimeTune() {
    echo -1 > /proc/sys/kernel/sched_rt_period_us
    echo -1 > /proc/sys/kernel/sched_rt_runtime_us
    echo 10 > /proc/sys/vm/stat_interval
    echo 0 > /proc/sys/kernel/watchdog_thresh
}
mainHandlerVM() {
    clear
    doOut "clear"
    local configFile="dkvm_vmconfig.${1}"

    local VMNAME="$(getConfigItem $configFile NAME)"
    local VMHARDDISK=$(getConfigItem $configFile HARDDISK)
    local VMCDROM=$(getConfigItem $configFile CDROM)
    local VMPCIDEVICE=$(getConfigItem $configFile PCIDEVICE)
    local VMBIOS=$(getConfigItem $configFile BIOS)
    local VMBIOS_VARS=$(getConfigItem $configFile BIOS_VARS)
    local VMSOCKETS=$(getConfigItem $configFile SOCKETS)
    local VMCORES=$(getConfigItem $configFile CORES)
    local VMTHREADS=$(getConfigItem $configFile THREADS)
    local VMCORELIST=$(getConfigItem $configFile CORELIST)
    local VMMEM=$(getConfigItem $configFile MEM)
    local VMMAC=$(getConfigItem $configFile MAC)
    local VMCPUOPTS=$(getConfigItem $configFile CPUOPTS)
    local VMEXTRA=$(getConfigItem $configFile EXTRA)


    # Build qemu command
    OPTS="-enable-kvm -nodefaults -machine q35,accel=kvm,kernel_irqchip=on,mem-merge=off -qmp tcp:localhost:4444,server,nowait"
    OPTS+=" -mem-prealloc -realtime mlock=off -rtc base=localtime,clock=host"
    #OPTS+=" -device virtio-net-pci,netdev=net0,mac=$VMMAC -netdev bridge,id=net0"
    #OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"
    OPTS+=" -device e1000,netdev=net0,mac=$VMMAC -netdev bridge,id=net0"
    #OPTS+=" -name $VMNAME"
    OPTS+=" -mem-path /dev/hugepages -m $VMMEM"
    OPTS+=" $VMEXTRA "
    if [ ! -z "$VMSOCKETS" ] && [ ! -z "$VMTHREADS" ] && [ ! -z "$VMCORES" ]; then
        OPTS+=" -smp sockets=${VMSOCKETS},cores=${VMCORES},threads=${VMTHREADS}"
    fi
    if [ ! -z "$VMBIOS" ] && [ ! -z "$VMBIOS_VARS" ]; then
        OPTS+=" -drive if=pflash,format=raw,readonly,file=${VMBIOS} -drive if=pflash,format=raw,file=${VMBIOS_VARS}"
    fi

    if [ ! -z "$VMHARDDISK" ]; then
        COUNT=0
    for DISK in $VMHARDDISK; do
            # Do we need virtio,id=driveX here ?
            #OPTS+=" -drive if=virtio,cache=none,aio=native,format=raw,file=${DISK}"
            OPTS+=" -drive if=virtio,format=raw,file=${DISK}"
        #OPTS+=" -drive if=none,id=drive${COUNT},cache=directsync,aio=native,format=raw,file=${DISK} -device virtio-blk-pci,drive=drive${COUNT},scsi=off"
        let COUNT=COUNT+1
        done
    fi
    if [ ! -z "$VMCDROM" ]; then
        for CD in $VMCDROM; do
            OPTS+=" -drive file=${VMCDROM},media=cdrom"
        done
    fi
    if [ ! -z "$VMPCIDEVICE" ]; then
        for PCIDEVICE in $VMPCIDEVICE; do
            OPTS+=" -device vfio-pci,host=${PCIDEVICE}"
        done
    fi
    if [ ! -z "$VMCPUOPTS" ]; then
        OPTS+=" -cpu host,${VMCPUOPTS}"

    else
        OPTS+=" -cpu host"
    fi
    doOut "clear"
    doOut "showlog" &
    reloadPCIDevices $VMPCIDEVICE
    vCPUpin "$VMCORELIST" &
    #IRQAffinity "$VMCORELIST" &
    #realTimeTune
    echo "Starting qemu..." | doOut
    eval qemu-system-x86_64 $OPTS | doOut
    doOut showlog
}

reloadPCIDevices() {
    local VMPCIDEVICE="$@"
    for PCIDEVICE in $(echo "$VMPCIDEVICE" | tr ' ' '\n') ; do
        PCIDEVICE=$(echo $PCIDEVICE | sed 's/,.*//') # Strip options
        VENDOR=$(cat /sys/bus/pci/devices/0000:${PCIDEVICE}/vendor)
        DEVICE=$(cat /sys/bus/pci/devices/0000:${PCIDEVICE}/device)
        if [ -e /sys/bus/pci/devices/0000:${PCIDEVICE}/driver ]; then
            echo "0000:${PCIDEVICE}" > /sys/bus/pci/devices/0000:${PCIDEVICE}/driver/unbind 2>&1 | doOut
            echo "Unloaded $PCIDEVICE" | doOut
        fi
        sleep 0.5
        if [ -e "/sys/bus/pci/devices/0000:${PCIDEVICE}/reset" ]; then
            echo "Resetting $PCIDEVICE" | doOut
            echo 1 > "/sys/bus/pci/devices/0000:${PCIDEVICE}/reset" 2>&1 | doOut
        fi
        sleep 0.5

        echo "Registrating vfio-pci on ${VENDOR}:${DEVICE}" | doOut
        echo "$VENDOR $DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id 2>&1 | doOut
        sleep 0.5
    done
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
    #sleep 20 # Give QEMU time to start the threads
    local CORELIST="$1"
    echo "Setting CPU affinity using cores: $CORELIST" | doOut
    if timeout --help 2>&1 | grep -q BusyBox; then
        TIMEOUT="-t2"
    else
        TIMEOUT=2
    fi
    if [ -f /media/usb/custom/chrt ]; then
        CHRTCMD=/media/usb/custom/chrt
    else
        CHRTCMD=chrt
    fi
    local THREADS=""

    while [ -z "$THREADS" ]; do
        sleep 5
        THREADS=`( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus" }' | timeout $TIMEOUT nc localhost 4444 | tr , '\n' ) | grep thread_id | cut -d : -f 2 | sed -e 's/}.*//g' -e 's/ //g'`
    done

    echo Threads: $THREADS | doOut

    if [ "$(echo $CORELIST | tr -cd ' ' | wc -c )" -gt $(echo "$THREADS" | wc -l) ]; then
        local USEHT=yes
    else
        local USEHT=no
    fi

    local COUNT=1
    for THREAD_ID in $THREADS; do
        if [ $USEHT == yes ]; then
            NCOUNT=$(( $COUNT + 1 ))
            CURCORE=$(echo $CORELIST | cut -d " " -f $COUNT,$NCOUNT | sed 's/ /,/g')
            COUNTUP=2
        else
            CURCORE=$(echo $CORELIST | cut -d " " -f $COUNT)
            COUNTUP=1
        fi
        echo "Binding $THREAD_ID to $CURCORE" | doOut
        taskset -pc $CURCORE $THREAD_ID 2>&1 | doOut
        echo "Setting SCHED_FIFO priority to $THREAD_ID"  | doOut
        $CHRTCMD -pf 10 $THREAD_ID | doOut
        COUNT=$(( $COUNT + $COUNTUP ))
    done
    
}

IRQAffinity() {
    sleep 5
    local CORELIST="$1"
    local CORELISTCOMMA=$(echo $CORELIST | sed 's/ /,/g')
    local ALLCORES=$(cat /proc/cpuinfo | grep processor | awk '{print $3}')

    for CORE in $ALLCORES; do
        if echo "$CORELIST" | grep $CORE -q ; then
            IRQCORE="${IRQCORE},${CORE}"
        fi
    done
    IRQCORE="${IRQCORE:1}" # Remove first ,

    # Move all irq away from VM CPUs
    for IRQ in `ls -1 /proc/irq/`; do
        if [ -d /proc/irq/${IRQ} ]; then
            echo "$IRQCORE" > /proc/irq/${IRQ}/smp_affinity_list
        fi
    done

     # service interrupts coming from vfio devices on the VM's cores
    for IRQ in $(cat /proc/interrupts | grep vfio | awk '{print $1}' | tr -d :); do
        echo $CORELISTCOMMA > /proc/irq/${IRQ}/smp_affinity_list
    done
}

#buildItems
showMainMenu
doSelect
