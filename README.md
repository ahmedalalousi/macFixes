# macOS Power Management & System Stability Toolkit

> A comprehensive toolkit for diagnosing and resolving power management, thermal throttling, and system stability issues on Intel MacBooks.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-orange.svg)](https://www.gnu.org/software/bash/)

---

## The Problem

After months of frustration with my MacBook Pro (2020, Intel), I finally snapped when I opened my bag to find my laptop had been running at full blast, burning through the battery and heating up dangerously—despite the lid being closed.

This wasn't an isolated incident. The symptoms had been building:

- **WindowServer crashes** during normal use
- **Thermal throttling** reducing CPU to 31% speed
- **Battery drain** while the Mac should have been sleeping
- **Touch ID failures** after wake from sleep
- **iCloud sync** consuming 150%+ CPU for hours
- **Spotlight indexing** hammering the system relentlessly

After an extensive debugging session, I discovered a cascade of interconnected issues—from a misconfigured SMC to phantom audio drivers holding sleep assertions. This repository documents everything I learned and provides tools to prevent these issues.

---

## What This Toolkit Does

| Tool | Purpose |
|------|---------|
| `sysutil` | Swiss-army knife for system diagnostics and fixes |
| `icloud-throttle.sh` | Persistent daemon to throttle runaway iCloud/Spotlight processes |
| `macos-setup.sh` | One-command setup script for fresh installations |
| `com.user.icloud-throttle.plist` | Launch daemon for automatic process throttling |

---

## Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [The sysutil Command](#-the-sysutil-command)
- [Root Causes Identified](#-root-causes-identified)
- [Detailed Findings](#-detailed-findings)
- [Manual Fixes](#-manual-fixes)
- [Troubleshooting Guide](#-troubleshooting-guide)
- [Contributing](#-contributing)
- [Licence](#-licence)

---

## Installation

### Option 1: Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/macos-power-toolkit.git
cd macos-power-toolkit

# Run the setup script
sudo ./macos-setup.sh
```

### Option 2: Manual Installation

```bash
# 1. Create bin directory
mkdir -p ~/bin

# 2. Copy scripts
cp sysutil ~/bin/
cp icloud-throttle.sh ~/bin/
chmod +x ~/bin/sysutil ~/bin/icloud-throttle.sh

# 3. Add to PATH
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 4. Install launch daemon (requires sudo)
sudo cp com.user.icloud-throttle.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.user.icloud-throttle.plist
```

### Requirements

- macOS 13+ (tested on macOS 26.2)
- Bash 4+ (install via Homebrew: `brew install bash`)
- Intel or Apple Silicon MacBook

> **Note:** The scripts use `/usr/local/bin/bash` by default. If your Bash is elsewhere, update the shebang in each script.

---

## Quick Start

After installation, run a system health check:

```bash
sysutil status
```

This shows:
- Thermal status (CPU throttling)
- System load
- Power source
- Active sleep blockers
- Top CPU processes
- Throttler daemon status

### Common Tasks

```bash
# Check if your Mac can sleep properly
sysutil sleep-check

# Fix Touch ID after sleep issues
sysutil touchid

# See what's blocking sleep
sysutil assertions

# Manually throttle iCloud/Spotlight
sysutil throttle

# Watch throttled processes live
sysutil monitor

# Check why your Mac woke up
sysutil wake-reason
```

---

## The sysutil Command

A comprehensive utility for managing macOS power, processes, and diagnostics.

### Commands

| Command | Description |
|---------|-------------|
| `status` | Overall system health check |
| `top` | Top 15 CPU-consuming processes |
| `thermal` | Thermal status and CPU throttling level |
| `assertions` | All active sleep blockers/assertions |
| `throttle` | Manually throttle iCloud/Spotlight processes |
| `monitor` | Live monitoring of throttled processes |
| `touchid` | Reset Touch ID daemons |
| `sleep-check` | Verify sleep configuration is correct |
| `sleep-test` | Interactive sleep/wake cycle test |
| `icloud-reset` | Reset iCloud sync state (clears caches) |
| `icloud-status` | Show iCloud sync status |
| `spotlight on\|off\|status` | Control Spotlight indexing |
| `audio` | Check audio-related sleep assertions |
| `battery` | Battery status and health |
| `wake-reason` | Show recent wake reasons |
| `pmset` | Current power management settings |

### Examples

```bash
# Quick health check
sysutil status

# Before leaving Mac unattended on battery
sysutil sleep-check

# Fix Touch ID not working after sleep
sysutil touchid

# iCloud using too much CPU
sysutil throttle
sysutil monitor

# Mac keeps waking up
sysutil wake-reason
sysutil assertions

# Disable Spotlight temporarily
sysutil spotlight off
```

---

## Root Causes Identified

Through extensive debugging, I identified these root causes:

### 1. SMC Misconfiguration (Critical)

**Symptom:** Laptop doesn't sleep when lid is closed

**Cause:** `AppleClamshellCausesSleep` was set to `No`

**Discovery:**
```bash
ioreg -r -k AppleClamshellCausesSleep | grep AppleClamshellCausesSleep
# Returned: "AppleClamshellCausesSleep" = No  ← THIS IS WRONG
```

**Fix:** SMC Reset (see [Manual Fixes](#-manual-fixes))

### 2. WhatsApp Holding Sleep Assertions

**Symptom:** Battery drains while Mac should be idle

**Cause:** WhatsApp holds `PreventUserIdleSystemSleep` even when not on a call:
```
WhatsApp: "cameracaptured-idleSleepPreventionForBWFigCaptureDevice"
```

**Fix:** Quit WhatsApp properly (Cmd+Q) before leaving Mac unattended

### 3. Phantom Audio Driver Contexts

**Symptom:** `coreaudiod` holds sleep assertions for 23+ minutes

**Cause:** Virtual audio drivers (BlackHole, Teams Audio Device) create persistent audio contexts

**Fix:** Remove unused virtual audio drivers:
```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver
sudo killall coreaudiod
```

### 4. iCloud Sync Loop

**Symptom:** `fileproviderd` at 150%+ CPU for hours

**Cause:** 67 orphaned containers from uninstalled apps

**Fix:** Reset iCloud sync state:
```bash
sysutil icloud-reset
```

### 5. Touch ID Secure Enclave Desync

**Symptom:** Touch ID doesn't work after sleep/power events

**Cause:** Biometric daemons lose sync with Secure Enclave

**Fix:**
```bash
sysutil touchid
# or manually:
sudo killall biometrickitd BiomeAgent biomed TouchBarServer
```

---

## Detailed Findings

### Thermal Throttling Chain

```
Runaway browser tab (101% CPU)
    ↓
System overheats
    ↓
ThermalPressureLevelHeavy triggered
    ↓
CPU throttled to 31%
    ↓
Intel GPU driver stalls under thermal stress
    ↓
WindowServer hangs waiting for GPU
    ↓
Watchdog kills WindowServer
    ↓
System crash
```

### Sleep Prevention Chain

```
WhatsApp running (even in background)
    ↓
Holds "cameracaptured" assertion
    ↓
PreventUserIdleSystemSleep = 1
    ↓
Mac ignores idle timeout
    ↓
Battery drains to 0%
    ↓
"Low Power Sleep" finally triggers (too late)
```

### Problematic Software Identified

| Software | Issue | Impact |
|----------|-------|--------|
| BlackHole 2ch | Phantom audio contexts | Battery drain |
| Adobe Acrobat DC | CGPDFService CPU spikes | Thermal issues |
| Adobe Creative Cloud | Finder sync overhead | CPU usage |
| Foxit PDF Editor | PDF rendering conflicts | CPU spikes |
| Weather Widget | Stuck at 72% CPU | Thermal issues |
| WhatsApp | Sleep assertion holder | Battery drain |
| Microsoft Teams | Audio driver loaded at boot | Sleep issues |

---

## Manual Fixes

### SMC Reset (MacBook Pro with T2 chip)

This is **critical** if your Mac doesn't sleep when the lid is closed.

1. Shut down the Mac completely
2. Press and hold **Control + Option + Shift** (left side) for 7 seconds
3. While holding those keys, press and hold the **Power button** for 7 seconds
4. Release all keys, wait a few seconds
5. Press Power to turn on

**Verify:**
```bash
ioreg -r -k AppleClamshellCausesSleep | grep AppleClamshellCausesSleep
# Should return: "AppleClamshellCausesSleep" = Yes
```

### Power Management Settings

```bash
# Battery settings
sudo pmset -b sleep 15           # Sleep after 15 min idle
sudo pmset -b displaysleep 10    # Display sleep after 10 min

# AC power settings
sudo pmset -c sleep 0            # Never sleep with lid open on AC
sudo pmset -c displaysleep 10    # Display sleep after 10 min

# Both power sources
sudo pmset -a womp 0             # Disable Wake on Magic Packet
sudo pmset -a proximitywake 0    # Disable proximity wake
sudo pmset -a tcpkeepalive 0     # Disable TCP keepalive
sudo pmset -a powernap 0         # Disable Power Nap
```

### Remove Problematic Audio Drivers

```bash
# List installed audio drivers
ls -la /Library/Audio/Plug-Ins/HAL/

# Remove BlackHole (if not needed)
sudo rm -rf /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver

# Restart audio system
sudo killall coreaudiod
```

### Reset iCloud Sync

```bash
# Kill iCloud processes
killall -9 fileproviderd cloudd bird

# Clear sync caches
rm -rf ~/Library/Application\ Support/CloudDocs/session/
rm -rf ~/Library/Caches/CloudKit/
rm -rf ~/Library/Caches/com.apple.bird/
```

---

## Troubleshooting Guide

### Mac Won't Sleep When Lid Closes

```bash
# Check clamshell setting
ioreg -r -k AppleClamshellCausesSleep | grep AppleClamshellCausesSleep

# If it says "No", do an SMC reset (see above)
```

### Battery Drains While Mac Should Be Sleeping

```bash
# Check what's blocking sleep
sysutil assertions

# Look for PreventUserIdleSystemSleep or PreventSystemSleep
# Kill the offending app or process
```

### Touch ID Not Working

```bash
sysutil touchid
```

### Mac Running Hot

```bash
# Check thermal status
sysutil thermal

# Check top CPU consumers
sysutil top

# Throttle iCloud/Spotlight if needed
sysutil throttle
```

### iCloud Sync Using Too Much CPU

```bash
# Check status
sysutil icloud-status

# Throttle processes
sysutil throttle

# If still bad, reset sync state
sysutil icloud-reset
```

### Finding What Woke Your Mac

```bash
sysutil wake-reason
```

---

## File Structure

```
macos-power-toolkit/
├── README.md                           # This file
├── LICENSE                             # MIT licence
├── sysutil                             # Main utility script
├── icloud-throttle.sh                  # Throttle daemon script
├── com.user.icloud-throttle.plist      # Launch daemon config
├── macos-setup.sh                      # Automated setup script
└── docs/
    └── macos-power-management-guide.tex  # LaTeX documentation
```

---

## Tested Configuration

- **Hardware:** MacBook Pro 16,2 (2020, Intel)
- **macOS:** 26.2
- **Chip:** Intel Core i5 with Intel Iris Plus Graphics
- **Bash:** 5.x (via Homebrew)

The toolkit should work on:
- Intel MacBooks (2015–2020)
- Apple Silicon MacBooks (M1/M2/M3)
- macOS 13 Ventura and later

---

## Contributing

Contributions are welcome! If you've encountered similar issues or have improvements:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add new diagnostic'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

### Ideas for Contribution

- [ ] Apple Silicon-specific diagnostics
- [ ] GUI wrapper for sysutil
- [ ] Integration with Homebrew
- [ ] Automated issue detection
- [ ] Menu bar status indicator

---

## 📜 Licence

This project is licensed under the MIT Licence - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgements

- Apple's `pmset` documentation
- The macOS power management community

---

## Disclaimer

These tools modify system settings and kill system processes. While they've been tested extensively on my own machine, use at your own risk. Always have a backup before making system changes.

**This toolkit is not affiliated with or endorsed by Apple Inc.**

---

## Contact

If you find this useful or have questions:

- Open an issue on GitHub
- Star the repository if it helped you!

---

<p align="center">
  <i>Because no laptop should cook itself in a bag.</i>
</p>
