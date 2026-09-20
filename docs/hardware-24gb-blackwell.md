# Hardware profile: 24 GiB Blackwell + FLUX.2-dev

Read when working on the archived 24 GiB and FLUX.2-dev profile.

**Status: archived, not the current machine.** Every measurement here was taken on
an RTX PRO 5000 Blackwell Laptop with FLUX.2-dev installed, verified working
2026-09-19. The repo has since moved to a 16 GiB Ada card running FLUX.2 Klein 9B
— see [`hardware-16gb-ada.md`](./hardware-16gb-ada.md).

These numbers are **still correct for this hardware** and are expensive to
re-derive, so they are kept in full. Do not apply them to the current box: the
GPU, the RAM, the models and the upscaler have all changed.

## Baseline

| | |
|---|---|
| GPU | RTX PRO 5000 Blackwell Laptop, **23.89 GiB**, sm_120, cap (12,0) |
| RAM | 191 GiB (~164 free) |
| torch | 2.11.0+cu130, Python 3.14.7 |
| ComfyUI | v0.36.0 |
| Disks | `C:` ~81 GB free, `D:` ~1480 GB free |

Usable VRAM is **22.6 GiB**, not 23.89 — the desktop holds ~1.3 GiB
(`/system_stats` reports `vram_free` at idle).

## Use fp8, not GGUF — it is 2x faster

**`flux2_dev_fp8mixed.safetensors` beats `flux2-dev-Q4_K_M.gguf` decisively**, even
though it is 33.02 GiB vs 18.70 and therefore *must* stream on a 24 GiB card.

| Model | 1 MP (1024²) | 4 MP (2048²) |
|---|---|---|
| GGUF Q4_K_M | 88.4s | 335.8s |
| **fp8mixed** | **44.3s** | **213.2s** |
| speedup | **2.00x** | **1.58x** |

Why, from source: `ComfyUI-GGUF/ops.py:177` calls `dequantize_tensor(...)` and
`dequant.py` does `d.view(torch.float16).to(dtype)`. **GGUF's 4-bit format is
storage-only** — it dequantizes to bf16 before every matmul, so the quantisation
buys zero compute and costs dequant overhead each forward pass. fp8 is native on
sm_120 (`mm.supports_fp8_compute() == True`), so its matmuls run on fp8 tensor
cores.

The dequant overhead dominates PCIe bandwidth: a *streaming* 33 GiB fp8 model
still doubles the speed of a *fully resident* 18.70 GiB GGUF.

Output quality at matched seed is **comparable** — same composition, both render
text cleanly. There is no visible quality win either way, only the speed.

Keep GGUF only if you need the smaller disk/RAM footprint. There is **no NVFP4
FLUX.2** — `split_files/diffusion_models/` contains just the one fp8 file.

## Steps measured (FLUX.2-dev)

All fp8, same prompt, seed `121027157284439`, warm (encoder cached).

**At 1024² — no visible win, and step counts are not comparable there** (see `mu`
below):

| Steps | Time | Result |
|---|---|---|
| 20 | ~44.3s | baseline |
| 28 | 66.1s | no clear sharpness gain |
| 50 | 108.2s | no clear sharpness gain |

**At 1440² — composition locked, so this is the valid comparison.** MAD is mean
absolute difference vs the 50-step render (0–255):

| Steps | Time | s/step | MAD vs 50 | Verdict |
|---|---|---|---|---|
| 4 | 19.5s | 4.88 | 34.47 | **unusable** — glyph has no drips, poses wrong |
| 6 | 30.0s | 5.00 | 26.18 | unreliable — pose and props still diverge |
| 8 | 37.6s | 4.70 | 24.96 | borderline |
| 10 | 45.1s | 4.51 | 18.91 | aggressive floor |
| **12** | **54.1s** | 4.51 | 17.84 | **draft default** — layout matches |
| 16 | 72.1s | 4.51 | 14.19 | safe margin |
| 20 | 94.5s | 4.72 | 12.91 | matches |
| 28 | 130.0s | 4.64 | 7.98 | — |
| 50 | 225.8s | 4.52 | 0 | print default |

