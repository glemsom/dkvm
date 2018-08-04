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
    local backtitle=$(ip a | grep "inet " | grep -v "inet 127" | awk '{print "DKVM          ip: "$2 " nic: " $9}')
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
    local configFile="dkvm_vmconfig.${1}"

    local VMNAME=$(getConfigItem $configFile NAME)
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
    local VMEXTRA=$(getConfigItem $configFile VMEXTRA)


    # Build qemu command
    OPTS="-enable-kvm -nodefaults -machine q35,accel=kvm -qmp tcp:localhost:4444,server,nowait"
    OPTS+=" -mem-prealloc"
    OPTS+=" -device virtio-net-pci,netdev=net0,mac=$VMMAC -netdev bridge,id=net0"
    OPTS+=" -name $VMNAME"
    OPTS+=" -mem-path=/dev/hugepages -mem $VMMEM"
    if [ ! -z "$VMSOCKETS" ] && [ ! -z "$VMTHREADS" ] && [ ! -z "$VMCORES" ]; then
        OPTS+=" -smp sockets=${VMSOCKETS},cores=${VMCORES},threads=${VMTHREADS}"
    fi
    if [ ! -z "$VMBIOS" ] && [ ! -z "$VMBIOS_VARS" ]; then
        OPTS+=" -drive if=pflash,format=raw,readonly,file=${VMBIOS} -drive if=pflash,format=raw,file=${VMBIOS_VARS}"
    fi

    if [ ! -z "$VMHARDDISK" ]; then
        for DISK in $VMHARDDISK; do
            # Do we need virtio,id=driveX here ?
            OPTS+=" -drive if=virtio,cache=none,aio=native,format=raw,file=${DISK}"
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
    echo $VMCPUOPTS
    echo "$OPTS"

    vCPUpin "$VMCORELIST" &
    IRQAffinity "$VMCORELIST" &
    realTimeTune

    echo qemu-system-x86_64 $OPTS
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
    sleep 10
    local CORELIST="$1"
    echo "Setting CPU affinity using cores: $CORELIST"
    local THREADS=`( echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "query-cpus" }' | timeout 2 nc localhost 4444 | tr , '\n' ) | grep thread_id | cut -d : -f 2 | sed -e 's/}.*//g' -e 's/ //g'`

	local COUNT=1
	for THREAD_ID in $THREADS; do
		CURCORE=$(echo $CORELIST | cut -d " " -f $COUNT)
        echo "Binding $THREAD_ID to $CURCORE"
		taskset -pc $CURCORE $THREAD_ID > /dev/null 2>&1
		COUNT=$(( $COUNT + 1 ))
	done
}

IRQAffinity() {
    sleep 5
    local CORELIST="$1"
    local ALLCORES=$(cat /proc/cpuinfo | grep processor | awk '{print $3}')

    for CORE in $ALLCORES; do
        if echo "$CORELIST" | grep $CORE -q ; then
            IRQCORE="${IRQCORE},${CORE}"
        fi
    done
    IRQCORE="${IRQCORE:1}" # Remove first ,

    for IRQ in `ls -1 /proc/irq/`; do
        if [ -d /proc/irq/${IRQ} ]; then
            echo "$IRQCORE" > /proc/irq/${IRQ}/smp_affinity_list
        fi
    done
}

buildItems
showMainMenu
doSelect
