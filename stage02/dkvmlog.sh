#!/bin/bash

qemuStarted=false
shownUSBDevices=false
shownPCIDevices=false
shownThreads=false

# Check arguments
if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <usbpassthrough file> <pci passthrough file>"
	exit 1
else
	usbPassthroughFile=$1
	pciPassthroughFile=$2
fi

# Sends a command to QEMU via QMP
doQMP() {
	local cmd=$1
	# Connect to QMP and send command
	echo -e '{ "execute": "qmp_capabilities" }\n{ "execute": "'$cmd'" }' | timeout 2 nc localhost 4444 2>/dev/null
}

# Returns the current status of the QEMU instance
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
doShowStatus() {
	loopCount=0
	echo "Waiting for QEMU to start..."
	
	while true; do
		currentStatus=$(getQEMUStatus) # Get current QEMU status
		
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

doShowStatus # Start monitoring