The structural break is **between 8 and 10** (MAD 25.0 → 18.9, then flat). Below
10 the model has not committed to a composition. At ≥12 the draft reliably
predicts the final layout; only fine detail (exact wing angle, prop shapes) still
moves.

Unlike at 1024², typography **is** visibly crisper at 28/50 than at 20 here —
tighter letterform edges, better-defined spray speckle. Most of the gain is
20→28; 28→50 is marginal for 1.7x the time.

**Time scales with pixel count, not resolution.** s/step is ~2.2 at 1024² and
~4.5–4.7 at 1440² — a 2.1x rise for a 1.97x pixel increase. Steps are linear on
top of that.

**Watch for encoder load in the first run of a new prompt.** The raw 1440²@20
measurement was 112.1s but 94.5s warm; the ~18s delta is the Mistral encoder
loading. Discard the first run of any prompt when benchmarking.

## VRAM budget

Measured, FLUX.2-dev Q4_K_M, 1024×1024, 20 steps:

```
  8-12s   0.22 → 11.32 GiB   text encoder loads
 16s             2.67 GiB    encoder EVICTED (expected; cannot coexist with DiT)
 20-32s   7.48 → 21.58 GiB   DiT loads progressively
 36-124s        22.23 GiB    FLAT PLATEAU — fully resident, no sawtooth
128s            17.48 GiB    VAE decode
```

**130.7s cold, ~4.6 s/step.** Peak 22.23 / 23.89 GiB = **93%**.

A second run with the same prompt and a new seed took **98.6s** (peak 22.20 GiB).
The 32s saved is the text encoder being skipped — ComfyUI caches conditioning, so
only a prompt change pays the encoder load/evict cycle.

Read the curve to diagnose: a **flat plateau means resident**. A **sawtooth means
weights are streaming** from RAM — drop a quant level.

**Residency is an optimisation, not a requirement — 4 MP works on Q4_K_M.**
Measured, same prompt and seed 42, 20 steps:

| Output | MP | Tokens | Time | s/MP | Peak VRAM | Mode |
|---|---|---|---|---|---|---|
| 1024² | 1.05 | 4,096 | 98.6s | 93.9 | 22.23 GiB | flat — resident |
| 1440² | 2.07 | 8,100 | 168.7s | 81.5 | 23.54 GiB | sawtooth — streaming |
| 2048² | 4.19 | 16,384 | 337.4s | 80.5 | **20.91 GiB** | streaming |

Two counter-intuitive results, both verified:

- **Peak VRAM goes *down* at 4 MP** (20.91 vs 23.54 GiB at 2 MP). DynamicVRAM
  evicts more weight blocks to make room for activations, so the allocator
  adapts rather than OOMing.
- **Cost per megapixel *improves* with resolution** (93.9 → 80.5 s/MP). Time is
  near-linear in pixel count, not quadratic, because `Using pytorch attention`
  (SDPA) gives O(n) attention memory.

Beyond ~1 MP the weights stream from RAM and the sawtooth is expected and
healthy. Do not treat it as a fault above 1 MP. **System RAM is the real
constraint for high-res, not VRAM** — ComfyUI users report FLUX.2-dev fp8
running on a 12 GB card with 70 GB RAM, while a 24 GB card with only 32 GB RAM
fails. This box has 191 GiB.

Encoder and DiT **cannot** be co-resident (11.43 + 18.70 = 30.1 GiB). ComfyUI
evicts the encoder after prompt encoding and reloads from RAM only when the
prompt changes — conditioning is cached, so repeated seeds skip it.

## Launch flags

Benchmarked at 1024², 20 steps, median of 3 after a discarded warm-up:

