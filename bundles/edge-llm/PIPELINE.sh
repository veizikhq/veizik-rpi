#!/bin/sh
# PIPELINE.sh -- veizik EDGE (aarch64 CPU) launcher for the LLM packs (gpt2-124m / smollm2-135m / smollm2-360m / lfm2.5-230m) from the canonical fp16 VZQ container (.vzqup).
# Contract = what `veizik run/serve` drive for every bundle:  ./PIPELINE.sh --model T --prompt-file F --out D [--max-tokens N] [--mode M]
#   env (CLI exports): VZ_VZQ=<pack> VZ_MODE VZ_POWER VZ_ACCEL=<chain> VZ_HYBRID
#   exit 0 ok | 2 usage | 3 input missing | 4 integrity/coherence | 6 runtime/accelerator unavailable, or sealed pack without key
# The pack is the distributed artifact: models/<T>/<T>.vzqup (fp16 common master, sha256 + size pinned in vz_vzq_pins via lib/vzq_launch_resolve.sh, compat id vs shared-core.vzroot).  The five --mode tiers are
# NOT in the pack: models/<T>/modes.tsv maps each tier to a veizik weight format (body / head / rerank / embedding handling / threads) and the runtime requantises the fp16 master AT LOAD.
HERE=$(cd "$(dirname "$0")" && pwd); export HERE
unset VZQ_CAPTURE VZQ_PROBE VZQ_LOAD VZQ_LOAD2 VZQ_PIN VZQ_PIN2 VZQ_REL VZQ_MODEL VZ_FMT VZ_HFMT VZ_Q VZ_HQ VZ_MIXL VZ_RERANK VZ_WTE16 VZ_EMBHEAD VZ_STREAM VZ_CFG VZ_LFM_TYPES VZ_GW VZ_JOB VZ_SPEC
MODEL=""; PF=""; OUT=""; NTOK=32; MODE="${VZ_MODE:-balanced}"
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="$2"; shift 2;; --model=*) MODEL="${1#*=}"; shift;;
    --prompt-file) PF="$2"; shift 2;; --out) OUT="$2"; shift 2;;
    --tokens|--max-tokens|--steps) NTOK="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --seed|--neg-file|--width|--height|--guidance|--resume|--checkpoint-every) shift 2;;   # greedy decode: accepted, unused
    *) echo "PIPELINE: unknown option $1" >&2; exit 2;;
  esac
done
[ -n "$MODEL" ] || { echo "PIPELINE: --model required (installed: $(ls "$HERE/models" | tr '\n' ' '))" >&2; exit 2; }
[ -d "$HERE/models/$MODEL" ] || { echo "PIPELINE: no such model: $MODEL (installed: $(ls "$HERE/models" | tr '\n' ' '))" >&2; exit 2; }
[ -r "$PF" ] || { echo "PIPELINE: --prompt-file missing/unreadable: $PF" >&2; exit 3; }
[ -n "$OUT" ] || OUT="$HOME/veizik-out"; mkdir -p "$OUT" || exit 6
case "$NTOK" in ''|*[!0-9]*) echo "PIPELINE: token count must be a whole number" >&2; exit 2;; esac

# ---- accelerator chain (--accel / VZ_ACCEL; VZ_HYBRID=1 = sugar for the accelerator+cpu chain).  This engine is CPU-only: auto/cpu resolve to cpu; a chain naming an unavailable accelerator is satisfied by a later cpu/auto link, else exit 6. ----
ACCEL="${VZ_ACCEL:-}"; [ -n "$ACCEL" ] || { [ "${VZ_HYBRID:-0}" = 1 ] && ACCEL="hailo8+cpu" || ACCEL="auto"; }
_ok=0
for _t in $(echo "$ACCEL" | tr '+,' '  '); do
  case "$_t" in
    auto|cpu) _ok=1;;
    hailo8|cuda|metal|v3d) ;;
    *) echo "PIPELINE: unknown accelerator '$_t' in VZ_ACCEL=$ACCEL" >&2; exit 2;;
  esac
done
[ "$_ok" = 1 ] || { echo "PIPELINE: accelerator chain '$ACCEL' is not available for $MODEL on this device (strict)" >&2; exit 6; }
ACCEL_USED=cpu

