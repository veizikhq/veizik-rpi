# veizik-rpi

**Native generative AI on a Raspberry Pi.** One package runs language, image and video models
*entirely on the board* — CLIP, tokenizer, diffusion and VAE decode all on the Pi's own CPU, nothing
precomputed off-device, no cloud, no Python, no PyTorch. One engine, two boards: the Raspberry Pi 5
(BCM2712) and the palm-sized, 512 MB Raspberry Pi Zero 2 W (BCM2710A1).

> **The edge engine is arriving soon.** This repository describes what ships and how it was measured.
> Packages are published as signed release assets when the edge build is cleared for download; until
> then the boards, models and numbers below are the measured state, not an install you can run today.

<p align="center">
  <img src="https://veizik.com/media/edge/sdxs_landscape.webp" width="30%" alt="A snow-capped mountain reflected in a still lake, generated on a Raspberry Pi 5.">
  <img src="https://veizik.com/media/edge/lcm_sd15_mountain.webp" width="30%" alt="A mountain lake at sunrise, Stable Diffusion 1.5 generated on a Raspberry Pi 5.">
  <img src="https://veizik.com/media/edge/zero2w_lighthouse.webp" width="30%" alt="A lighthouse on a cliff, generated end-to-end on a 512 MB Raspberry Pi Zero 2 W.">
</p>
<p align="center"><sub>AI-generated on Raspberry Pi hardware · left &amp; centre: Pi 5 CPU · right: Pi Zero 2 W (512 MB), prompt→image in ~75 s on the board. More at <a href="https://veizik.com/edge">veizik.com/edge</a>.</sub></p>

## Why this exists

Local-inference runtimes expect a GPU, or a laptop-class CPU and gigabytes of RAM. The Raspberry Pi
has neither. veizik treats the four little Cortex-A cores as the compute budget and designs *down* to
them: a from-scratch native engine (no BLAS, no ONNX Runtime, no llama.cpp underneath) with a
proprietary per-tensor mixed-precision weight ladder, so each tensor is carried at the smallest number
format that holds its quality on *that* board. The result is generative models — a full Stable
Diffusion image, a short animation, a chatting language model — running on a $35 computer, and image
generation on a $15 one.

It is built to **win on the device the user actually owns**: measured against the other runtimes that
run on the same Raspberry Pi, at matched output quality, not against a datacenter GPU.

## Boards and models

| Board | SoC / cores | RAM | What runs |
|---|---|---|---|
| **Raspberry Pi 5** | BCM2712 · 4× Cortex-A76 (ARMv8.2, SDOT int8) | 8 GB | Language (GPT-2, SmolLM2-135M/360M, LFM2.5-230M), image (SDXS-512, Stable Diffusion 1.5, SANA-Sprint 0.6B @1024²), short video (AnimateDiff-Lightning on DreamShaper-8), and a growing computer-vision set |
| **Raspberry Pi Zero 2 W** | BCM2710A1 · 4× Cortex-A53 (ARMv8.0 NEON) | 512 MB | Language (GPT-2, SmolLM2-135M) and image (SDXS-512, full prompt→image on the board) — memory-frugal streaming runtime |

Every model is shipped as a weightless, sealed per-model package; the public fp16 master weights are
fetched separately by `veizik pull` and prepared into the on-device cache. Models roll out one at a
time as each board's build is cleared — see [the catalogue](https://veizik.com/models#catalogue) for
current status.

**With a Hailo AI accelerator (optional):** a Raspberry Pi 5 paired with the Hailo-8 (26 TOPS) or
Hailo-8L (13 TOPS) AI HAT+ runs the accelerated image path through HailoRT (MIT-licensed). Hailo
performance figures are covered by the Hailo EULA and are not published here.

## The quality ladder — one model, five `--mode` tiers

A single installed model answers a `--mode` flag that trades memory and speed against output quality:
`quality` · `balanced` (default) · `fast` · `ultrafast` · `low-memory`. Under the hood each tier is a
different per-tensor assignment of the engine's own number formats — the layout is proprietary and is
not exposed; what you choose is a tier, and what you get is published as a measured outcome below.

