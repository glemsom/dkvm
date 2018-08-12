#!/bin/bash
# DKVM Menu
# Glenn Sommer <glemsom+dkvm AT gmail.com>
# Version 0.1 Initial release

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

for cfile in dkvm_vmconfig.*; do
    if [ "$cfile" == "dkvm_vmconfig.*" ]; then
        err "No VM configs found. Look at dkvm_vmconfig.sample"
    fi

    # Build VM items for menu
    itemNumber=$(echo "$cfile" | sed 's/.*\.//')
    itemName=$(cat "$cfile" | grep ^NAME | sed 's/NAME=//')
    menuItemsVMs[$itemNumber]="$itemName"
done

doOut() {
    local TAILFILE=dkvm.log
    if [ "$1" == "clear" ]; then
        rm -f "$TAILFILE"
        touch "$TAILFILE"
    elif [ "$1" == "showlog" ]; then
        dialog --tailbox "$TAILFILE" 20 70
        # When exited, kill any remaining qemu
        kill $PIDOFQEMU
        sleep 10
        kill -9 $PIDOFQEMU
    else
        cat - >> "$TAILFILE"
    fi
}

buildItems() {
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
    local title="DKVM Main menu"
    # build menu
    for i in `seq 0 $(( ${#menuItems[@]} - 1 ))`; do
        menuStr="$menuStr ${menuItemsType[$i]}-${i} '${menuItems[$i]}'"
    done
    local backtitle=$(ip a | grep "inet " | grep -v "inet 127" | awk '{print "DKVM          ip: "$2 " nic: " $7}')
    menuStr="--title '$title' --backtitle '$backtitle' --no-tags --no-cancel --menu 'Select option' 20 50 20 $menuStr --stdout"
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

mainHandlerInternal() {
    local item="$1"
    [ "$1" == "INT_SHELL" ] && /bin//bash
    dialog --msgbox "TODO: Make this work..." 6 60
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
    OPTS+=" -netdev bridge,id=hostnet0 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=$VMMAC"
    #OPTS+=" -device e1000,netdev=net0,mac=$VMMAC -netdev bridge,id=net0"
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
    reloadPCIDevices $VMPCIDEVICE
    vCPUpin "$VMCORELIST" &
    #IRQAffinity "$VMCORELIST" &
    #realTimeTune
    eval qemu-system-x86_64 $OPTS
    PIDOFQEMU=$?!
    doOut showlog
}

reloadPCIDevices() {
    local VMPCIDEVICE="$1"
    for PCIDEVICE in $VMPCIDEVICE; do
        VENDOR=$(cat /sys/bus/pci/devices/0000:${PCIDEVICE}/vendor)
        DEVICE=$(cat /sys/bus/pci/devices/0000:${PCIDEVICE}/device)

        if [ -e /sys/bus/pci/devices/0000:${PCIDEVICE}/driver ]; then
            echo "0000:${PCIDEVICE}" > /sys/bus/pci/devices/0000:${PCIDEVICE}/driver/unbind 2>/dev/null
            echo "Unloaded $PCIDEVICE"
        fi
        sleep 1
        if [ -e "/sys/bus/pci/devices/0000:${PCIDEVICE}/reset" ]; then
            echo "Resetting $PCIDEVICE"
            echo 1 > "/sys/bus/pci/devices/0000:${PCIDEVICE}/reset" 2>/dev/null
        fi
        sleep 1

        echo "Registrating vfio-pci on ${VENDOR}:${DEVICE}"
        echo "$VENDOR $DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id
        sleep 1
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
    sleep 2 # Give QEMU time to start the threads
    local CORELIST="$1"
    echo "Setting CPU affinity using cores: $CORELIST" | doOut
    if timeout --help 2>&1 | grep -q BusyBox; then
        TIMEOUT="-t 2"
    else
        TIMEOUT="2"
    fi
    if [ -f ./chrt ]; then
        CHRTCMD=./chrt
    else
        CHRTCMD=chrt
    fi

    local THREADS=`( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus" }' | timeout $TIMEOUT nc localhost 4444 | tr , '\n' ) | grep thread_id | cut -d : -f 2 | sed -e 's/}.*//g' -e 's/ //g'`
    THREADS="100 
200 
300"

    echo "Threads: $THREADS" | doOut

    if [ "$(echo $CORELIST | tr -cd ' ' | wc -c )" -lt $(echo "$THREADS" | wc -l) ]; then
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
        echo taskset -pc $CURCORE $THREAD_ID 2>&1 | doOut
        echo "Setting SCHED_FIFO priority to $THREAD_ID"  | doOut
        echo $CHRTCMD -pf 20 $THREAD_ID | doOut
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

buildItems
showMainMenu
doSelect
