# vzq_launch_resolve.sh -- canonical VZQ sealed-weights launcher resolution (POSIX sh, source-only).
# Single-source "loader wiring" per VZQ_BUNDLE_WIRING.md section 6. Each family's PIPELINE.sh generator sources this
# ONE file and calls vzq_resolve per weight component; the family-specific bits (which checkpoint checks to skip when a
# .vzqup covers them, the S4 env-list wiring) stay in that family's generator per the section-6 table. ADDITIVE and
# back-compat: no vz_vzq_pins member / no line for the component -> vzq_resolve returns 1 and the launcher runs its
# existing checkpoint path byte-for-byte unchanged.
#
# Contract (section 6):
#   1. no vz_vzq_pins, or no line for (model,component)      -> return 1 (legacy, silent)
#   2. candidate first-hit: --vzq($VZQ_OPT) > $VZ_VZQ > $VEIZIK_CACHE/models/<m>/<m>[.<c>].vzqup > $HERE/../vzq > $HERE/vzq
#   3. EXPLICIT (--vzq/$VZ_VZQ) and missing/unreadable        -> exit 3  (input missing; no silent fallback)
#   4. found but size != pinned bytes                         -> exit 4  (integrity; NEVER fall back after a tamper signal)
#   5. non-explicit and nothing found anywhere                -> return 1 (legacy) + one note line
#   6. found + size-checked -> export VZQ_LOAD[2]/VZQ_PIN[2]/VZQ_REL ; return 0. Engine does the header-digest/tag check.
#
# Env hygiene: the launcher must `unset VZQ_CAPTURE VZQ_PROBE VZQ_LOAD VZQ_LOAD2 VZQ_PIN VZQ_PIN2 VZQ_REL VZQ_MODEL`
# at the top (copy the WAN WAN_* clear pattern) BEFORE calling vzq_resolve; this file sets only the resolved values.
# $HERE must be the launcher's own dir (the sealed-inner root). $VZQ_OPT is set by the family's `--vzq FILE` option parse.

vz_vzq_line() {  # $1 model $2 component -> "<digest_hex64> <bytes> <release>" (empty = no VZQ for this component)
  [ -f "$HERE/vz_vzq_pins" ] || return 0
  awk -v m="$1" -v c="$2" '$1=="VZQPIN1" && $2==m && $3==c {print $4, $5, $6; exit}' "$HERE/vz_vzq_pins"
}

vz_vzq_find() {  # $1 model $2 component -> a SEARCH path or nothing (no explicit handling; vzq_resolve does that,
                 # because VZQ_EXPLICIT set here would be lost across the `$(...)` command substitution that calls it)
  for _d in "${VEIZIK_CACHE:-/nonexistent}/models/$1" "$HERE/../vzq" "$HERE/vzq"; do
    for _f in "$_d/$1.$2.vzqup" "$_d/$1.vzqup"; do
      [ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
    done
  done
  return 0
}

# vzq_resolve <model> <component> [slot]  ; slot "" -> VZQ_LOAD/VZQ_PIN(+VZQ_REL) ; slot "2" -> VZQ_LOAD2/VZQ_PIN2
#   returns 0 = a sealed .vzqup is active for this component (exports set) ; 1 = legacy checkpoint path for this component.
vzq_resolve() {
  _m="$1"; _c="$2"; _slot="${3:-}"
  _line="$(vz_vzq_line "$_m" "$_c")"
  [ -n "$_line" ] || return 1                                   # (1) no pin line -> legacy, silent
  _dig="${_line%% *}"; _rest="${_line#* }"; _bytes="${_rest%% *}"; _rel="${_rest##* }"
  # (2) candidate: explicit (--vzq / $VZ_VZQ) wins; else search. Explicit is decided HERE, not in a $()-subshell.
  if [ -n "${VZQ_OPT:-}" ]; then _cand="$VZQ_OPT"; _explicit=1
  elif [ -n "${VZ_VZQ:-}" ]; then _cand="$VZ_VZQ"; _explicit=1
  else _cand="$(vz_vzq_find "$_m" "$_c")"; _explicit=0
  fi
  if [ -z "$_cand" ] || [ ! -r "$_cand" ]; then
    if [ "$_explicit" = 1 ]; then
      echo "VZQ: named sealed weights not found/unreadable: ${VZQ_OPT:-$VZ_VZQ}" >&2; exit 3   # (3)
    fi
    echo "VZQ: no sealed weights found for $_m${_c:+.$_c}, using the checkpoint" >&2; return 1  # (5)
  fi
  _sz="$(wc -c < "$_cand" 2>/dev/null | tr -d ' ')"
  if [ "$_sz" != "$_bytes" ]; then
    echo "VZQ: $_cand size $_sz != pinned $_bytes (integrity) -- refusing; no checkpoint fallback" >&2; exit 4  # (4)
  fi
  _abs="$(cd "$(dirname "$_cand")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$_cand")")"
  if [ "$_slot" = 2 ]; then                                     # (6) second expert
    VZQ_LOAD2="$_abs"; VZQ_PIN2="$_dig"; export VZQ_LOAD2 VZQ_PIN2
  else
    VZQ_LOAD="$_abs"; VZQ_PIN="$_dig"; VZQ_REL="$_rel"; export VZQ_LOAD VZQ_PIN VZQ_REL
  fi
  return 0
}