<p align="center">
  <img src="https://veizik.com/media/edge/ladder_sdxs_native_pi.webp" width="48%" alt="SDXS-512 rendered at five quality tiers on a Raspberry Pi 5.">
  <img src="https://veizik.com/media/edge/ladder_sd15_native_pi.webp" width="48%" alt="Stable Diffusion 1.5 at 25 steps across five tiers with an fp32 reference, on a Raspberry Pi 5.">
</p>
<p align="center"><sub>AI-generated on a Raspberry Pi 5 CPU. Left: SDXS tier ladder. Right: SD1.5 25-step ladder with the fp32 reference at far left.</sub></p>

## Measured on the real boards

Every figure below was taken on the named board; LLM comparisons are at **matched quality** (same
WikiText-2 perplexity band, same token ids) and image comparisons at **equal output and equal clock**,
against the frontier runtime that runs on that same Pi. Numbers are **warm** (steady-state, after the
first run); a cold first run and the sealed customer path are slower. These are development-tree
measurements unless marked otherwise.

### Raspberry Pi 5 — language

| Model | Metric | veizik | Same-board frontier runtime | Result |
|---|---|---|---|---|
| GPT-2 124M | decode @ matched PPL ≈30 | 104 tok/s | llama.cpp Q4_K_M + F16 head, 86 tok/s | **1.21× faster** |
| GPT-2 124M | peak memory (low-memory tier) | 110 MiB | llama.cpp 161–170 MiB | **1.5× smaller** |
| SmolLM2-135M | decode @ matched quality | 98–110 tok/s | llama.cpp Q4_K_M, 102 tok/s | **1.06–1.08×** |
| SmolLM2-135M | prefill (pp512) | 747 tok/s | llama.cpp Q4_0, 653 tok/s | **1.14× faster** |
| LFM2.5-230M | decode @ matched quality | 82 tok/s | llama.cpp Q4_K_M imatrix, 75 tok/s | **1.08×** |
| LFM2.5-230M | resident memory | 171 MiB | 314 MiB | **1.8× smaller** |

### Raspberry Pi 5 — image

| Model | Metric | veizik | Same-board frontier runtimes | Result |
|---|---|---|---|---|
| SDXS-512 | warm end-to-end, equal clock (1.8 GHz), equal output | 6.47 s | TFLite+XNNPACK 7.47 s · ORT-CPU 7.51 s · ORT+XNNPACK 10.4–11.5 s · TFLite 20.4 s | **1.15–3.15× faster** |
| SDXS-512 | peak RAM | 1.9 GB | 3.3–4.4 GB | **~2× less** |
| SDXS-512 | stability at 2.4 GHz | 0 resets | ORT+XNNPACK hard-reset 3/3 | **finishes where others crash** |
| SANA-Sprint 0.6B @1024² | warm end-to-end at oracle quality | C runner (fp32 path) | ORT-CPU / ORT-XNNPACK / TFLite | **1.7–2.6× faster, 4–6.5× less RAM** |
| Stable Diffusion 1.5, full 25 steps | warm end-to-end @1.8 GHz | ≈249 s | *(no same-board runtime measured at 25 steps)* | runs the full model on four CPU cores |

> SANA-Sprint's speed and memory wins come with a quality trade: veizik's shipped path is 2.3–2.9 dB
> lower PSNR than the 8-bit ONNX reference. We publish the number rather than claim parity.

### Raspberry Pi Zero 2 W (512 MB)

| Model | Metric | veizik | Same-board frontier runtime | Result |
|---|---|---|---|---|
| SmolLM2-135M | decode @ matched quality | 17.7 tok/s | llama.cpp Q8_0 13.6 / Q5_0 16.6 | **+8% to +30%** |
| GPT-2 124M | peak memory | 98–108 MiB | llama.cpp 179–185 MiB | **1.7–1.9× smaller** |
| SDXS-512 | full prompt→image on the board | ≈75 s, ~242 MiB peak | *(no same-board image runtime measured)* | a diffusion model on a 512 MB board |

### Where the other runtimes win (so you can choose honestly)

veizik does not win everywhere, and a runtime README should say so.

- **LLM prefill on the Pi 5** is llama.cpp's: the Cortex-A76 has no `i8mm`, so veizik's prefill trails
  Q4_0 by ~7–8%. veizik's advantage is **decode** and **memory footprint**, which is what matters for
  interactive, memory-starved boards.