# ---- policy axes: --mode -> format tier ; --power -> threads (+ one-step smaller-tier bias) ----
CORES=$(nproc 2>/dev/null || echo 4); [ "$CORES" -le 4 ] || CORES=4
BIAS=0; PNT=""
case "${VZ_POWER:-auto}" in
  eco|battery) PNT=$((CORES/2)); [ "$PNT" -ge 1 ] || PNT=1; BIAS=1;;
  sustained)   PNT=$((CORES-1)); [ "$PNT" -ge 1 ] || PNT=1;;
  max)         PNT=$CORES;;
  auto)        PNT="";;
  *) echo "PIPELINE: unknown VZ_POWER=${VZ_POWER}" >&2; exit 2;;
esac
if [ "$BIAS" = 1 ]; then case "$MODE" in quality) MODE=balanced;; balanced) MODE=fast;; esac; fi
case "$MODE" in quality|balanced|fast|ultrafast|low-memory) ;; *) echo "PIPELINE: --mode takes quality|balanced|fast|ultrafast|low-memory" >&2; exit 2;; esac

# ---- model metadata + tier -> format table ----
MD="$HERE/models/$MODEL"
[ -r "$MD/model.env" ] && [ -r "$MD/modes.tsv" ] || { echo "PIPELINE: $MODEL has no model.env/modes.tsv" >&2; exit 3; }
. "$MD/model.env"        # ENGINE FAMILY CFG THETA TYPES BOS PRE
_row=$(awk -F'\t' -v m="$MODE" '$1==m {print; exit}' "$MD/modes.tsv")
[ -n "$_row" ] || { echo "PIPELINE: $MODEL: no tier '$MODE' in modes.tsv" >&2; exit 2; }
TIER_NT=$(echo "$_row" | cut -f2); TIER_ENV=$(echo "$_row" | cut -f3)
NT=${PNT:-$TIER_NT}; [ "$CORES" -ge "$NT" ] || NT=$CORES

# ---- resolve + verify the master pack (reused fleet resolver) ----
. "$HERE/lib/vzq_launch_resolve.sh"
vzq_resolve "$MODEL" common || { echo "PIPELINE: no .vzqup for $MODEL" >&2; exit 3; }
PACK="$VZQ_LOAD"
_dg=$(sha256sum "$PACK" | cut -d' ' -f1)
[ "$_dg" = "$VZQ_PIN" ] || { echo "VZQ: $PACK sha256 != pin (integrity) -- refusing" >&2; exit 4; }
case "$(head -c4 "$PACK")" in
  VZQ1) ;;
  VZP1) echo "PIPELINE: $PACK is a non-canonical pack form -- refusing" >&2; exit 4;;
  *)    echo "PIPELINE: $PACK: unknown container magic" >&2; exit 4;;
