# Model catalog

Read when installing, replacing or sourcing a model file.

Sizes are GiB (bytes ÷ 1024³). Repos host `.../resolve/main/<file>`.

This file says what exists and where to get it. **What is installed is a property
of a machine, not of the repository**, so it lives in that machine's profile:
[`hardware-24gb-blackwell.md`](./hardware-24gb-blackwell.md) and
[`hardware-16gb-ada.md`](./hardware-16gb-ada.md) each carry their own set.

## Downloading

`hf` ships inside the ComfyUI environment. Point `HF_HOME` at a drive with room
before any pull: `hf-xet` keeps a chunk cache there, and `--local-dir` does not
move it.

```powershell
conda activate ComfyUI
$env:HF_HOME = "D:\<somewhere with tens of GiB free>\hf"
```

Black Forest Labs gates its diffusion weights. Accept the license on each model
page first; gating is `auto`, so access is immediate. `hf auth login` writes its
token under whatever `HF_HOME` was set to at the time, so either set `HF_HOME`
first or pass the token through `HF_TOKEN` afterwards. A download that sits on
"Still waiting to acquire lock" is a dead `hf` process holding
`<file>.lock` under `.cache/huggingface/download/`, not a slow network.

Comfy-Org's Qwen repo already mirrors ComfyUI's own directory layout, so it
lands in place:

```powershell
hf download Comfy-Org/Qwen-Image-2.1 `
  diffusion_models/qwen_image_2.1_int8_convrot.safetensors `
  text_encoders/qwen3vl_8b_int8_convrot.safetensors `
  vae/qwen_image_2.1_vae_bf16.safetensors `
  --local-dir .\vendor\ComfyUI\models
```

Comfy-Org's Krea 2 repo does the same:

```powershell
hf download Comfy-Org/Krea-2 `
  diffusion_models/krea2_turbo_fp8_scaled.safetensors `
  text_encoders/qwen3vl_4b_fp8_scaled.safetensors `
  vae/qwen_image_vae.safetensors `
  --local-dir .\vendor\ComfyUI\models
```

Every other repo below stores the file at a path that does not match, so pull it
to a scratch directory and move it into the right `models/` subdirectory.

## Krea 2

`Comfy-Org/Krea-2`, released under the Krea 2 Community License; read its terms
on the model page before any commercial use. A 12B single-stream DiT on the
16-channel Qwen-Image VAE, with Qwen3-VL-4B as its encoder.

| Role              | File                                   | GiB   |
| ----------------- | -------------------------------------- | ----- |
| Turbo DiT (fp8)   | `krea2_turbo_fp8_scaled.safetensors`   | 12.24 |
| Turbo DiT (nvfp4) | `krea2_turbo_nvfp4.safetensors`        | 7.15  |
| Turbo DiT (int8)  | `krea2_turbo_int8_convrot.safetensors` | 12.57 |
| RAW DiT (fp8)     | `krea2_raw_fp8_scaled.safetensors`     | 12.24 |
| Encoder           | `qwen3vl_4b_fp8_scaled.safetensors`    | 4.88  |
| VAE               | `qwen_image_vae.safetensors`           | 0.24  |

The workflows load the fp8 Turbo file, which is native on both boxes. nvfp4 is
native only where `supports_nvfp4_compute()` holds, which needs compute
capability 10 or higher, so it would run on the Blackwell card and not on Ada.
**RAW** is the undistilled base that Krea publishes for LoRA training and does
not recommend for inference; no workflow here loads it.

`qwen_image_vae` is the Qwen-Image v1 VAE, not Qwen-Image-2.1's
`qwen_image_2.1_vae_bf16`: the two differ in channel count and are not
interchangeable. Krea 2 needs ComfyUI v0.37.0 or newer.

## Qwen-Image-2.1

`Comfy-Org/Qwen-Image-2.1`, license `qwen-research`, **non-commercial**. One set
of weights covers both text to image and instruction editing, so a workflow
never swaps checkpoints. 7B DiT, 32 single-stream layers, native 2K output, and
a 64-channel RGBA VAE at 16x spatial compression.

