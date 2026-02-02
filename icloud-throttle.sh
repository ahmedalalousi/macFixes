#!/usr/local/bin/bash

# =============================================================================
# iCloud & Spotlight Process Throttler
# =============================================================================
# Monitors and throttles iCloud and Spotlight processes, re-applying niceness
# if processes restart. Designed to run as a system LaunchDaemon.
#
# Author: System Configuration
# Date: 31 January 2026
# Location: /Users/ahmedal/bin/icloud-throttle.sh
# =============================================================================

NICE_LEVEL=20
CHECK_INTERVAL=30
LOG_FILE="/tmp/icloud-throttle.log"

# Processes to throttle (user processes)
USER_PROCESSES="fileproviderd cloudd bird itunescloudd"

# Processes that need sudo (root processes)
ROOT_PROCESSES="mds mds_stores"

# Track PIDs we've already logged
declare -A LOGGED_PIDS

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

throttle_process() {
    local name=$1
    local use_sudo=$2
    
    # Get ALL PIDs for this process name (not just first one)
    for pid in $(pgrep -x "$name"); do
        local current_nice=$(ps -o nice= -p "$pid" 2>/dev/null | tr -d ' ')
        
        if [ -n "$current_nice" ] && [ "$current_nice" != "$NICE_LEVEL" ]; then
            if [ "$use_sudo" = "yes" ]; then
                sudo renice $NICE_LEVEL -p "$pid" >/dev/null 2>&1
            else
                renice $NICE_LEVEL -p "$pid" >/dev/null 2>&1
            fi
            log "Throttled $name (PID: $pid) from nice $current_nice to $NICE_LEVEL"
            LOGGED_PIDS["$name:$pid"]=1
        elif [ -z "${LOGGED_PIDS["$name:$pid"]}" ]; then
            log "New PID detected for $name (PID: $pid) - already throttled"
            LOGGED_PIDS["$name:$pid"]=1
        fi
    done
}

show_status() {
    echo ""
    echo "=== $(date '+%H:%M:%S') ==="
    printf "%-20s %8s %8s %8s\n" "PROCESS" "PID" "NICE" "CPU%"
    echo "------------------------------------------------"
    
    for name in $USER_PROCESSES $ROOT_PROCESSES; do
        local found=0
        for pid in $(pgrep -x "$name"); do
            found=1
            local nice=$(ps -o nice= -p "$pid" 2>/dev/null | tr -d ' ')
            local cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
            printf "%-20s %8s %8s %8s\n" "$name" "$pid" "$nice" "$cpu"
        done
        if [ $found -eq 0 ]; then
            printf "%-20s %8s %8s %8s\n" "$name" "-" "-" "-"
        fi
    done
}

log "=== iCloud & Spotlight Throttler Started ==="

# Initial throttle
for name in $USER_PROCESSES; do
    throttle_process "$name" "no"
done
for name in $ROOT_PROCESSES; do
    throttle_process "$name" "yes"
done

# Monitor loop
while true; do
    show_status
    
    for name in $USER_PROCESSES; do
        throttle_process "$name" "no"
    done
    for name in $ROOT_PROCESSES; do
        throttle_process "$name" "yes"
    done
    
    sleep $CHECK_INTERVAL
done
