#!/bin/bash

qemuStarted=false
shownUSBDevices=false
shownPCIDevices=false
shownThreads=false

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <usbpassthrough file> <pci passthrough file>"
    exit 1
else
    usbPassthroughFile=$1
    pciPassthroughFile=$2
fi

backtitle="DKVM @ $ip   Version: $version"

doQMP() {
    local cmd=$1
    echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "'$cmd'" }' | timeout 10 nc localhost 4444
}

getQEMUStatus() {
    doQMP query-status |  grep return | tail -n 1 | jq -r .return.status
}

getQEMUThreads() {
    doQMP query-cpus-fast | tail -n1 | jq '.return[] | ."thread-id"' 
}

getUSBPassthroughDevices() {
    local usbDevices=$(cat $1)
    for usbDevice in $usbDevices; do
        lsusb 2>/dev/null| grep $usbDevice
    done
}
getPCIPassthroughDevices() {
    local pciDevices=$(cat $1)
    for pciDevice in $pciDevices; do
        lspci -s $pciDevice
    done
}

# QEMU might not be running yet, give it 30 cycles to startup
doShowStatus() {
    loopCount=0
    echo "Waiting for QEMU to start..."
    while true; do
        if ! $qemuStarted; then
            [ "$(getQEMUStatus)" == "running" ] && echo "QEMU detected with status running" && qemuStarted=true
            [  $loopCount -ge 30 ] && echo "QEMU not detected - aborting" && exit 1 # We waited 30 cycles for qemu to start, something is wrong - abort
        else
            # QEMU has been detected at running
            if ! $shownThreads; then
                echo "QEMU Threads: " $(getQEMUThreads)
                shownThreads=true
            fi
            if ! $shownUSBDevices; then
                echo -e "\nUSB Devices passthrough:"
                getUSBPassthroughDevices $usbPassthroughFile
                shownUSBDevices=true
            fi
            if ! $shownPCIDevices; then
                echo -e "\nPCI Devices passthrough:"
                getPCIPassthroughDevices $pciPassthroughFile
                shownPCIDevices=true
            fi
            # Check if QEMU is still in running state
            if [ ! "$(getQEMUStatus)" == "running" ] ;then
                echo "QEMU exited."
                exit 0
            fi
        fi
        sleep 1
        let loopCount++
    done

}

doShowStatus
