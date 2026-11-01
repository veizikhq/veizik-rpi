# veizik-rpi

Native generative inference on Raspberry Pi — **one package, two boards**: Raspberry Pi 5 and
Raspberry Pi Zero 2 W. Image (SDXS-512, Stable Diffusion 1.5), video (AnimateDiff-Lightning on
DreamShaper-8), and language (GPT-2, SmolLM2, LFM2.5) models, plus SANA-Sprint — measured on the
real boards. The edge engine is arriving soon.

## Install
```bash
./install.sh
```
Detects the board by its model name, selects the matching native runtime, fetches the shared
weight packs, and materializes the on-device cache. On a Raspberry Pi Zero 2 W this gives you a
prompt-to-image render **entirely on the board** (CLIP, tokenizer, noise, diffusion and decode all
on the Pi) in about 75 seconds at 512×512 — nothing precomputed off-device.

## Layout
- `packs/` — shared weight packs (IEEE fp16 masters, arch-agnostic). Shipped as release assets.
- `bin/bcm2712/` — Raspberry Pi 5 / BCM2712 runtime (ARMv8.2, dot-product int8).
- `bin/bcm2710a1/` — Raspberry Pi Zero 2 W / BCM2710A1 runtime (ARMv8.0 NEON, memory-frugal streaming).
- `modes/` — per-board quality/size mode ladder.
- `install.sh` — board detection + pack fetch + materialize.

Weights are chosen per tensor at the number format that fits each board's memory and compute, traded
with a `--mode` flag. Formats and the engine are the product's own; this package carries the public
fp16 masters and the native runtimes.
