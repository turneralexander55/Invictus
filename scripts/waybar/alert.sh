#!/usr/bin/env bash
# ------------------------------------------------------------
# alert.sh: the bar's system alert (docs/look.md, Waybar).
#
# Replaces the GPU, CPU and memory pills. Prints one waybar JSON line.
# Hidden (empty text) while CPU, GPU temperature, RAM and the root disk
# are all under the threshold (90); when one is over, shows that one
# reading in the "hot" class, e.g. "󰢮 94 °C". The tooltip lists all four.
#
# Env (the tests set these; defaults are the real system):
#   ALERT_THRESHOLD   percent or degrees C, default 90
#   ALERT_PROC_STAT   /proc/stat
#   ALERT_MEMINFO     /proc/meminfo
#   ALERT_GPU_TEMP    a file holding the GPU temperature in millidegrees;
#                     default: first /sys/class/hwmon/hwmon*/temp1_input
#                     whose name file says amdgpu
#   ALERT_DF          command printing the root disk use, e.g. "42%"
#   ALERT_CPU_WAIT    seconds between the two CPU samples, default 0.5
# ------------------------------------------------------------
set -u

THRESHOLD="${ALERT_THRESHOLD:-90}"
PROC_STAT="${ALERT_PROC_STAT:-/proc/stat}"
MEMINFO="${ALERT_MEMINFO:-/proc/meminfo}"
CPU_WAIT="${ALERT_CPU_WAIT:-0.5}"

cpu_sample() { awk '/^cpu / { idle = $5 + $6; total = 0; for (i = 2; i <= NF; i++) total += $i; print idle, total; exit }' "$PROC_STAT"; }

# CPU: busy share between two samples
read -r idle1 total1 < <(cpu_sample)
sleep "$CPU_WAIT"
read -r idle2 total2 < <(cpu_sample)
cpu=0
if [[ -n "${total1:-}" && -n "${total2:-}" ]]; then
    dt=$((total2 - total1))
    di=$((idle2 - idle1))
    (( dt > 0 )) && cpu=$(( (100 * (dt - di) + dt / 2) / dt ))
fi

# RAM: used share of MemTotal (MemAvailable counts as free)
ram=$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { if (t > 0) printf "%d", 100 * (t - a) / t; else print 0 }' "$MEMINFO")

# Root disk
if [[ -n "${ALERT_DF:-}" ]]; then
    disk=$(eval "$ALERT_DF")
else
    disk=$(df --output=pcent / 2>/dev/null | tail -n 1)
fi
disk=${disk//[!0-9]/}
disk=${disk:-0}

# GPU temperature in degrees C (blank when there is no AMD GPU sensor)
gpu=""
temp_file="${ALERT_GPU_TEMP:-}"
if [[ -z "$temp_file" ]]; then
    for dir in /sys/class/hwmon/hwmon*; do
        if [[ "$(cat "$dir/name" 2>/dev/null)" == "amdgpu" && -r "$dir/temp1_input" ]]; then
            temp_file="$dir/temp1_input"
            break
        fi
    done
fi
if [[ -n "$temp_file" && -r "$temp_file" ]]; then
    milli=$(cat "$temp_file" 2>/dev/null)
    [[ "$milli" =~ ^[0-9]+$ ]] && gpu=$((milli / 1000))
fi

text=""
class=""
if [[ -n "$gpu" ]] && (( gpu >= THRESHOLD )); then text="󰢮 ${gpu} °C"; class="hot"
elif (( cpu >= THRESHOLD )); then text="󰻠 ${cpu}%"; class="hot"
elif (( ram >= THRESHOLD )); then text="󰘚 ${ram}%"; class="hot"
elif (( disk >= THRESHOLD )); then text="󰋊 ${disk}%"; class="hot"
fi

gpu_text="n/a"
[[ -n "$gpu" ]] && gpu_text="${gpu} °C"
tooltip="CPU ${cpu}%\\nGPU ${gpu_text}\\nRAM ${ram}%\\nDisk / ${disk}%"
printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tooltip"
