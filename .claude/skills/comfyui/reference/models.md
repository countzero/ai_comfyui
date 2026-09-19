# FLUX.2 model manifest

Sizes are GiB (bytes ÷ 1024³), verified against the HuggingFace API on
2026-09-19. Repos host `.../resolve/main/<file>`.

## Installed

| Role | File | GiB | Bytes |
|---|---|---|---|
| **DiT (default)** | `models/diffusion_models/flux2_dev_fp8mixed.safetensors` | **33.02** | 35,455,599,592 |
| DiT (alt) | `models/diffusion_models/flux2-dev-Q4_K_M.gguf` | 18.70 | 20,082,414,560 |
| Text encoder | `models/text_encoders/mistral_3_small_flux2_fp4_mixed.safetensors` | 11.43 | 12,275,678,071 |
| VAE | `models/vae/flux2-vae.safetensors` | 0.31 | 336,213,556 |
| Upscaler | `models/upscale_models/4xNomos2_hq_dat2.pth` | 0.13 | 140,196,334 |

Encoder and DiT are **never co-resident** with either DiT.

## fp8 vs GGUF — fp8 wins, use it

| Model | 1 MP | 4 MP |
|---|---|---|
| GGUF Q4_K_M (18.70 GiB) | 88.4s | 335.8s |
| **fp8mixed (33.02 GiB)** | **44.3s** | **213.2s** |
| speedup | **2.00x** | **1.58x** |

GGUF dequantizes to bf16 before every matmul (`ComfyUI-GGUF/ops.py:177`), so its
4-bit format is storage-only and buys no compute. fp8 is native on sm_120. The
dequant overhead beats PCIe: streaming 33 GiB still doubles resident 18.70 GiB.
Quality at matched seed is comparable. Keep GGUF only for footprint.

There is **no NVFP4 FLUX.2** — `split_files/diffusion_models/` holds only
`flux2_dev_fp8mixed.safetensors` (verified via the HF API).

## Upscaler — `4xNomos2_hq_dat2`

From `Phhofm/models`, **CC-BY-4.0** (no non-commercial restriction). DAT2 arch,
4x, tagged `general-upscaler, photo`. Verified sha256
`1f2be2b4786b5031776aed90e1818564f5576ab1e44da9355c7f3788ea25bdea`.

```
https://github.com/Phhofm/models/releases/download/4xNomos2_hq_dat2/4xNomos2_hq_dat2.pth
```

Chosen over restoration-oriented models (`4xRealWebPhoto_v4_dat2`,
`4xNomosWebPhoto_RealPLKSR`) because those assume *degraded* input and
over-process FLUX.2's already-clean output. The "hq" variant is trained for
high-quality input.

Alternatives worth knowing: `4xNomos2_hq_atd` (ATD, stronger but slower,
CC-BY-4.0); `4xNomosWebPhoto_RealPLKSR` (30 MB vs 140 MB if speed matters);
`4x-UltraSharpV2` (kim2091, widely used, but **CC-BY-NC-SA-4.0 — non-commercial**).
`4x-UltraSharp` v1 is Mega-only and not curl-fetchable.

## Resolution behaviour (measured)

An earlier version of this file predicted 4 MP was unreachable on Q4_K_M. **That
was wrong** — it assumed weights must stay VRAM-resident. They don't; DynamicVRAM
streams them from RAM.

Measured on Q4_K_M, same prompt, seed 42, 20 steps:

| Output | MP | Tokens | Time | s/MP | Peak VRAM | Mode |
|---|---|---|---|---|---|---|
| 1024² | 1.05 | 4,096 | 98.6s | 93.9 | 22.23 GiB | flat — resident |
| 1440² | 2.07 | 8,100 | 168.7s | 81.5 | 23.54 GiB | sawtooth — streaming |
| 2048² | 4.19 | 16,384 | 337.4s | 80.5 | 20.91 GiB | streaming |

Peak VRAM *falls* at 4 MP because the allocator evicts more weight blocks to fund
activations. Time is near-linear in pixels and cost per megapixel *improves* with
resolution.

**Consequence for quant choice.** Residency only matters at ~1 MP, where it buys
the flat 98.6s path. Above that everything streams regardless, so the quant
governs *how much* streams (speed) and weight fidelity — not whether a resolution
is reachable. For high-res work a larger quant is defensible: `flux2_dev_fp8mixed`
(33.02 GiB) streams like anything else but carries better weights than Q4_K_M.

**System RAM, not VRAM, is the binding constraint for high-res.** ComfyUI users
report fp8 running on a 12 GB card with 70 GB RAM, while a 24 GB card with 32 GB
RAM fails outright. This box has 191 GiB.

