#!/bin/bash
# DKVM CPU Pinning Verification Utility
#
# Usage:
#   This script should be executed INSIDE the guest VM.
#   It requires SSH key access to the DKVM Host (Adjust $HOST_IP as needed).
#
# Description:
#   1. Correlates Guest CPU IDs to Guest Physical Cores.
#   2. Fetches Host CPU topology.
#   3. Sequentially generates CPU load on each guest vCPU.
#   4. Checks on the Host which physical core is handling the load.
#   5. Verifies if the pinned core belongs to the DKVM-reserved VMCPU set.
#
# Requirements:
#   - bash, lscpu, taskset, yes (in guest)
#   - ssh root access to host with passwordless authentication

HOST_IP="192.168.50.21"
TOPOLOGY_FILE="/media/dkvmdata/cpuTopology"

echo "--- Fetching Topologies ---"

# 1. Fetch Guest Topology
declare -A GUEST_CPU_TO_CORE
while read -r line; do
	[[ $line =~ ^# ]] && continue
	cpu=$(echo "$line" | cut -d, -f1)
	core=$(echo "$line" | cut -d, -f2)
	GUEST_CPU_TO_CORE[$cpu]=$core
done < <(lscpu -p=CPU,Core)

GUEST_CPU_COUNT=${#GUEST_CPU_TO_CORE[@]}

# 2. Fetch Host topology data
HOST_DATA=$(ssh root@${HOST_IP} "
	for i in /sys/devices/system/cpu/cpu[0-9]*; do
		cpu=\${i##*cpu}
		core=\$(cat \$i/topology/core_id)
		l3_size=\$(cat \$i/cache/index3/size 2>/dev/null || echo 'N/A')
		cppc_perf=\$(cat \$i/acpi_cppc/highest_perf 2>/dev/null || echo 'N/A')
		echo \"\$cpu,\$core,\$l3_size,\$cppc_perf\"
	done
")

declare -A HOST_CPU_TO_CORE
declare -A HOST_CPU_TO_L3
declare -A HOST_CPU_TO_CPPC
while IFS=',' read -r cpu core l3 cppc; do
	HOST_CPU_TO_CORE[$cpu]=$core
	HOST_CPU_TO_L3[$cpu]=$l3
	HOST_CPU_TO_CPPC[$cpu]=$cppc
done <<< "$HOST_DATA"

# 3. Fetch Expected VMCPUs
# shellcheck disable=SC1090
source <(ssh root@${HOST_IP} "cat ${TOPOLOGY_FILE}")
IFS=',' read -r -a VM_HOST_CPUS <<< "$VMCPU"

echo "--- Starting Pinning Verification ---"
printf "%-12s | %-12s | %-12s | %-12s | %-10s | %-8s | %-8s\n" "Guest CPU" "Guest Core" "Host CPU" "Host Core" "L3 Cache" "CPPC" "Status"
echo "-------------|--------------|--------------|--------------|------------|----------|----------"

for (( i=0; i<GUEST_CPU_COUNT; i++ )); do
	G_CPU=$i
	G_CORE=${GUEST_CPU_TO_CORE[$G_CPU]}

	# Start load
	yes > /dev/null &
	LOAD_PID=$!
	taskset -pc "$G_CPU" $LOAD_PID > /dev/null
	sleep 3

	# Detect Host CPU
	DETECTION_RESULT=$(ssh root@${HOST_IP} "bash -c '
		declare -A t1
		while read -r l; do [[ \$l =~ ^cpu([0-9]+) ]] || continue; t1[\${BASH_REMATCH[1]}]=\$l; done < /proc/stat
		sleep 1
		max_busy=0; max_core=-1
		while read -r l; do
			[[ \$l =~ ^cpu([0-9]+) ]] || continue
			c=\${BASH_REMATCH[1]}
			read -r _ u1 n1 s1 i1 io1 ir1 sir1 st1 g1 gn1 <<< \"\${t1[\$c]}\"
			read -r _ u2 n2 s2 i2 io2 ir2 sir2 st2 g2 gn2 <<< \"\$l\"
			busy=\$(( (u2+n2+s2+ir2+sir2+st2) - (u1+n1+s1+ir1+sir1+st1) ))
			if [ \$busy -gt \$max_busy ]; then max_busy=\$busy; max_core=\$c; fi
		done < /proc/stat
		echo \$max_core
	'")

	H_CPU=$DETECTION_RESULT
	kill $LOAD_PID; wait $LOAD_PID 2>/dev/null
	H_CORE=${HOST_CPU_TO_CORE[$H_CPU]}
	H_L3=${HOST_CPU_TO_L3[$H_CPU]}
	H_CPPC=${HOST_CPU_TO_CPPC[$H_CPU]}

	# Simple verification: Does the detected Host CPU belong to the set of reserved VMCPUs?
	IS_EXPECTED="FAIL"
	for expected in "${VM_HOST_CPUS[@]}"; do
		if [ "$H_CPU" == "$expected" ]; then
			IS_EXPECTED="PASS"
			break
		fi
	done

	printf "%-12s | %-12s | %-12s | %-12s | %-10s | %-8s | %-8s\n" "$G_CPU" "$G_CORE" "$H_CPU" "$H_CORE" "$H_L3" "$H_CPPC" "$IS_EXPECTED"
done

echo "--- Verification Finished ---"
