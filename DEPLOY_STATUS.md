# veizik-rpi deploy status (develop-lane, private; public flip = operator-direct)

Form: canonical `veizik run <model>` + PIPELINE.sh bundles (zero-CLI-change; VERIFIED on RPi5 for GPT-2).
SoCs: bcm2712 (Raspberry Pi 5, A76 +SDOT) · bcm2710a1 (Raspberry Pi Zero 2 W, A53 NEON).

## Bundleable now (product-path RV done / CURRENT / license-clear + notice)
- gpt2-124m (MIT) · smollm2-135m, smollm2-360m (Apache) · lfm2.5-230m (LFM v1.0, operator-cleared) · taesd (MIT)
- runtimes CURRENT; LLM loader = 57_vzqc materialize.
- ★CANONICAL LLM BUNDLE BUILT (develop-lane): bundles/edge-llm/ — PIPELINE.sh + INTERFACE.json + bin/vzedge_{gpt2,llama,lfm} + vz_vzq_pins(VZQMASTER/VZQPIN) + SHA256SUMS; 5 models (gpt2-124m[+plain]/smollm2-135m/360m/lfm2.5-230m); `veizik run <model>` contract. Packs = release assets (gitignored). aarch64 no-SDOT = serves BOTH SoCs (LLMs measured on A53).

## Gated (HOLD until all pass)
| model | gate |
|---|---|
| sd15-*, sdxs-*, video | (가) 66_sdmode fp16-master materialize RV [video RV probing] · (나) OpenRAIL conditional · (다) 2-SoC whole-bundle e2e |
| sana | te=Gemma-2 EXCLUDED from assets; ships as numbers/demo only |

## Hard gates before PUBLIC flip (operator-direct; edge = develop-lane)
(가) image/video 66_sdmode fp16-master→materialize→product-loader render RV — ★RED (UNWIRED): 79_main_video never calls sdp_attach; vzvideo reads loose .f32, no sdpack. 4 wiring items → engine/runtime lane. Image models same split. BLOCKED until wired.
(나) license asset audit — ZERO violations (Gemma-2 excluded, Hailo HEF excluded, OpenRAIL conditioned, notices present)
(다) 2-SoC whole-bundle e2e: install → materialize from shared fp16 pack → product loader render/decode rc=0 (one-shot.md §6 D-PREAMBLE/D-RUN)
bcm2712 runtime: pending rpi5-lane sha.db registration + RV handoff.
