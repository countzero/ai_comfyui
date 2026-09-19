# FLUX.2 model manifest

Sizes are GiB (bytes ÷ 1024³). Repos host `.../resolve/main/<file>`.

Hardware-specific timings live in the profile docs, not here:
[`hardware-16gb-ada.md`](./hardware-16gb-ada.md) (current) and
[`hardware-24gb-blackwell.md`](./hardware-24gb-blackwell.md) (archived).

## Installed

| Role | File | GiB |
|---|---|---|
| **DiT (distilled)** | `models/diffusion_models/flux-2-klein-9b-fp8.safetensors` | **8.79** |
| **DiT (base)** | `models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors` | **8.91** |
| **Text encoder** | `models/text_encoders/qwen_3_8b_fp8mixed.safetensors` | **8.07** |
| VAE | `models/vae/flux2-vae.safetensors` | 0.31 |
| Upscaler | `models/upscale_models/4xNomos2_hq_dat2.pth` | 0.13 |
| Upscaler (alt) | `models/upscale_models/4x-ESRGAN.pth` | 0.06 |

Klein 9B is **non-commercial licensed** (the 4B variants are Apache-2.0).

DiT + encoder + VAE = 17.3 GiB, so they do **not** co-reside in the current
card's 14.76 GiB usable. An earlier revision of this file claimed klein was "the
only FLUX.2 configuration where encoder and DiT stay resident simultaneously" —
that was computed against 24 GiB and is false here.

**No FLUX.2-dev files remain installed.** Restoring that profile costs ~45 GiB:
`flux2_dev_fp8mixed.safetensors` (33.02) plus a Mistral encoder (11.43 fp4_mixed).

## Klein 9B sources

Diffusion models require accepting BFL's licence on HuggingFace first.

| File | Repo |
|---|---|
| `flux-2-klein-9b-fp8.safetensors` | `black-forest-labs/FLUX.2-klein-9b-fp8` |
| `flux-2-klein-base-9b-fp8.safetensors` | `black-forest-labs/FLUX.2-klein-base-9b-fp8` |
| `qwen_3_8b_fp8mixed.safetensors` | `Comfy-Org/flux2-klein-9B`, `split_files/text_encoders/` |
| `flux2-vae.safetensors` | `Comfy-Org/flux2-dev`, `split_files/vae/` |

Both BFL model cards state the 9B models "fit in ~29GB VRAM … RTX 4090 and
above". That is the bf16 reference pipeline; the fp8 checkpoints above run in
8.8 GiB and work fine on a 16 GiB card with the encoder evicting between passes.

Other klein 9B encoder quants: `qwen_3_8b` bf16 15.26, `qwen_3_8b_fp4mixed` 6.34.
The fp4 variant would cut the ~7.4–8.4s encoder reload penalty and is worth
testing if prompt-churn dominates your workload.

Current Comfy-Org templates reference a newer VAE,
`full_encoder_small_decoder.safetensors`, instead of `flux2-vae.safetensors`. The
klein docs list `flux2-vae` for 9B and it is what is installed and verified, so
the newer VAE is optional.

**klein-4B** — Apache-2.0, all safetensors from
`Comfy-Org/vae-text-encorder-for-flux-klein-4b`, 11.12 GiB total:
`flux-2-klein-4b.safetensors` 7.22 + `qwen_3_4b_fp4_flux2.safetensors` 3.58 +
VAE 0.31. Needs `qwen_3_4b`, not `qwen_3_8b`.

## Encoders are not interchangeable

FLUX.2 concatenates three intermediate hidden layers, so conditioning width is
fixed by architecture and cannot be changed by config.

| Model | Required encoder | Taps | Width |
|---|---|---|---|
| FLUX.2-dev (32B) | Mistral-Small-3 24B | 10,20,30 | 15360 |
| FLUX.2-klein-9B | Qwen3-8B | 9,18,27 | 12288 |
| FLUX.2-klein-4B | Qwen3-4B | 9,18,27 | 7680 |

`CLIPLoader` takes `type=flux2` for **all** of them; ComfyUI auto-detects which
encoder a checkpoint is from its state dict (`comfy/sd.py:1880-1936`).

## Upscaler — `4xNomos2_hq_dat2`

From `Phhofm/models`, **CC-BY-4.0** (no non-commercial restriction). DAT2 arch,
4x, tagged `general-upscaler, photo`. Verified sha256
`1f2be2b4786b5031776aed90e1818564f5576ab1e44da9355c7f3788ea25bdea`,
140,196,334 bytes.

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

## fp8 vs GGUF — fp8 wins

Measured on the archived Blackwell box with FLUX.2-dev, but the *reason* is
architectural and applies to any card with native fp8 (sm_89 and sm_120 both
report `supports_fp8_compute() == True`):

| Model | 1 MP | 4 MP |
|---|---|---|
| GGUF Q4_K_M (18.70 GiB) | 88.4s | 335.8s |
| **fp8mixed (33.02 GiB)** | **44.3s** | **213.2s** |
| speedup | **2.00x** | **1.58x** |

GGUF dequantizes to bf16 before every matmul (`ComfyUI-GGUF/ops.py:177`), so its
4-bit format is storage-only and buys no compute. Quality at matched seed is
comparable. Keep GGUF only for footprint.

**GGUF support stays installed.** The `vendor/ComfyUI-GGUF` submodule,
`rebuild_comfyui.ps1:99` and `requirements_override.txt:18` are all in place so
`UnetLoaderGGUF` registers. Do not rip out the wiring.

`GET /models/diffusion_models` returns nothing for `.gguf` files — that extension
is not in ComfyUI's default set. Query `/models/unet_gguf` instead.

## FLUX.2-dev DiT quants — `city96/FLUX.2-dev-gguf`

Kept for reference if the dev profile is ever restored. City96's K-quants use
mixed-precision block logic, so they beat their nominal bit width. Q4_0 and
Q4_K_S are byte-identical; prefer Q4_K_S. The "1 MP" column is whether it fit the
old 24 GiB card.

| Quant | GiB | 1 MP |
|---|---|---|
| Q2_K | 11.97 | yes |
| Q3_K_S | 14.69 | yes |
| Q3_K_M | 14.86 | yes |
| Q4_K_S | 17.97 | yes |
| Q4_K_M | 18.70 | yes |
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
| `mistral_3_small_flux2_fp4_mixed.safetensors` | 11.43 |

**These are already 30/40-layer pruned.** Unsloth's full
`Mistral-Small-3.2-24B-Instruct-2506-GGUF` BF16 is 43.9 GiB vs Comfy-Org's
33.14 — a 0.755 ratio, matching 30 of 40 layers. FLUX.2's deepest tap is layer
30, so layers 31-39 are dead weight. `flux2_te(pruned=True)` sets
`num_layers=30`, auto-detected when `...layers.39.post_attention_layernorm.weight`
is absent.

Consequence: generic llama.cpp Mistral GGUFs (e.g. unsloth Q4_K_M, 12.44 GiB)
are **larger and slower** than Comfy-Org's fp4_mixed while producing identical
conditioning. Do not substitute them.

**No mmproj / vision tower is needed** for any FLUX.2 variant. There is no
`pixtral`/`vision_tower`/`patch_merger` anywhere in `comfy/text_encoders/`;
image references go through the VAE latent path (`ReferenceLatent`).
