#!/usr/bin/env bash

# ------------------------------------------------------------
# gpu.sh
# GPU monitoring with detailed tooltip
# Supports NVIDIA (nvidia-smi) and AMD (sysfs + sensors)
# ------------------------------------------------------------

set -euo pipefail

# Check for NVIDIA GPU
if command -v nvidia-smi &>/dev/null 2>&1; then
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    GPU_MEM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
    GPU_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    GPU_CLOCK=$(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")

    GPU_MEM_USED_GB=$(awk "BEGIN {printf \"%.1f\", $GPU_MEM_USED/1024}")
    GPU_MEM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $GPU_MEM_TOTAL/1024}")

    TOOLTIP="${GPU_NAME}\\n"
    TOOLTIP+="Utilization: ${GPU_UTIL}%\\n"
    TOOLTIP+="Temperature: ${GPU_TEMP}C\\n"
    TOOLTIP+="Memory: ${GPU_MEM_USED_GB}G / ${GPU_MEM_TOTAL_GB}G\\n"
    TOOLTIP+="Clock: ${GPU_CLOCK} MHz\\n"
    TOOLTIP+="Power: ${GPU_POWER} W"

    printf '{"text":"%s%%","tooltip":"%s"}\n' "$GPU_UTIL" "$TOOLTIP"
    exit 0
fi

# Find AMD GPU card (could be card0, card1, etc.)
GPU_CARD=""
for card in /sys/class/drm/card*; do
    # Skip if not a directory or if it's a connector (contains -)
    [[ ! -d "$card" ]] && continue
    [[ "$card" =~ .*-.* ]] && continue

    # Check if this card has a device directory (actual GPU)
    if [[ -d "$card/device" ]]; then
        GPU_CARD="$card"
        break
    fi
done

# Check for AMD GPU via sysfs
if [[ -n "$GPU_CARD" ]] && [[ -d "$GPU_CARD/device" ]]; then
    GPU_NAME="AMD Radeon"

    # Try to get specific GPU name from device
    if [[ -f "$GPU_CARD/device/product_name" ]]; then
        GPU_NAME=$(cat "$GPU_CARD/device/product_name" 2>/dev/null || echo "AMD Radeon")
    fi

    # Get GPU utilization
    GPU_UTIL="0"
    if [[ -f "$GPU_CARD/device/gpu_busy_percent" ]]; then
        GPU_UTIL=$(cat "$GPU_CARD/device/gpu_busy_percent" 2>/dev/null || echo "0")
    fi

    # Get temperatures from sensors (amdgpu)
    GPU_TEMP="N/A"
    GPU_JUNCTION="N/A"
    GPU_MEM_TEMP="N/A"

    if command -v sensors &>/dev/null; then
        SENSOR_OUTPUT=$(sensors amdgpu-pci-* 2>/dev/null || sensors 2>/dev/null)

        # Edge temperature
        TEMP_RAW=$(echo "$SENSOR_OUTPUT" | grep -i "edge" | awk '{print $2}' | tr -d '+°C' || echo "")
        if [[ -n "$TEMP_RAW" ]]; then
            GPU_TEMP="${TEMP_RAW}"
        fi

        # Junction temperature
        JUNCTION_RAW=$(echo "$SENSOR_OUTPUT" | grep -i "junction" | awk '{print $2}' | tr -d '+°C' || echo "")
        if [[ -n "$JUNCTION_RAW" ]]; then
            GPU_JUNCTION="${JUNCTION_RAW}"
        fi

        # Memory temperature
        MEM_RAW=$(echo "$SENSOR_OUTPUT" | grep -i "mem" | awk '{print $2}' | tr -d '+°C' || echo "")
        if [[ -n "$MEM_RAW" ]]; then
            GPU_MEM_TEMP="${MEM_RAW}"
        fi
    fi

    # Get VRAM usage
    GPU_MEM_USED="N/A"
    GPU_MEM_TOTAL="N/A"
    if [[ -f "$GPU_CARD/device/mem_info_vram_used" ]] && [[ -f "$GPU_CARD/device/mem_info_vram_total" ]]; then
        VRAM_USED=$(cat "$GPU_CARD/device/mem_info_vram_used" 2>/dev/null || echo "0")
        VRAM_TOTAL=$(cat "$GPU_CARD/device/mem_info_vram_total" 2>/dev/null || echo "0")
        if [[ "$VRAM_USED" != "0" ]] && [[ "$VRAM_TOTAL" != "0" ]]; then
            GPU_MEM_USED=$(awk "BEGIN {printf \"%.1f\", $VRAM_USED/1024/1024/1024}")
            GPU_MEM_TOTAL=$(awk "BEGIN {printf \"%.1f\", $VRAM_TOTAL/1024/1024/1024}")
        fi
    fi

    # Get clock speed
    GPU_CLOCK="N/A"
    if [[ -f "$GPU_CARD/device/pp_dpm_sclk" ]]; then
        CLOCK_RAW=$(grep '\*' "$GPU_CARD/device/pp_dpm_sclk" 2>/dev/null | awk '{print $2}' | tr -d 'Mhz*' || echo "")
        if [[ -n "$CLOCK_RAW" ]]; then
            GPU_CLOCK="${CLOCK_RAW}"
        fi
    fi

    # Get power draw
    GPU_POWER="N/A"
    if compgen -G "$GPU_CARD/device/hwmon/hwmon*/power1_average" >/dev/null; then
        POWER_UW=$(head -qn1 "$GPU_CARD"/device/hwmon/hwmon*/power1_average 2>/dev/null | head -n1)
        POWER_UW=${POWER_UW:-0}
        if [[ "$POWER_UW" != "0" ]]; then
            GPU_POWER=$(awk "BEGIN {printf \"%.1f\", $POWER_UW/1000000}")
        fi
    fi

    # Build tooltip
    TOOLTIP="${GPU_NAME}\\n"
    TOOLTIP+="Utilization: ${GPU_UTIL}%\\n"
    [[ "$GPU_TEMP" != "N/A" ]] && TOOLTIP+="Edge Temp: ${GPU_TEMP}C\\n"
    [[ "$GPU_JUNCTION" != "N/A" ]] && TOOLTIP+="Junction: ${GPU_JUNCTION}C\\n"
    [[ "$GPU_MEM_TEMP" != "N/A" ]] && TOOLTIP+="Memory: ${GPU_MEM_TEMP}C\\n"
    if [[ "$GPU_MEM_USED" != "N/A" ]] && [[ "$GPU_MEM_TOTAL" != "N/A" ]]; then
        TOOLTIP+="VRAM: ${GPU_MEM_USED}G / ${GPU_MEM_TOTAL}G\\n"
    fi
    [[ "$GPU_CLOCK" != "N/A" ]] && TOOLTIP+="Clock: ${GPU_CLOCK} MHz\\n"
    [[ "$GPU_POWER" != "N/A" ]] && TOOLTIP+="Power: ${GPU_POWER} W"

    # Remove trailing newline if present
    TOOLTIP="${TOOLTIP%\\n}"

    printf '{"text":"%s%%","tooltip":"%s"}\n' "$GPU_UTIL" "$TOOLTIP"
    exit 0
fi

# No GPU found
printf '{"text":"N/A","tooltip":"No GPU detected"}\n'
