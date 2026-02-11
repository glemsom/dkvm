#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ FILE:        verify_pinning.sh
# ║ USAGE:       ./verify_pinning.sh
# ║
# ║ DESCRIPTION: DKVM CPU Pinning Verification Utility
# ║              Should be executed INSIDE the guest VM.
# ║              Correlates Guest CPU IDs to Guest Physical Cores,
# ║              fetches Host CPU topology, generates CPU load on each
# ║              guest vCPU, and verifies core/thread siblings are correctly placed.
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
#
# Requirements:
#   - bash, lscpu, taskset, yes (in guest)
#   - ssh root access to host with passwordless authentication

HOST_IP="192.168.50.21"

echo "--- Fetching Topologies ---"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Fetch Guest Topology - Maps Guest CPU IDs to physical cores
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
declare -A GUEST_CPU_TO_CORE
while read -r line; do
	[[ $line =~ ^# ]] && continue
	cpu=$(echo "$line" | cut -d, -f1)
	core=$(echo "$line" | cut -d, -f2)
	GUEST_CPU_TO_CORE[$cpu]=$core
done < <(lscpu -p=CPU,Core)

GUEST_CPU_COUNT=${#GUEST_CPU_TO_CORE[@]}

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Fetch Host topology data via SSH - Collects CPU ID, core ID, L3 cache size
# ║                                    and CPPC highest performance values
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
HOST_DATA=$(ssh root@${HOST_IP} '
	for i in /sys/devices/system/cpu/cpu[0-9]*; do
		cpu=${i##*cpu}
		core=$(cat $i/topology/core_id)
		l3_size=$(cat $i/cache/index3/size 2>/dev/null || echo "N/A")
		cppc_perf=$(cat $i/acpi_cppc/highest_perf 2>/dev/null || echo "N/A")
		siblings=$(cat $i/topology/thread_siblings_list 2>/dev/null || echo "N/A")
		die_id=$(cat $i/topology/die_id 2>/dev/null || echo "0")
		echo "$cpu|$core|$l3_size|$cppc_perf|$siblings|$die_id"
	done
')

declare -A HOST_CPU_TO_CORE
declare -A HOST_CPU_TO_L3
declare -A HOST_CPU_TO_CPPC
declare -A HOST_CPU_SIBLINGS
declare -A HOST_CPU_TO_DIE
while IFS='|' read -r cpu core l3 cppc siblings die_id; do
	HOST_CPU_TO_CORE[$cpu]=$core
	HOST_CPU_TO_L3[$cpu]=$l3
	HOST_CPU_TO_CPPC[$cpu]=$cppc
	HOST_CPU_SIBLINGS[$cpu]=$siblings
	HOST_CPU_TO_DIE[$cpu]=$die_id
done <<<"$HOST_DATA"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Collect Thread Siblings - Maps CPUs to their sibling threads (SMT topology)
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
declare -A GUEST_CPU_SIBLINGS
declare -A GUEST_CPU_TO_DIE
for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
	cpu=${cpu_dir##*/cpu}
	if [[ -f "$cpu_dir/topology/thread_siblings_list" ]]; then
		GUEST_CPU_SIBLINGS[$cpu]=$(cat "$cpu_dir/topology/thread_siblings_list")
	fi
	if [[ -f "$cpu_dir/topology/die_id" ]]; then
		GUEST_CPU_TO_DIE[$cpu]=$(cat "$cpu_dir/topology/die_id")
	else
		GUEST_CPU_TO_DIE[$cpu]=0
	fi
done

echo "--- Starting Pinning Verification ---"
printf "%-12s | %-14s | %-10s | %-15s | %-15s | %-10s | %-8s\n" "Guest vCPU" "Guest Core ID" "Guest Die" "Host Logical CPU" "Host Core ID" "L3 Cache" "CPPC"
echo "-------------|----------------|------------|-----------------|-----------------|------------|----------"

# Track which host core, CPU, and die each guest CPU maps to (for sibling and die verification)
declare -A GUEST_CPU_TO_HOST_CORE
declare -A GUEST_CPU_TO_HOST_CPU
declare -A GUEST_CPU_TO_HOST_DIE

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Main Verification Loop - For each guest vCPU: generate load, detect which host
# ║                          physical core handles it.
# ╚═══════════════════════════════════════════════════════════════════════════════════╝
for ((i = 0; i < GUEST_CPU_COUNT; i++)); do
	G_CPU=$i
	G_CORE=${GUEST_CPU_TO_CORE[$G_CPU]}
	G_DIE=${GUEST_CPU_TO_DIE[$G_CPU]:-0}

	# Start load generator pinned to this guest CPU
	taskset -c "$G_CPU" yes >/dev/null &
	LOAD_PID=$!
	sleep 3

	# Detect which host CPU is handling the load by comparing /proc/stat snapshots
	DETECTION_RESULT=$(
		ssh root@${HOST_IP} 'bash -s' <<'REMOTESCRIPT'
		declare -A t1
		while read -r l; do [[ $l =~ ^cpu([0-9]+) ]] || continue; t1[${BASH_REMATCH[1]}]=$l; done < /proc/stat
		sleep 1
		max_busy=0; max_core=-1
		while read -r l; do
			[[ $l =~ ^cpu([0-9]+) ]] || continue
			c=${BASH_REMATCH[1]}
			read -r _ u1 n1 s1 i1 io1 ir1 sir1 st1 g1 gn1 <<< "${t1[$c]}"
			read -r _ u2 n2 s2 i2 io2 ir2 sir2 st2 g2 gn2 <<< "$l"
			busy=$(( (u2+n2+s2+ir2+sir2+st2) - (u1+n1+s1+ir1+sir1+st1) ))
			if [ $busy -gt $max_busy ]; then max_busy=$busy; max_core=$c; fi
		done < /proc/stat
		echo $max_core
REMOTESCRIPT
	)

	H_CPU=$DETECTION_RESULT
	kill $LOAD_PID
	wait $LOAD_PID 2>/dev/null
	H_CORE=${HOST_CPU_TO_CORE[$H_CPU]}
	H_L3=${HOST_CPU_TO_L3[$H_CPU]}
	H_CPPC=${HOST_CPU_TO_CPPC[$H_CPU]}
	H_DIE=${HOST_CPU_TO_DIE[$H_CPU]:-0}

	# Store mapping for sibling and die verification
	GUEST_CPU_TO_HOST_CORE[$G_CPU]=$H_CORE
	GUEST_CPU_TO_HOST_CPU[$G_CPU]=$H_CPU
	GUEST_CPU_TO_HOST_DIE[$G_CPU]=$H_DIE

	printf "%-12s | %-14s | %-10s | %-15s | %-15s | %-10s | %-8s\n" "$G_CPU" "$G_CORE" "$G_DIE" "$H_CPU" "$H_CORE" "$H_L3" "$H_CPPC"
done

echo ""
echo "--- Core Sibling Verification ---"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ Core Sibling Verification - Verify that sibling threads on the guest map to the
# ║                             same physical core on the host
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# Build map of guest cores to their CPUs
declare -A GUEST_CORE_TO_CPUS
for cpu in "${!GUEST_CPU_TO_CORE[@]}"; do
	core=${GUEST_CPU_TO_CORE[$cpu]}
	GUEST_CORE_TO_CPUS[$core]="${GUEST_CORE_TO_CPUS[$core]} $cpu"
done

printf "%-14s | %-14s | %-15s | %-15s | %-8s\n" "Guest Core ID" "Guest vCPU" "Host Core ID" "Host Logical CPU" "Status"
echo "---------------|---------------|-----------------|-----------------|----------"

for core in "${!GUEST_CORE_TO_CPUS[@]}"; do
	cpus=(${GUEST_CORE_TO_CPUS[$core]})

	# Collect host cores for all CPUs in this guest core
	declare -A host_cores_seen=()
	for cpu in "${cpus[@]}"; do
		host_core=${GUEST_CPU_TO_HOST_CORE[$cpu]}
		host_cores_seen[$host_core]=1
	done

	# Determine if this guest core has consistent host core mapping
	if [ ${#host_cores_seen[@]} -eq 1 ]; then
		core_status="PASS"
	else
		core_status="FAIL"
	fi

	# Print each individual thread mapping
	for cpu in "${cpus[@]}"; do
		host_core=${GUEST_CPU_TO_HOST_CORE[$cpu]}
		host_cpu=${GUEST_CPU_TO_HOST_CPU[$cpu]}

		printf "%-14s | %-14s | %-15s | %-15s | %-8s\n" "Core $core" "vCPU $cpu" "$host_core" "$host_cpu" "$core_status"
	done
done

echo ""
echo "--- CPU-Die Verification ---"

# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║ CPU-Die Verification - Verify that cores on the same guest die map to the same
# ║                        host die (die numbers don't need to match)
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# Build map of guest dies to their CPUs
declare -A GUEST_DIE_TO_CPUS
for cpu in "${!GUEST_CPU_TO_DIE[@]}"; do
	die=${GUEST_CPU_TO_DIE[$cpu]}
	GUEST_DIE_TO_CPUS[$die]="${GUEST_DIE_TO_CPUS[$die]} $cpu"
done

printf "%-14s | %-30s | %-15s | %-8s\n" "Guest Die ID" "Guest vCPUs" "Host Die ID" "Status"
echo "---------------|-------------------------------|-----------------|----------"

for die in "${!GUEST_DIE_TO_CPUS[@]}"; do
	cpus=(${GUEST_DIE_TO_CPUS[$die]})

	# Collect host dies for all CPUs in this guest die
	declare -A host_dies_seen=()
	for cpu in "${cpus[@]}"; do
		host_die=${GUEST_CPU_TO_HOST_DIE[$cpu]}
		host_dies_seen[$host_die]=1
	done

	# Determine if this guest die has consistent host die mapping
	if [ ${#host_dies_seen[@]} -eq 1 ]; then
		die_status="PASS"
	else
		die_status="FAIL"
	fi

	# Get the host die (should be only one if PASS)
	host_die_list=""
	for host_die in "${!host_dies_seen[@]}"; do
		host_die_list="$host_die_list$host_die "
	done
	host_die_list=$(echo "$host_die_list" | sed 's/ $//')

	# Format CPU list
	cpu_list=$(echo "${cpus[*]}" | tr ' ' ',')

	printf "%-14s | %-30s | %-15s | %-8s\n" "Die $die" "$cpu_list" "$host_die_list" "$die_status"
done
echo ""
echo "--- Verification Finished ---"