| Config | Median | Δ |
|---|---|---|
| `--high-ram` (baseline) | 98.4s | — |
| `+ --enable-triton-backend` | 98.4s | **0%** |
| `+ --fast` (all four features) | 88.4s | −10.2% |
| `+ --fast fp16_accumulation cublas_ops` | **88.4s** | **−10.2%** |

The two-feature subset **exactly matches** full `--fast`, so `autotune` and
`fp8_matrix_mult` contribute nothing measurable. Upstream flags `--fast` as
"untested and potentially quality deteriorating", so prefer the narrow subset.

### Triton is installed but useless here — do not add it to requirements

`triton-windows` 3.8.0.post28 has a native **cp314** wheel and does activate the
backend:

```
[INFO] Found triton 3.8.0. Enabling comfy-kitchen triton backend.
triton   available=True   disabled=False
```

But it measured **0% on both GGUF and fp8**. Its capabilities (`quantize_nvfp4`,
`rms_rope`, `int8_linear`, `w4a8_int8_linear`) target quantisation paths this
setup never takes — the matmuls go through cuBLAS regardless. It is deliberately
**absent from `requirements_override.txt`**; re-test only if adopting an
nvfp4/int8 model.

## Print pipeline (20 MP)

Measured: **272.5s total, peak 22.33 GiB**, output 4472×4472 = 20.0 MP, 30.4 MB
PNG = **37.9 × 37.9 cm at 300 DPI**.

```
FLUX.2 fp8 @ 1440² × 50 steps  →  ImageUpscaleWithModel (4xNomos2_hq_dat2)  →  5760²
                               →  ImageScale lanczos 4472×4472              →  20 MP master
```

**Generate at 1440².** It sits inside BFL's recommended ≤2 MP band and leaves
budget for 50 steps. 2048² is BFL's hard ceiling and sits *above* the recommended
band. 1440×4 = 5760 → 4472 is still a **downscale**, so supersampling holds.

Generating 4x then downscaling supersamples: the upscaler's detail is averaged
down, suppressing artifacts. Verified at 1:1 — crisp letterforms, visible fabric
weave, individual feather barbs, no sharpening halos.

### Draft → Print was seed-portable, by design

Both ran at **1440²**, and that was the whole point:

```
flux2_draft  1440² @ 12 steps   54.1s   ← seed-hunt + dial the prompt
flux2_print  1440² @ 50 steps  272.5s   ← SAME seed → SAME composition, full detail
```

Because `seq_len=8100 > 4300`, `mu` is step-independent at 1440², so changing only
the step count preserves the composition. Verified: mean abs diff between the
12-step and 50-step renders is detail-level, and the layout (poses, object
placement, glyph position) is identical.

**Never draft at 1024².** A composition found at 1 MP cannot be reproduced at any
other resolution. Every seed spent there is unusable for print.

### Standalone upscale

**Measured: 1024² → 4096² in 22.6–27.1s**, 16.8 MP, 24 MB, 34.7 cm at 300 DPI.
Because `SaveImage` only depends on the `LoadImage` branch, ComfyUI's
output-driven executor **never loads the 33 GiB UNet, Mistral encoder or VAE** —
peak torch VRAM stays at tens of MiB.

Verified at 1:1 against plain lanczos: letterforms gain clean hard edges, feather
barbs separate individually. It does introduce faint white speckle on smooth
surfaces — hallucinated micro-contrast, minor at print scale.

## Model set used on this box

| Role | File | GiB |
|---|---|---|
| **DiT (default)** | `flux2_dev_fp8mixed.safetensors` | **33.02** |
| DiT (alt) | `flux2-dev-Q4_K_M.gguf` | 18.70 |
| Text encoder | `mistral_3_small_flux2_fp4_mixed.safetensors` | 11.43 |
| VAE | `flux2-vae.safetensors` | 0.31 |
| Upscaler | `4xNomos2_hq_dat2.pth` | 0.13 |

**None of the FLUX.2-dev files are installed any more.** Restoring this profile
means re-downloading the DiT and the Mistral encoder (~45 GiB). See
[`models.md`](./models.md) for quant tables and source repos.
