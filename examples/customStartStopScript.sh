# Sample startStopScript
# We must provide a customVMStart function and a customVMStop function
#
# This example assumes an AMD 9070XT on 03:00.0 and the HOSTGPU as a CPU integrated on 7c:00.0
#

customVMStart() {
  echo "Starting custom start script"
  # Custom start script for 9070 XT cards
  # AMDGPU driver should already be loaded - and initialized the GPU

  devices=$(cat $configPassthroughPCIDevices)
  GPU=03:00.0     # 9070 XT
  HOSTGPU=7c:00.0 # Onboard iGPU
	
  # Block iGPU from binding to amdgpu driver
  echo fake_driver > /sys/bus/pci/devices/0000:$HOSTGPU/driver_override

  # Unbind current drivers for all passthrough devices
  for device in $devices; do
    local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
    local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
    if [ -e /sys/bus/pci/devices/0000:${device}/driver/unbind ]; then
      echo "Unbinding 0000:${device}" 
      echo 0000:${device} > /sys/bus/pci/devices/0000:${device}/driver/unbind 2>/dev/null
    fi
    # Cleanup VFIO IDs
    echo "Purging VFIO IDs $pciVendor $pciDevice"
    echo "$pciVendor $pciDevice" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null
  done

  # Load amdgpu
  echo "Loading AMDGPU driver on 0000:$GPU"
  modprobe amdgpu
  sleep 2

  # Unload amdgpu
  echo "Unloading AMDGPU driver on 0000:$GPU"
  rmmod amdgpu

  # Set BAR for 9070XT
  echo "Optimizing BARs for 0000:$GPU"
  echo 12 > /sys/bus/pci/devices/0000:$GPU/resource0_resize 2>/dev/null
  echo 3  > /sys/bus/pci/devices/0000:$GPU/resource2_resize 2>/dev/null
	
  sleep 2 # Let devices settle

  # Bind VFIO-PCI
  for device in $devices; do
    local pciVendor=$(cat /sys/bus/pci/devices/0000:${device}/vendor)
    local pciDevice=$(cat /sys/bus/pci/devices/0000:${device}/device)
    echo "Registrating vfio-pci on ${pciVendor}:${pciDevice}"
    echo "$pciVendor $pciDevice" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null
  done
  echo "Done with custom start script"
}

customVMStop() {
  echo "Starting custom stop script"
  echo "Done with custom stop script"
}