#!/usr/local/bin/bash

# =============================================================================
# macOS Power Management & System Stability Setup Script
# =============================================================================
# Configures a fresh macOS installation with optimised power management,
# process throttling, and stability improvements.
#
# Usage: sudo ./macos-setup.sh [--username USERNAME]
#
# Author: System Configuration
# Date: 31 January 2026
# Tested on: MacBook Pro 16,2 (Intel, 2020), macOS 26.2
# =============================================================================

set -e

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# Default username (can be overridden with --username)
USERNAME="${SUDO_USER:-$(whoami)}"
USER_HOME="/Users/$USERNAME"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            USERNAME="$2"
            USER_HOME="/Users/$USERNAME"
            shift 2
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--username USERNAME]"
            echo ""
            echo "Options:"
            echo "  --username USERNAME  Specify the user to configure (default: current user)"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    echo -e "${RED}Error: User '$USERNAME' does not exist${NC}"
    exit 1
fi

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  macOS Power Management Setup Script${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo -e "Configuring for user: ${GREEN}$USERNAME${NC}"
echo -e "User home: ${GREEN}$USER_HOME${NC}"
echo ""

# -----------------------------------------------------------------------------
# Section 1: Power Management Settings
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/6] Configuring power management settings...${NC}"

# Battery settings
pmset -b sleep 15                 # Sleep after 15 min idle
pmset -b displaysleep 10          # Display sleep after 10 min
pmset -b disksleep 10             # Disk sleep after 10 min

# AC power settings
pmset -c sleep 0                  # Never sleep when lid open on AC
pmset -c displaysleep 10          # Display sleep after 10 min

# Both power sources
pmset -a womp 0                   # Disable Wake on Magic Packet
pmset -a proximitywake 0          # Disable proximity wake
pmset -a tcpkeepalive 0           # Disable TCP keepalive wake
pmset -a ttyskeepawake 0          # Disable terminal keepawake
pmset -a powernap 0               # Disable Power Nap
pmset -a standbydelayhigh 900     # 15 min to standby (high battery)
pmset -a standbydelaylow 300      # 5 min to standby (low battery)
pmset -a acwake 0                 # Disable wake on AC change

echo -e "${GREEN}  ✓ Power management settings configured${NC}"

# -----------------------------------------------------------------------------
# Section 2: Create bin directory
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/6] Creating user bin directory...${NC}"

mkdir -p "$USER_HOME/bin"
chown "$USERNAME:staff" "$USER_HOME/bin"

echo -e "${GREEN}  ✓ Created $USER_HOME/bin${NC}"

# -----------------------------------------------------------------------------
# Section 3: Install throttle script
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/6] Installing iCloud/Spotlight throttle script...${NC}"

cat > "$USER_HOME/bin/icloud-throttle.sh" << 'THROTTLE_SCRIPT'
#!/usr/local/bin/bash

# =============================================================================
# iCloud & Spotlight Process Throttler
# =============================================================================

NICE_LEVEL=20
CHECK_INTERVAL=30
LOG_FILE="/tmp/icloud-throttle.log"

USER_PROCESSES="fileproviderd cloudd bird"
ROOT_PROCESSES="mds mds_stores"

declare -A TRACKED_PIDS

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

throttle_process() {
    local name=$1
    local use_sudo=$2
    local pid=$(pgrep -x "$name" | head -1)
    
    if [ -n "$pid" ]; then
        local current_nice=$(ps -o nice= -p "$pid" 2>/dev/null | tr -d ' ')
        
        if [ "$current_nice" != "$NICE_LEVEL" ]; then
            if [ "$use_sudo" = "yes" ]; then
                sudo renice $NICE_LEVEL -p "$pid" >/dev/null 2>&1
            else
                renice $NICE_LEVEL -p "$pid" >/dev/null 2>&1
            fi
            log "Throttled $name (PID: $pid) from nice $current_nice to $NICE_LEVEL"
            TRACKED_PIDS[$name]=$pid
        elif [ "${TRACKED_PIDS[$name]}" != "$pid" ]; then
            log "New PID detected for $name (PID: $pid) - already throttled"
            TRACKED_PIDS[$name]=$pid
        fi
    fi
}