Keep dimensions divisible by 16 (VAE stride), and set width/height on **both**
`EmptyFlux2LatentImage` and `Flux2Scheduler`.

## FLUX.2-dev DiT quants — `city96/FLUX.2-dev-gguf`

City96's K-quants use mixed-precision block logic, so they beat their nominal
bit width. Q4_0 and Q4_K_S are byte-identical; prefer Q4_K_S.

| Quant | GiB | 1 MP |
|---|---|---|
| Q2_K | 11.97 | yes |
| Q3_K_S | 14.69 | yes |
| Q3_K_M | 14.86 | yes |
| Q4_K_S | 17.97 | yes |
| **Q4_K_M** | **18.70** | **installed** |
| Q4_1 | 19.80 | no |
| Q5_K_S | 21.63 | no |
| Q5_K_M | 22.40 | no |
| Q6_K | 25.51 | no |
| Q8_0 | 32.60 | no |
| BF16 | 60.02 | no |

## FLUX.2-dev text encoders — `Comfy-Org/flux2-dev`

Path prefix `split_files/text_encoders/`.

| File | GiB |
|---|---|
| `mistral_3_small_flux2_bf16.safetensors` | 33.14 |
| `mistral_3_small_flux2_fp8.safetensors` | 16.80 |
| **`mistral_3_small_flux2_fp4_mixed.safetensors`** | **11.43 — installed** |

**These are already 30/40-layer pruned.** Unsloth's full
`Mistral-Small-3.2-24B-Instruct-2506-GGUF` BF16 is 43.9 GiB vs Comfy-Org's
33.14 — a 0.755 ratio, matching 30 of 40 layers. FLUX.2's deepest tap is layer
30, so layers 31-39 are dead weight. `flux2_te(pruned=True)` sets
`num_layers=30`, auto-detected when `...layers.39.post_attention_layernorm.weight`
is absent.

Consequence: generic llama.cpp Mistral GGUFs (e.g. unsloth Q4_K_M, 12.44 GiB)
are **larger and slower** than Comfy-Org's fp4_mixed while producing identical
conditioning. Do not substitute them.

GGUF encoders purpose-built for FLUX.2 exist at `gguf-org/flux2-dev-gguf`
(`cow-mistral3-small-{q2_k 7.20, iq4_xs 10.35, q4_0 10.84, q8_0 18.60}.gguf`)
but offer no advantage over fp4_mixed at 1 MP.

## Other FLUX.2-dev files — `Comfy-Org/flux2-dev`

| File | GiB | Note |
|---|---|---|
| `split_files/vae/flux2-vae.safetensors` | 0.31 | installed |
| `split_files/diffusion_models/flux2_dev_fp8mixed.safetensors` | 33.02 | does not fit |
| `split_files/loras/Flux2TurboComfyv2.safetensors` | 2.57 | step-count reduction |

The Turbo LoRA with a GGUF DiT forces on-the-fly patching of quantized weights —
costs VRAM and time. Test without it first.

Note the docs.comfy.org tutorial recommends `flux2_dev_fp8mixed` (33.02) +
`mistral_3_small_flux2_bf16` (33.14) = **66.5 GiB**. That configuration does not
fit 24 GiB and is not what this install uses.

## FLUX.2-klein — the fully-resident alternative

klein is the only FLUX.2 configuration where encoder **and** DiT stay resident
simultaneously, leaving headroom for 2-4 MP output.

**klein-9B** — DiT from `unsloth/FLUX.2-klein-9B-GGUF`, encoder + VAE from
`Comfy-Org/vae-text-encorder-for-flux-klein-9b`:

| Component | GiB |
|---|---|
| `flux-2-klein-9b-Q8_0.gguf` | 9.29 |
| `qwen_3_8b_fp8mixed.safetensors` | 8.07 |
| VAE | 0.31 |
| **Total** | **17.67** — ~6 GiB headroom |

Other DiT quants: BF16 16.91, Q6_K 7.32, Q5_K_M 6.54, Q4_K_M 5.50.
Other encoders: `qwen_3_8b` bf16 15.26, `qwen_3_8b_fp4mixed` 6.34.

**klein-4B** — all safetensors from
`Comfy-Org/vae-text-encorder-for-flux-klein-4b`, 11.12 GiB total:
`flux-2-klein-4b.safetensors` 7.22 + `qwen_3_4b_fp4_flux2.safetensors` 3.58 +
VAE 0.31. Apache-2.0, unlike dev.

Encoders are **not interchangeable** across variants — see SKILL.md. klein-9B
requires Qwen3-8B (12288), klein-4B requires Qwen3-4B (7680).