| Role            | File                                      | GiB   |
| --------------- | ----------------------------------------- | ----- |
| DiT (int8)      | `qwen_image_2.1_int8_convrot.safetensors` | 6.76  |
| DiT (bf16)      | `qwen_image_2.1_bf16.safetensors`         | 13.25 |
| Encoder (int8)  | `qwen3vl_8b_int8_convrot.safetensors`     | 8.71  |
| Encoder (bf16)  | `qwen3vl_8b_bf16.safetensors`             | 16.33 |
| Encoder (w4a8)  | `qwen3vl_8b_w4a8.safetensors`             | 5.88  |
| VAE             | `qwen_image_2.1_vae_bf16.safetensors`     | 0.63  |

The int8 pair is what Comfy-Org's own templates load. `int8_convrot` and
`asym_w4a8_int8` both dispatch through `comfy-kitchen`, and `ops.py:1719`
disables both unless `comfy.model_management.supports_int8_compute()` is true.
That gate is by backend, not by hardware: `model_management.py:2049` returns
true for every CUDA device and false only for MPS, Intel XPU, DirectML and
ixuca. It never reads the compute capability, so the bf16 files are the fallback
for those four backends rather than for an older NVIDIA card.

The repo also carries `qwen3.5_9b_qwen_image_2.1_pe_t2i` and `..._pe_i2i`, each
8.82 GiB. Those are Qwen's **prompt rewriting** checkpoints, not ComfyUI text
encoders, and no workflow here loads them.

Qwen-Image-2.1 needs ComfyUI v0.37.0 or newer. v0.36.0 has neither the nodes nor
`supported_models.QwenImage21`.

## FLUX.2 Klein 9B sources

Diffusion models require accepting BFL's license on HuggingFace first.

| File                                   | Repo                                                                          |
| -------------------------------------- | ----------------------------------------------------------------------------- |
| `flux-2-klein-9b-fp8.safetensors`      | `black-forest-labs/FLUX.2-klein-9b-fp8`                                       |
| `flux-2-klein-base-9b-fp8.safetensors` | `black-forest-labs/FLUX.2-klein-base-9b-fp8`                                  |
| `qwen_3_8b_fp8mixed.safetensors`       | `Comfy-Org/vae-text-encorder-for-flux-klein-9b`, `split_files/text_encoders/` |
| `flux2-vae.safetensors`                | `Comfy-Org/flux2-dev`, `split_files/vae/`                                     |

Klein 9B is **non-commercial licensed**; the 4B variants are Apache-2.0. The DiT
files are 8.79 and 8.91 GiB.

Both BFL model cards state the 9B models "fit in ~29GB VRAM … RTX 4090 and
above". That is the bf16 reference pipeline; the fp8 checkpoints above run in
8.8 GiB.

Other klein 9B encoder quants: `qwen_3_8b` bf16 15.26, `qwen_3_8b_fp4mixed` 6.34.
The fp4 variant is worth testing where the encoder has to evict between passes.

Current Comfy-Org templates reference a newer VAE,
`full_encoder_small_decoder.safetensors`, instead of `flux2-vae.safetensors`. The
klein docs list `flux2-vae` for 9B and it is what has been verified here, so the
newer VAE is optional.

**klein-4B** — Apache-2.0, all safetensors from
`Comfy-Org/vae-text-encorder-for-flux-klein-4b`, 11.12 GiB total:
`flux-2-klein-4b.safetensors` 7.22 + `qwen_3_4b_fp4_flux2.safetensors` 3.58 +
VAE 0.31. Needs `qwen_3_4b`, not `qwen_3_8b`.

## Encoders are not interchangeable

FLUX.2 concatenates three intermediate hidden layers, so conditioning width is
fixed by architecture and cannot be changed by config.

| Model            | Required encoder     | Taps     | Width |
| ---------------- | -------------------- | -------- | ----- |
| FLUX.2-dev (32B) | Mistral-Small-3 24B  | 10,20,30 | 15360 |
| FLUX.2-klein-9B  | Qwen3-8B             | 9,18,27  | 12288 |
| FLUX.2-klein-4B  | Qwen3-4B             | 9,18,27  | 7680  |

`CLIPLoader` takes `type=flux2` for **all** of them; ComfyUI auto-detects which
encoder a checkpoint is from its state dict (`comfy/sd.py`). Qwen-Image-2.1
follows the same pattern under `type=qwen_image`, which it shares with
Qwen-Image 2.0. Krea 2 takes `type=krea2`, and its Qwen3-VL-4B is a different
checkpoint from Qwen-Image-2.1's Qwen3-VL-8B, so neither encoder substitutes for
the other.