show_status() {
    echo ""
    echo "=== $(date '+%H:%M:%S') ==="
    printf "%-20s %8s %8s %8s\n" "PROCESS" "PID" "NICE" "CPU%"
    echo "------------------------------------------------"
    
    for name in $USER_PROCESSES $ROOT_PROCESSES; do
        local pid=$(pgrep -x "$name" | head -1)
        if [ -n "$pid" ]; then
            local nice=$(ps -o nice= -p "$pid" 2>/dev/null | tr -d ' ')
            local cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
            printf "%-20s %8s %8s %8s\n" "$name" "$pid" "$nice" "$cpu"
        else
            printf "%-20s %8s %8s %8s\n" "$name" "-" "-" "-"
        fi
    done
}

log "=== iCloud & Spotlight Throttler Started ==="

for name in $USER_PROCESSES; do
    throttle_process "$name" "no"
done
for name in $ROOT_PROCESSES; do
    throttle_process "$name" "yes"
done

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
THROTTLE_SCRIPT

chmod +x "$USER_HOME/bin/icloud-throttle.sh"
chown "$USERNAME:staff" "$USER_HOME/bin/icloud-throttle.sh"

echo -e "${GREEN}  ✓ Throttle script installed${NC}"

# -----------------------------------------------------------------------------
# Section 4: Install launch daemon
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/6] Installing launch daemon...${NC}"

cat > /Library/LaunchDaemons/com.user.icloud-throttle.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.icloud-throttle</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bash</string>
        <string>$USER_HOME/bin/icloud-throttle.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/icloud-throttle.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/icloud-throttle.out</string>
</dict>
</plist>
PLIST

chmod 644 /Library/LaunchDaemons/com.user.icloud-throttle.plist

# Load the daemon
launchctl load /Library/LaunchDaemons/com.user.icloud-throttle.plist 2>/dev/null || true

echo -e "${GREEN}  ✓ Launch daemon installed and loaded${NC}"

# -----------------------------------------------------------------------------
# Section 5: Install utility script
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/6] Installing system utility script...${NC}"

cat > "$USER_HOME/bin/sysutil" << 'UTILITY_SCRIPT'
#!/usr/local/bin/bash

# =============================================================================
# macOS System Utility Script
# =============================================================================

VERSION="1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << EOF
macOS System Utility v$VERSION

Usage: sysutil <command> [options]

Commands:
  status          Show overall system status
  top             Show top CPU-consuming processes
  thermal         Show thermal status
  assertions      Show sleep blockers/assertions
  throttle        Manually throttle iCloud/Spotlight processes
  monitor         Start live monitoring of throttled processes
  touchid         Reset Touch ID (fix after sleep issues)
  sleep-check     Check if system can sleep properly
  icloud-reset    Reset iCloud sync state
  spotlight       Control Spotlight indexing

Options:
  -h, --help      Show this help message
  -v, --version   Show version

Examples:
  sysutil status           # Quick system health check
  sysutil throttle         # Manually renice iCloud/Spotlight
  sysutil touchid          # Fix Touch ID after sleep
  sysutil monitor          # Watch throttled processes
  sysutil spotlight off    # Disable Spotlight indexing
  sysutil spotlight on     # Enable Spotlight indexing
EOF
}

cmd_status() {
    echo -e "${BLUE}=== System Status ===${NC}"
    echo ""
    
    # Thermal
    echo -e "${YELLOW}Thermal:${NC}"
    local speed=$(pmset -g therm 2>/dev/null | grep "CPU_Speed_Limit" | awk '{print $3}')
    if [ "$speed" = "100" ]; then
        echo -e "  CPU Speed Limit: ${GREEN}${speed}%${NC} (no throttling)"
    else
        echo -e "  CPU Speed Limit: ${RED}${speed}%${NC} (THROTTLED)"
    fi
    echo ""
    
    # Load
    echo -e "${YELLOW}Load Average:${NC}"
    uptime | awk -F'load averages:' '{print "  " $2}'
    echo ""
    
    # Sleep blockers
    echo -e "${YELLOW}Sleep Blockers:${NC}"
    local blockers=$(pmset -g assertions 2>/dev/null | grep -c "PreventUserIdleSystemSleep\|PreventSystemSleep" | grep -v "0")
    if [ "$blockers" -gt 0 ] 2>/dev/null; then
        echo -e "  ${RED}Warning: $blockers sleep blocker(s) active${NC}"
        pmset -g assertions 2>/dev/null | grep -E "Prevent.*Sleep" | head -5 | sed 's/^/    /'
    else
        echo -e "  ${GREEN}No sleep blockers${NC}"
    fi
    echo ""
    
    # Top processes
    echo -e "${YELLOW}Top CPU Processes:${NC}"
    ps aux | sort -nrk 3 | head -5 | awk '{printf "  %-20s %5.1f%%\n", $11, $3}' | cut -c1-60
}