esac
_fl=$(od -An -tu1 -j7 -N1 "$PACK" | tr -d ' ')
if [ $((_fl & 2)) -ne 0 ]; then echo "PIPELINE: $PACK is sealed; key release for the edge is not wired (operator-direct) -- refusing" >&2; exit 6; fi
VZ_EDGE_COMPAT=$(od -An -tx1 -j8 -N16 "$HERE/shared-core.vzroot" | tr -d ' \n'); export VZ_EDGE_COMPAT
_ml=$(awk -v m="$MODEL" '$1=="VZQMASTER1" && $2==m {print $3, $4; exit}' "$HERE/vz_vzq_pins")
MASTER=${_ml%% *}; _mk=${_ml#* }
[ -n "$MASTER" ] || { echo "PIPELINE: no VZQMASTER1 pin for $MODEL -- refusing" >&2; exit 4; }
if [ "$_mk" = header ]; then
  [ "$(od -An -tx1 -j24 -N32 "$PACK" | tr -d ' \n')" = "$MASTER" ] || { echo "PIPELINE: pack header digest != bundle pin -- refusing" >&2; exit 4; }
else
  head -c 8192 "$PACK" | LC_ALL=C grep -a -q "$MASTER" || { echo "PIPELINE: pack master != bundle pin -- refusing" >&2; exit 4; }
fi

RUNTIME="$HERE/bin/$ENGINE"
[ -x "$RUNTIME" ] || { echo "PIPELINE: runtime missing: $ENGINE" >&2; exit 6; }

# ---- tokenize (lib/bpe.awk, byte-level BPE in POSIX awk; PRE selects the model's pre-tokenizer; BOS prepended when the model wants one) ----
IDS=$(awk -v MODE=enc -v DIR="$MD" -v PRE="$PRE" -f "$HERE/lib/bpe.awk" < "$PF") || { echo "PIPELINE: tokenizer failed" >&2; exit 4; }
[ -z "$BOS" ] || IDS="$BOS $IDS"
NP=$(echo "$IDS" | wc -w); [ "$NP" -ge 1 ] || { echo "PIPELINE: empty prompt" >&2; exit 2; }
CTXMAX=${CTXMAX:-1024}
[ $((NP+NTOK)) -le "$CTXMAX" ] || NTOK=$((CTXMAX-NP))
CTX=$(( (NP+NTOK+31)/32*32 + 32 ))

# ---- run ----
LOG="$OUT/engine.log"
# tier env first (VZ_FMT / VZ_HFMT / VZ_Q / VZ_HQ / VZ_MIXL / VZ_RERANK / VZ_WTE16 / VZ_EMBHEAD / VZ_STREAM), then the model's own shape config
eval "export $TIER_ENV"
[ -z "$CFG" ] || export VZ_CFG="$CFG"
[ -z "$TYPES" ] || export VZ_LFM_TYPES="$TYPES"
VZQ_FAMILY="$FAMILY"; VZQ_ROPE_THETA="$THETA"; export VZQ_FAMILY VZQ_ROPE_THETA
VZ_CTX="$CTX" VZ_AG=32 VZ_PF=1 VZ_NT="$NT" VZ_POOL=1 "$RUNTIME" "$IDS" "$NTOK" > "$LOG" 2>&1; RC=$?
[ "$RC" = 0 ] || { cat "$LOG" >&2; echo "PIPELINE: engine exit $RC" >&2; exit "$RC"; }
GEN=$(sed -n 's/^GEN_IDS: *//p' "$LOG" | head -1)
printf '%s' "$GEN" | awk -v MODE=dec -v DIR="$MD" -f "$HERE/lib/bpe.awk" > "$OUT/completion.txt"
TPS=$(sed -n 's/.*=> \([0-9.]*\) tok\/s.*/\1/p' "$LOG" | head -1)
LOADMS=$(sed -n 's/.*load+pack \([0-9]*\) ms.*/\1/p' "$LOG" | head -1)
PFMS=$(sed -n 's/^prefill [0-9]* tokens: \([0-9]*\) ms.*/\1/p' "$LOG" | head -1)
HWM=$(sed -n 's/.*VmHWM \([0-9]*\) MiB.*/\1/p' "$LOG" | tail -1); RSS=$(sed -n 's/.*VmRSS \([0-9]*\) MiB.*/\1/p' "$LOG" | tail -1)
printf '{"model":"%s","mode":"%s","accel":"%s","residency_source":"fp16-master-requant-at-load","tier_env":"%s","pack_sha256":"%s","master_sha256":"%s","compat_id":"%s","threads":%s,"prompt_tokens":%s,"new_tokens":%s,"load_ms":"%s","prefill_ms":"%s","tok_per_s":"%s","peak_rss_mib":"%s","rss_mib":"%s","gen_ids":"%s"}\n' \
  "$MODEL" "$MODE" "$ACCEL_USED" "$TIER_ENV" "$_dg" "$MASTER" "$VZ_EDGE_COMPAT" "$NT" "$NP" "$NTOK" "$LOADMS" "$PFMS" "$TPS" "$HWM" "$RSS" "$GEN" > "$OUT/result.json"
cat "$PF"; cat "$OUT/completion.txt"; echo
echo "[veizik-edge] $MODEL mode=$MODE accel=$ACCEL_USED src=pack(fp16)+requant[$TIER_ENV] threads=$NT load=${LOADMS}ms ${TPS:+${TPS} tok/s} peakRSS=${HWM}MiB -> $OUT/completion.txt" >&2
exit 0
