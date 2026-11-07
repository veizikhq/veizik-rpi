#!/bin/sh
# veizik-rpi — thin bootstrap installer for the Raspberry Pi 5 and Raspberry Pi Zero 2 W (aarch64).
#
# What it does:
#   1. checks the board (BCM2712 / BCM2710A1) and a 64-bit OS,
#   2. downloads the veizik CLI from the veizik edge CDN and verifies its checksum,
#   3. downloads the sealed engine bundles (language, vision, image + video) and installs them (weightless; small),
#   4. installs the reactive thermal governor (recommended for sustained ML compute).
#
# Model weights are fetched on demand, per model, by `veizik pull`. Everything runs on the board —
# no Python, no PyTorch, no cloud inference. Compute is lease-gated: `veizik activate` licenses the
# device once (a one-time browser approval), after which runs are fully local.
#
# Override the source with VZ_EDGE_BASE=..., the install dir with VZ_BINDIR=... .
set -eu

BASE="${VZ_EDGE_BASE:-https://cdn.veizik.com}"
BINDIR="${VZ_BINDIR:-$HOME/.local/bin}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/veizik-rpi.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

say() { printf '%s\n' "$*"; }

# ---- 1. board + OS support gate -------------------------------------------------------------------
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
COMPAT="$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null || echo '')"
case "$MODEL$COMPAT" in
  *"Raspberry Pi 5"*|*bcm2712*)                            BOARD="Raspberry Pi 5 (BCM2712, Cortex-A76)";;
  *"Raspberry Pi Zero 2 W"*|*"model-zero-2-w"*|*bcm2710*)  BOARD="Raspberry Pi Zero 2 W (BCM2710A1, Cortex-A53)";;
  *) say "veizik-rpi targets the Raspberry Pi 5 and Raspberry Pi Zero 2 W. Detected: $MODEL" >&2; exit 2;;
esac
if [ "$(uname -m)" != aarch64 ]; then
  say "veizik-rpi needs 64-bit Raspberry Pi OS (aarch64). Detected $(uname -m)." >&2; exit 2
fi
command -v curl >/dev/null 2>&1 || { say "curl is required (sudo apt-get install -y curl)." >&2; exit 3; }
command -v sha256sum >/dev/null 2>&1 || { say "sha256sum is required (coreutils)." >&2; exit 3; }
say "veizik-rpi: $BOARD"

# ---- 2. fetch + verify the CLI --------------------------------------------------------------------
say "· downloading the veizik CLI …"
curl -fSL --retry 3 -o "$WORK/veizik" "$BASE/veizik-aarch64"
WANT="$(curl -fsSL "$BASE/SHA256SUMS" | awk '$2=="veizik-aarch64"||$2=="*veizik-aarch64"{print $1; exit}')"
GOT="$(sha256sum "$WORK/veizik" | cut -d' ' -f1)"
if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then
  say "CLI checksum mismatch (expected '${WANT:-?}', got '$GOT') — aborting." >&2; exit 4
fi
mkdir -p "$BINDIR"
install -m 0755 "$WORK/veizik" "$BINDIR/veizik"
say "· veizik CLI installed → $BINDIR/veizik"

# ---- 3. fetch + install the sealed engine bundles -------------------------------------------------
# A bundle installs with the shared-core root placed beside it. Bundles are weightless and small;
# model weights are pulled later, on demand, by `veizik pull <model>`.
curl -fSL --retry 3 -o "$WORK/veizik-shared-core.vzroot" "$BASE/veizik-shared-core.vzroot"
BUNDLES="veizik-edge-llm-linux-aarch64 veizik-edge-cv-linux-aarch64 veizik-sdxs-512-1.0.0-thin-linux-aarch64 veizik-sd15-1.0.0-thin-linux-aarch64 veizik-video-dreamshaper8-lightning8-1.0.0-thin-linux-aarch64"
for B in $BUNDLES; do
  say "· installing engine bundle: $B"
  curl -fSL --retry 3 -o "$WORK/$B.vzpack" "$BASE/$B.vzpack"
  ( cd "$WORK" && "$BINDIR/veizik" install "$WORK/$B.vzpack" ) || {
    say "  (bundle $B failed to install — continuing; retry later with: veizik install <path>)" >&2
  }
done

# ---- 4. thermal governor (recommended) ------------------------------------------------------------
# Sustained ML compute can drive the SoC to the firmware hard-throttle (and, on the Zero 2 W, brown
# out a marginal supply). The reactive governor caps the SoC so long renders finish instead of
# crashing. It needs root; skipped (with a note) if sudo/systemd are unavailable.
GOV=""
for d in "$HOME/.local/state/veizik/engines"/*/*/thermal; do
  [ -f "$d/vz_thermal_governor.sh" ] && { GOV="$d"; break; }
done
if [ -n "$GOV" ] && command -v systemctl >/dev/null 2>&1; then
  if sudo install -D -m 0755 "$GOV/vz_thermal_governor.sh" /opt/veizik/thermal/vz_thermal_governor.sh 2>/dev/null \
     && sudo install -D -m 0644 "$GOV/vz-thermal-governor.service" /etc/systemd/system/vz-thermal-governor.service 2>/dev/null \
     && sudo systemctl daemon-reload 2>/dev/null \
     && sudo systemctl enable --now vz-thermal-governor.service 2>/dev/null; then
    say "· thermal governor installed + enabled (vz-thermal-governor.service)"
  else
    say "· thermal governor NOT installed (needs root/systemd) — recommended before long renders; see the engine's thermal/INSTALL.md"
  fi
fi

# ---- 5. next steps --------------------------------------------------------------------------------
cat <<MSG

veizik-rpi is installed. Next:

  export PATH="$BINDIR:\$PATH"          # if 'veizik' is not on your PATH yet
  veizik activate                       # license this device (one-time browser approval)
  veizik list                           # the models you can run
  veizik pull gpt2-124m                 # fetch a model's weights on demand
  veizik run  gpt2-124m "The capital of France is"
  veizik pull sdxs                      # an image model (weights fetched on demand)
  veizik run  sdxs "a red sports car at sunset"
  veizik serve gpt2-124m                # OpenAI-compatible local API on http://127.0.0.1:8000

Models run only after activation — compute is lease-gated, then fully on-device.
Generated images and video carry an AI-generated provenance mark.
Docs and the model catalogue: https://veizik.com/edge
MSG