cmd_top() {
    echo -e "${BLUE}=== Top CPU Processes ===${NC}"
    echo ""
    printf "%-8s %-20s %8s %8s\n" "PID" "PROCESS" "CPU%" "MEM%"
    echo "------------------------------------------------"
    ps aux | sort -nrk 3 | head -10 | awk '{printf "%-8s %-20s %8.1f %8.1f\n", $2, $11, $3, $4}' | while read line; do
        echo "$line" | cut -c1-60
    done
}

cmd_thermal() {
    echo -e "${BLUE}=== Thermal Status ===${NC}"
    echo ""
    pmset -g therm
}

cmd_assertions() {
    echo -e "${BLUE}=== Sleep Assertions ===${NC}"
    echo ""
    pmset -g assertions
}

cmd_throttle() {
    echo -e "${BLUE}=== Throttling Processes ===${NC}"
    echo ""
    
    for proc in fileproviderd cloudd bird; do
        local pid=$(pgrep -x "$proc" | head -1)
        if [ -n "$pid" ]; then
            renice 20 -p "$pid" >/dev/null 2>&1
            echo -e "${GREEN}✓${NC} Throttled $proc (PID: $pid)"
        else
            echo -e "${YELLOW}○${NC} $proc not running"
        fi
    done
    
    for proc in mds mds_stores; do
        local pid=$(pgrep -x "$proc" | head -1)
        if [ -n "$pid" ]; then
            sudo renice 20 -p "$pid" >/dev/null 2>&1
            echo -e "${GREEN}✓${NC} Throttled $proc (PID: $pid)"
        else
            echo -e "${YELLOW}○${NC} $proc not running"
        fi
    done
}

cmd_monitor() {
    echo -e "${BLUE}=== Process Monitor (Ctrl+C to stop) ===${NC}"
    tail -f /tmp/icloud-throttle.out 2>/dev/null || echo -e "${RED}Throttle daemon not running${NC}"
}

cmd_touchid() {
    echo -e "${BLUE}=== Resetting Touch ID ===${NC}"
    echo ""
    
    sudo killall biometrickitd BiomeAgent biomed TouchBarServer 2>/dev/null
    sleep 3
    
    if pgrep -x biometrickitd >/dev/null; then
        echo -e "${GREEN}✓${NC} Touch ID daemons restarted"
        echo -e "${YELLOW}Try using Touch ID now${NC}"
    else
        echo -e "${RED}✗${NC} Failed to restart Touch ID daemons"
    fi
}

cmd_sleep_check() {
    echo -e "${BLUE}=== Sleep Readiness Check ===${NC}"
    echo ""
    
    # Check clamshell
    local clamshell=$(ioreg -r -k AppleClamshellCausesSleep 2>/dev/null | grep AppleClamshellCausesSleep | awk '{print $3}')
    if [ "$clamshell" = "Yes" ]; then
        echo -e "${GREEN}✓${NC} Lid close will cause sleep"
    else
        echo -e "${RED}✗${NC} Lid close will NOT cause sleep (SMC reset needed)"
    fi
    
    # Check assertions
    local prevent_system=$(pmset -g assertions 2>/dev/null | grep "PreventSystemSleep" | head -1 | awk '{print $2}')
    if [ "$prevent_system" = "0" ]; then
        echo -e "${GREEN}✓${NC} No PreventSystemSleep assertions"
    else
        echo -e "${RED}✗${NC} PreventSystemSleep is active"
    fi
    
    local prevent_idle=$(pmset -g assertions 2>/dev/null | grep "PreventUserIdleSystemSleep" | head -1 | awk '{print $2}')
    if [ "$prevent_idle" = "0" ]; then
        echo -e "${GREEN}✓${NC} No PreventUserIdleSystemSleep assertions"
    else
        echo -e "${YELLOW}!${NC} PreventUserIdleSystemSleep is active (check 'sysutil assertions')"
    fi
    
    # Check audio
    local audio=$(pmset -g assertions 2>/dev/null | grep -i audio)
    if [ -z "$audio" ]; then
        echo -e "${GREEN}✓${NC} No audio assertions"
    else
        echo -e "${YELLOW}!${NC} Audio assertions present"
    fi
}

