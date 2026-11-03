#!/bin/bash
# veizik-rpi installer — one package, two boards, keyed by Broadcom SoC codename (Raspberry Pi's own
# designation, as used by the board dtbs: bcm2712-rpi-5-b, bcm2710-rpi-zero-2-w).
#   bcm2712    = Raspberry Pi 5           (ARMv8.2 Cortex-A76, +SDOT/i8mm)
#   bcm2710a1  = Raspberry Pi Zero 2 W    (ARMv8.0 Cortex-A53, NEON fallback, memory-frugal)
# Shared fp16 common packs are arch-agnostic (IEEE fp16, compat_id ad06dab6); runtimes are per-SoC.
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
COMPAT="$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null || echo '')"
MEMKB="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
case "$MODEL$COMPAT" in
  *"Raspberry Pi 5"*|*bcm2712*)                   SOC=bcm2712;   DEF_MODE=quality ;;
  *"Raspberry Pi Zero 2 W"*|*"model-zero-2-w"*)   SOC=bcm2710a1; DEF_MODE=balanced ;;
  *) echo "Unsupported board: $MODEL (targets bcm2712 / bcm2710a1 = Raspberry Pi 5 / Zero 2 W)"; exit 2 ;;
esac
[ "$MEMKB" -lt 1048576 ] && DEF_MODE=low-memory
BINDIR="$ROOT/bin/$SOC"
echo "veizik-rpi: $MODEL -> SoC $SOC, ${MEMKB}kB RAM, default mode=$DEF_MODE"
[ -x "$BINDIR/vzsd15z_accel" ] || { echo "runtime for $SOC not present in this package ($BINDIR)"; exit 3; }
PACKS="${VZ_PACKS:-$ROOT/packs}"; mkdir -p "$HOME/.veizik/edge"
# MANDATORY: reactive thermal governor for ML compute -- caps the SoC <=76C so sustained SD/SANA/LLM
# renders complete instead of hitting the 80C firmware hard-throttle + OOM-crashing the board.
if [ -d "$ROOT/thermal" ]; then
  if sudo install -D -m755 "$ROOT/thermal/vz_thermal_governor.sh" /opt/veizik/thermal/vz_thermal_governor.sh 2>/dev/null \
     && sudo install -D -m644 "$ROOT/thermal/vz-thermal-governor.service" /etc/systemd/system/vz-thermal-governor.service 2>/dev/null \
     && sudo systemctl daemon-reload 2>/dev/null && sudo systemctl enable --now vz-thermal-governor.service 2>/dev/null; then
    echo "thermal governor: installed + enabled (vz-thermal-governor.service, reactive <=76C cap)"
  else
    echo "WARNING: thermal governor NOT installed (needs root/systemd). ML renders may overheat/crash -- see thermal/INSTALL.md"
  fi
fi
# POWER REQUIREMENT -- inadequate/shared power is the #1 cause of mid-render crashes on the Zero 2 W:
# under sustained multi-core ML inference the current spikes sag the 5V rail -> undervoltage brownout ->
# the board resets/hangs. (Verified: a starved passive hub crashed 4-thread loads in minutes; on adequate
# direct power the same 4-core full load ran clean, vcgencmd get_throttled=0x0 throughout.)
case "$SOC" in
  bcm2710a1)
    echo "POWER: use a quality 5V supply rated for sustained >=2.5A (official Raspberry Pi 5.1V/2.5A micro-USB"
    echo "       supply is ideal) + a short, thick cable. Do NOT power from a passive/shared USB hub or an"
    echo "       underrated multi-port charger -- multi-core ML load will brown it out mid-render."
    echo "       Underpower check: 'vcgencmd get_throttled' -- undervoltage = bit 0x1 (now) / 0x10000 (since boot)."
    echo "       If power is marginal, run fewer threads (--power eco); but adequate power is the real fix." ;;
  bcm2712)
    echo "POWER: use the recommended official Raspberry Pi 5 power supply." ;;
esac
echo "Install OK. Runtime: $BINDIR  Packs: $PACKS  (materialize per-mode via --mode.)"
echo "Verify install: 'veizik status'  (lists installed models + activation state)."
echo "Render: activate first ('veizik activate'), then 'veizik run sdxs-512' (sealed, lease-gated, fully on-device; 'veizik run --help' for prompt/seed/mode)."