A wrong `type` fails silently rather than loudly: a Mistral encoder loaded as
`type=lumina2` loads without error and yields garbage.

## Upscaler: `4xNomos2_hq_dat2`

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

## Preview decoder: `taef2_decoder`, derived not downloaded

`--preview-method taesd` decodes previews through `models/vae_approx/`, and the
filename must start with the latent format's `taesd_decoder_name`. FLUX.2 wants
`taef2_decoder`, which **nobody publishes**. `madebyollin/taef2` ships one
`taef2.safetensors` holding both halves of the autoencoder, keyed
`encoder.layers.N.*` and `decoder.layers.N.*`, while ComfyUI's `TAESD` loads a
decoder-only state dict keyed by bare `nn.Sequential` indices. Loading the
published file directly fails every FLUX.2 render with a state-dict mismatch.

The two are one remap apart. ComfyUI's decoder starts with a `Clamp` at index 0,
so its convolutions sit one later than the published ones: `decoder.layers.N`
maps to `N+1`, sub-indices unchanged. All 79 tensors match pairwise by shape.

Derive it rather than trusting a rename, and verify functionally: a decoded
preview correlates 0.998 with the final render, against 0.948 for the latent2rgb
fallback it replaces. If Comfy-Org or madebyollin ever publish a real
`taef2_decoder`, prefer it and drop the derived copy.

The other decoders are published and need no work: `taesd_decoder` and
`taesdxl_decoder` from `madebyollin/taesd`, `taef1_decoder` and `taesd3_decoder`
from the community `vae_approx` mirrors. Krea 2's latent format is `Wan21`, which
asks for `lighttaew2_1`; `lightx2v/Autoencoders` publishes
`lighttaew2_1.safetensors` at its repo root, so
`hf download lightx2v/Autoencoders lighttaew2_1.safetensors --local-dir .\vendor\ComfyUI\models\vae_approx`
lands it in place. It was trained for Wan 2.1's VAE rather than this one, so how
well its preview tracks a Krea render is unmeasured. Qwen-Image-2.1 has none and cannot: its
latent format declares no `taesd_decoder_name` and no approximate decoder exists
for a 64-channel, 16x VAE.

## fp8 beats GGUF, for an architectural reason

GGUF dequantizes to bf16 before every matmul (`ComfyUI-GGUF/ops.py:177` calls
`dequantize_tensor`, and `dequant.py` does `d.view(torch.float16).to(dtype)`), so
its 4-bit format is storage-only and buys no compute. fp8 runs on fp8 tensor
cores wherever `mm.supports_fp8_compute()` is true, which covers sm_89 and
sm_120. A *streaming* fp8 model therefore beats a *fully resident* GGUF one.
Quality at matched seed is comparable. Keep GGUF only for footprint.

The measured 2x is in `hardware-24gb-blackwell.md` → *Use fp8, not GGUF*.

**GGUF support stays installed.** The `vendor/ComfyUI-GGUF` submodule,
`rebuild_comfyui.ps1` and `requirements_override.txt` are all in place so
`UnetLoaderGGUF` registers. Do not rip out the wiring.

`GET /models/diffusion_models` returns nothing for `.gguf` files — that extension
is not in ComfyUI's default set. Query `/models/unet_gguf` instead.

## FLUX.2-dev DiT quants: `city96/FLUX.2-dev-gguf`

City96's K-quants use mixed-precision block logic, so they beat their nominal bit
width. Q4_0 and Q4_K_S are byte-identical; prefer Q4_K_S.

| Quant  | GiB   |
| ------ | ----- |
| Q2_K   | 11.97 |
| Q3_K_S | 14.69 |
| Q3_K_M | 14.86 |
| Q4_K_S | 17.97 |
| Q4_K_M | 18.70 |
| Q4_1   | 19.80 |
| Q5_K_S | 21.63 |
| Q5_K_M | 22.40 |
| Q6_K   | 25.51 |
| Q8_0   | 32.60 |
| BF16   | 60.02 |

The fp8 file, `flux2_dev_fp8mixed.safetensors`, is 33.02 GiB.

## FLUX.2-dev text encoders: `Comfy-Org/flux2-dev`

Path prefix `split_files/text_encoders/`.

| File                                          | GiB   |
| --------------------------------------------- | ----- |
| `mistral_3_small_flux2_bf16.safetensors`      | 33.14 |
| `mistral_3_small_flux2_fp8.safetensors`       | 16.80 |
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
