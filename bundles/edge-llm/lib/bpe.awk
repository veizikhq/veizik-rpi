# bpe.awk -- GPT-2 byte-level BPE in POSIX awk (mawk/gawk), byte-oriented.  No python, no unicode support needed.
#   encode: awk -v MODE=enc -v DIR=<dir with vocab.tsv merges.tsv> -f bpe.awk < prompt.txt   -> "id id id ..."
#   decode: awk -v MODE=dec -v DIR=<dir>                          -f bpe.awk < ids.txt      -> raw text bytes
# PRE=gpt2 (default) | gpt2d (GPT-2 regex after splitting every digit out, SmolLM2) | l3 (Llama-3-style regex of LFM2.5: contractions i, [^\r\n\p{L}\p{N}]?\p{L}+, \p{N}{1,3}, space?punct+[\r\n]*, \s*[\r\n]+, \s+(?!\S), \s+)
# Pre-tokenisation (PRE=gpt2) = the GPT-2 regex  's|'t|'re|'ve|'m|'ll|'d| ?L+| ?N+| ?[^sLN]+|s+(?!S)|s+  implemented by hand;
# letters = A-Za-z and every byte >= 128 (UTF-8 continuation of a letter is treated as a letter: approximation, ASCII exact).
function isL(c) { return (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || ORD[c] >= 128 }
function isN(c) { return c >= "0" && c <= "9" }
function isS(c) { return c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\f" || c == "\v" }
function hexb(c) { return sprintf("%02x", ORD[c]) }
function bpe(s,    n, i, k, best, bi, a, b, m, np, out, w) {
  n = length(s); if (n == 0) return ""
  for (i = 1; i <= n; i++) P[i] = hexb(substr(s, i, 1))
  while (n > 1) {
    best = 1e9; bi = 0
    for (i = 1; i < n; i++) { k = P[i] " " P[i+1]; if ((k in RK) && RK[k] < best) { best = RK[k]; bi = i; m = k } }
    if (!bi) break
    split(m, ab, " "); a = ab[1]; b = ab[2]; np = 0
    for (i = 1; i <= n; i++) {
      if (i < n && P[i] == a && P[i+1] == b) { Q[++np] = a b; i++ } else Q[++np] = P[i]
    }
    for (i = 1; i <= np; i++) P[i] = Q[i]
    n = np
  }
  out = ""
  for (i = 1; i <= n; i++) { if (!(P[i] in V)) { print "bpe: token not in vocab: " P[i] > "/dev/stderr"; exit 3 } out = out (out == "" ? "" : " ") V[P[i]] }
  return out
}
function emit(tok) { if (tok == "") return; r = bpe(tok); if (r != "") res = res (res == "" ? "" : " ") r }
BEGIN {
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
  for (i = 0; i < 16; i++) HV[substr("0123456789abcdef", i + 1, 1)] = i
  while ((getline line < (DIR "/vocab.tsv")) > 0) { split(line, f, "\t"); V[f[1]] = f[2]; I[f[2]] = f[1] }
  if (MODE == "enc") { n = 0; while ((getline line < (DIR "/merges.tsv")) > 0) RK[line] = n++ }
  RS = "\001"
}
function isP(c) { return !isL(c) && !isN(c) && !isS(c) }
function isNL(c) { return c == "\r" || c == "\n" }
function enc_l3(    c, j, k, e, m, t2, t3) {
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == "'") {
      t2 = tolower(substr(s, i, 2)); t3 = tolower(substr(s, i, 3))
      if (t2 == "'s" || t2 == "'t" || t2 == "'m" || t2 == "'d") { emit(substr(s, i, 2)); i += 2; continue }
      if (t3 == "'re" || t3 == "'ve" || t3 == "'ll") { emit(substr(s, i, 3)); i += 3; continue }
    }
    if (isL(c)) j = i; else if (!isNL(c) && !isN(c)) j = i + 1; else j = 0
    if (j > 0 && j <= L && isL(substr(s, j, 1))) { k = j; while (k <= L && isL(substr(s, k, 1))) k++; emit(substr(s, i, k - i)); i = k; continue }
    if (isN(c)) { k = i; while (k <= L && k - i < 3 && isN(substr(s, k, 1))) k++; emit(substr(s, i, k - i)); i = k; continue }
    j = i; if (c == " ") j = i + 1
    if (j <= L && isP(substr(s, j, 1))) { k = j; while (k <= L && isP(substr(s, k, 1))) k++; while (k <= L && isNL(substr(s, k, 1))) k++; emit(substr(s, i, k - i)); i = k; continue }
    if (isS(c)) {
      e = i; while (e <= L && isS(substr(s, e, 1))) e++
      m = 0; for (k = e - 1; k >= i; k--) if (isNL(substr(s, k, 1))) { m = k; break }
      if (m > 0) { emit(substr(s, i, m - i + 1)); i = m + 1; continue }
      if (e > L) { emit(substr(s, i, e - i)); i = e; continue }
      if (e - i > 1) { emit(substr(s, i, e - i - 1)); i = e - 1; continue }
      emit(substr(s, i, 1)); i = i + 1; continue
    }
    emit(c); i++
  }
}
MODE == "enc" {
  s = $0; L = length(s); i = 1; res = ""
  if (PRE == "l3") { enc_l3(); print res; next }
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == "'") {
      t2 = substr(s, i, 2); t3 = substr(s, i, 3)
      if (t2 == "'s" || t2 == "'t" || t2 == "'m" || t2 == "'d") { emit(t2); i += 2; continue }
      if (t3 == "'re" || t3 == "'ve" || t3 == "'ll") { emit(t3); i += 3; continue }
    }
    j = i; lead = ""
    if (c == " " && i < L) { nc = substr(s, i + 1, 1); if (!isS(nc) && !(PRE == "gpt2d" && isN(nc))) { lead = " "; j = i + 1 } }
    d = substr(s, j, 1)
    if (isL(d)) { k = j; while (k <= L && isL(substr(s, k, 1))) k++; emit(lead substr(s, j, k - j)); i = k; continue }
    if (isN(d)) { k = j; if (PRE == "gpt2d") k = j + 1; else while (k <= L && isN(substr(s, k, 1))) k++; emit(lead substr(s, j, k - j)); i = k; continue }
    if (!isS(d)) { k = j; while (k <= L && !isS(substr(s, k, 1)) && !isL(substr(s, k, 1)) && !isN(substr(s, k, 1))) k++; emit(lead substr(s, j, k - j)); i = k; continue }
    # whitespace run starting at i
    k = i; while (k <= L && isS(substr(s, k, 1))) k++
    if (k <= L && k - i > 1) { emit(substr(s, i, k - i - 1)); i = k - 1 }   # \s+(?!\S): leave last ws for the next token
    else { emit(substr(s, i, k - i)); i = k }
  }
  print res
}
MODE == "dec" {
  nf = split($0, ids, /[^0-9]+/)
  for (q = 1; q <= nf; q++) {
    if (ids[q] == "") continue
    h = I[ids[q]]
    for (z = 1; z < length(h); z += 2) printf("%c", HV[substr(h, z, 1)] * 16 + HV[substr(h, z + 1, 1)])
  }
}