- **SmolLM2-360M 4-bit decode** trails llama.cpp by ~3–10%.
- **On the Zero 2 W**, llama.cpp decodes GPT-2 faster (≈1.1–1.3×) and prefills 2.5–3× faster; veizik's
  win on that board is a **1.7–1.9× smaller memory footprint** — often the difference between running
  and not running at all in 512 MB.
- **Computer-vision models**: for batch-1 convolution, int8 is already the arithmetic speed floor on
  these cores, so veizik's CV advantage is **model size at equal accuracy**, not latency.

## Install (when the edge build is published)

```bash
./install.sh
```

`install.sh` detects the board from its model name, selects the matching native runtime, fetches the
shared weight packs, and materializes the on-device cache. Then, the same command vocabulary as every
other veizik package:

```bash
veizik activate                       # once per board; online activation, keeps a valid lease
veizik run smollm2_135m "Write a haiku about the sea." --tokens 64
veizik run sdxs "a lighthouse on a cliff at golden hour" --mode balanced --out ./out
```

- **Online activation is required.** The board activates on first use (`veizik activate`) and keeps a
  valid licence through periodic online verification. All inference — CLIP, tokenizer, diffusion,
  decode — then runs entirely on the board.
- **Weights are not bundled.** Each package is weightless and sealed; `veizik pull <model>` fetches the
  public fp16 master and prepares the on-device cache. Model weights stay under their publisher's
  licence.
- Image output is written to the `--out` folder; text to `gen.txt`. `veizik run <model> --help` gives
  the per-model flags.

## Repository layout

- `packs/` — shared weight packs (IEEE fp16 masters, architecture-agnostic), shipped as release assets.
- `bin/bcm2712/` — Raspberry Pi 5 runtime (ARMv8.2, SDOT int8 tiling).
- `bin/bcm2710a1/` — Raspberry Pi Zero 2 W runtime (ARMv8.0 NEON, memory-frugal streaming).
- `modes/` — per-board quality/size `--mode` ladder.
- `install.sh` — board detection, pack fetch, cache materialize.

The number formats and the engine are the product's own; this repository carries the public fp16
masters and the native runtimes, not the proprietary layout.

## Limits and cautions

- **Pick the image model by board.** SDXS-512 is the image model for the **Raspberry Pi Zero 2 W**
  (fits in ~242 MB). **Stable Diffusion 1.5 is Raspberry Pi 5-only** — it does not fit the Zero 2 W's
  512 MB and the sealed path is killed out-of-memory there. On the Pi 5, SDXS is the fast path and
  SD1.5 is the full-quality path.
- **Numbers are warm.** Steady-state figures above assume the model is already resident. A cold first
  run, and the sealed customer path, are slower and use more peak memory than the warm dev-tree figure.
- **Boards vary.** Two nominally identical Zero 2 W boards measured ~18% apart; thermals and the power
  supply dominate. Give the board a steady supply (a Zero 2 W wants a clean 5 V / 2.5 A).
- **Activation needs the network.** First activation and periodic re-verification are online; inference
  is offline. A board that cannot reach the licence service will not start a new session.
- **Not in the edge build:** Hailo HEF binaries and any Hailo performance figures (Hailo EULA), power
  measurements, and the computer-vision latency board (only size-at-accuracy is published for CV).

## Licences and provenance

- veizik runtime and formats: see [LICENSES](LICENSES) and [NOTICE](NOTICE). Personal, educational,
  research and evaluation use at no charge; commercial use needs a separate licence from LinkPick.
- **Model weights stay under their publishers' licences**, and some have conditions you must honour:
  - **LFM2.5** is free to use while your revenue stays under the publisher's US$10M threshold.
  - **SANA** is research-only as shipped (its text encoder is under the Gemma Terms; Gemma weights are
    not redistributed here).
  - **AnimateDiff-Lightning** is used at 4- or 8-step; the 1-step configuration is research-only.
  - The OpenPose pose model is **non-commercial**.
- **Every generated image and video is AI-generated** and carries a visible label plus an in-pixel/XMP
  provenance mark. Do not present a generated result as a photograph.

---

*Raspberry Pi is a trademark of Raspberry Pi Ltd. Hailo and Hailo-8 are names of Hailo Technologies
Ltd. veizik is not affiliated with, or endorsed by, either. veizik is a brand of LinkPick, Seoul.*