cmd_icloud_reset() {
    echo -e "${BLUE}=== Resetting iCloud Sync State ===${NC}"
    echo ""
    echo -e "${YELLOW}Warning: This will restart iCloud sync from scratch${NC}"
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        killall -9 fileproviderd cloudd bird 2>/dev/null
        rm -rf ~/Library/Application\ Support/CloudDocs/session/
        rm -rf ~/Library/Caches/CloudKit/
        rm -rf ~/Library/Caches/com.apple.bird/
        
        echo -e "${GREEN}✓${NC} iCloud sync state reset"
        echo -e "${YELLOW}iCloud will rebuild its sync database${NC}"
    else
        echo "Cancelled"
    fi
}

cmd_spotlight() {
    local action="$1"
    
    case "$action" in
        on)
            echo -e "${BLUE}Enabling Spotlight...${NC}"
            sudo mdutil -a -i on
            echo -e "${GREEN}✓${NC} Spotlight enabled"
            ;;
        off)
            echo -e "${BLUE}Disabling Spotlight...${NC}"
            sudo mdutil -a -i off
            echo -e "${GREEN}✓${NC} Spotlight disabled"
            ;;
        status|"")
            echo -e "${BLUE}=== Spotlight Status ===${NC}"
            mdutil -s /
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Usage: sysutil spotlight [on|off|status]"
            ;;
    esac
}

# Main
case "$1" in
    status)
        cmd_status
        ;;
    top)
        cmd_top
        ;;
    thermal)
        cmd_thermal
        ;;
    assertions)
        cmd_assertions
        ;;
    throttle)
        cmd_throttle
        ;;
    monitor)
        cmd_monitor
        ;;
    touchid)
        cmd_touchid
        ;;
    sleep-check)
        cmd_sleep_check
        ;;
    icloud-reset)
        cmd_icloud_reset
        ;;
    spotlight)
        cmd_spotlight "$2"
        ;;
    -v|--version)
        echo "sysutil version $VERSION"
        ;;
    -h|--help|"")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run 'sysutil --help' for usage"
        exit 1
        ;;
esac
UTILITY_SCRIPT

chmod +x "$USER_HOME/bin/sysutil"
chown "$USERNAME:staff" "$USER_HOME/bin/sysutil"

echo -e "${GREEN}  ✓ Utility script installed${NC}"

# -----------------------------------------------------------------------------
# Section 6: Add bin to PATH
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[6/6] Updating shell PATH...${NC}"

# Add to .zshrc if not already present
if [ -f "$USER_HOME/.zshrc" ]; then
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$USER_HOME/.zshrc"; then
        echo '' >> "$USER_HOME/.zshrc"
        echo '# User bin directory' >> "$USER_HOME/.zshrc"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$USER_HOME/.zshrc"
        chown "$USERNAME:staff" "$USER_HOME/.zshrc"
    fi
fi

# Add to .bash_profile if not already present
if [ -f "$USER_HOME/.bash_profile" ]; then
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$USER_HOME/.bash_profile"; then
        echo '' >> "$USER_HOME/.bash_profile"
        echo '# User bin directory' >> "$USER_HOME/.bash_profile"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$USER_HOME/.bash_profile"
        chown "$USERNAME:staff" "$USER_HOME/.bash_profile"
    fi
fi

echo -e "${GREEN}  ✓ PATH updated${NC}"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo "Installed:"
echo "  • Power management settings (pmset)"
echo "  • iCloud/Spotlight throttle daemon"
echo "  • System utility script (sysutil)"
echo ""
echo "Files created:"
echo "  • $USER_HOME/bin/icloud-throttle.sh"
echo "  • $USER_HOME/bin/sysutil"
echo "  • /Library/LaunchDaemons/com.user.icloud-throttle.plist"
echo ""
echo "Usage:"
echo "  sysutil status       # Quick system check"
echo "  sysutil throttle     # Manual process throttle"
echo "  sysutil touchid      # Reset Touch ID"
echo "  sysutil monitor      # Watch throttler output"
echo ""
echo -e "${YELLOW}Note: Restart your terminal or run 'source ~/.zshrc' to use sysutil${NC}"
