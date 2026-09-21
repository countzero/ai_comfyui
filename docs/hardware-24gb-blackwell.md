# Hardware profile: 24 GiB Blackwell

Read when choosing resolution, steps, CFG or a VRAM budget on the Blackwell box.

**Identify the machine before trusting a number here.** This repository is used
from two, and neither is "the current one": this profile is the box with a single
**RTX PRO 5000 Blackwell Laptop, 23.89 GiB, sm_120** and 191 GiB of RAM, and the
other is [`hardware-16gb-ada.md`](./hardware-16gb-ada.md). `GET /system_stats`
says which one you are on.

Nothing here transfers to the Ada box: the GPU, the RAM, the models and the
upscaler all differ.

## Baseline

|         |                                                                  |
| ------- | ---------------------------------------------------------------- |
| GPU     | RTX PRO 5000 Blackwell Laptop, **23.89 GiB**, sm_120, cap (12,0) |
| RAM     | 191 GiB (~166 free)                                              |
| torch   | 2.11.0+cu130, Python 3.14.7                                      |
| ComfyUI | v0.37.0                                                          |
| Disks   | `C:` ~81 GB free, `D:` ~1450 GB free                             |

Usable VRAM is **22.6 GiB**, not 23.89 — the desktop holds ~1.3 GiB
(`/system_stats` reports `vram_free` at idle).

## Use fp8, not GGUF — it is 2x faster

**`flux2_dev_fp8mixed.safetensors` beats `flux2-dev-Q4_K_M.gguf` decisively**, even
though it is 33.02 GiB vs 18.70 and therefore *must* stream on a 24 GiB card.

| Model        | 1 MP (1024²) | 4 MP (2048²) |
| ------------ | ------------ | ------------ |
| GGUF Q4_K_M  | 88.4s        | 335.8s       |
| **fp8mixed** | **44.3s**    | **213.2s**   |
| speedup      | **2.00x**    | **1.58x**    |

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

| Steps | Time   | Result                  |
| ----- | ------ | ----------------------- |
| 20    | ~44.3s | baseline                |
| 28    | 66.1s  | no clear sharpness gain |
| 50    | 108.2s | no clear sharpness gain |

**At 1440² — composition locked, so this is the valid comparison.** MAD is mean
absolute difference vs the 50-step render (0–255):

| Steps  | Time      | s/step | MAD vs 50 | Verdict                                        |
| ------ | --------- | ------ | --------- | ---------------------------------------------- |
| 4      | 19.5s     | 4.88   | 34.47     | **unusable** — glyph has no drips, poses wrong |
| 6      | 30.0s     | 5.00   | 26.18     | unreliable — pose and props still diverge      |
| 8      | 37.6s     | 4.70   | 24.96     | borderline                                     |
| 10     | 45.1s     | 4.51   | 18.91     | aggressive floor                               |
| **12** | **54.1s** | 4.51   | 17.84     | **draft default** — layout matches             |
| 16     | 72.1s     | 4.51   | 14.19     | safe margin                                    |
| 20     | 94.5s     | 4.72   | 12.91     | matches                                        |
| 28     | 130.0s    | 4.64   | 7.98      | —                                              |
| 50     | 225.8s    | 4.52   | 0         | print default                                  |

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

| Output | MP   | Tokens | Time   | s/MP | Peak VRAM     | Mode                 |
| ------ | ---- | ------ | ------ | ---- | ------------- | -------------------- |
| 1024²  | 1.05 | 4,096  | 98.6s  | 93.9 | 22.23 GiB     | flat — resident      |
| 1440²  | 2.07 | 8,100  | 168.7s | 81.5 | 23.54 GiB     | sawtooth — streaming |
| 2048²  | 4.19 | 16,384 | 337.4s | 80.5 | **20.91 GiB** | streaming            |

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

| Config                                  | Median    | Δ          |
| --------------------------------------- | --------- | ---------- |
| `--high-ram` (baseline)                 | 98.4s     | —          |
| `+ --enable-triton-backend`             | 98.4s     | **0%**     |
| `+ --fast` (all four features)          | 88.4s     | −10.2%     |
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
`rms_rope`, `int8_linear`, `w4a8_int8_linear`) target quantisation paths those
models never take — the matmuls go through cuBLAS regardless.

**Re-tested on an int8 model, still nothing.** That was the one condition under
which this was worth revisiting, and Qwen-Image-2.1's `int8_convrot` weights meet
it: they take exactly the `int8_linear` and `quantize_and_rotate_rowwise` paths
the capability list advertises. Measured at 2048², 25 steps, one server per
configuration so the flag is the only variable:

| Backend | seed 42 | seed 777 |
| ------- | ------- | -------- |
| off     | 80.7s   | 80.2s    |
| on      | 79.6s   | 79.8s    |

0.9%, inside run-to-run noise. It is not free either: with the backend on, the
same seed renders MAD 1.08 away from the same seed with it off, while two runs
with it off are bit-identical. It stays **absent from
`requirements_override.txt`**, now for a measured reason rather than an
extrapolated one.

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

## Qwen-Image-2.1

ComfyUI v0.37.0, the `int8_convrot` DiT and encoder plus the bf16 VAE. That set
is 16.10 GiB against 22.6 usable, so DiT and encoder stay co-resident and a
prompt change never pays an encoder reload.

**Renders are bit-identical across server restarts.** The same seed, steps and
resolution measured MAD 0.000 between two separate server processes, so any
non-zero difference below is a real one rather than sampling jitter.

### Resolution, 25 steps

Loaders and the text encode stay cached between runs, so these isolate sampling
plus VAE decode.

| Output | MP   | Time  | s/MP | Peak VRAM |
| ------ | ---- | ----- | ---- | --------- |
| 1024²  | 1.05 | 14.1s | 13.4 | 16.42 GiB |
| 1440²  | 2.07 | 32.5s | 15.7 | 17.10 GiB |
| 2048²  | 4.19 | 80.5s | 19.2 | 19.89 GiB |

Cost per megapixel **rises** with resolution here, the opposite of FLUX.2-dev on
this card, where it improved from 93.9 to 80.5 s/MP. 4 MP still fits with 2.7 GiB
to spare, which is why the workflows generate at 2048² rather than the 1 MP the
upstream template ships.

### Steps at 2048², three prompts, three seeds

An earlier version of this table compared one image at one seed and scored it
with Laplacian variance. That was not enough to decide anything: lap.var rewards
grain as readily as detail, so "sharper" and "noisier" score the same way. The
prompt set below is in *The benchmark prompt set*.

| Steps | Mean time | s/step |
| ----- | --------- | ------ |
| 25    | 83.6s     | 3.34   |
| 40    | 135.4s    | 3.39   |
| 60    | 202.5s    | 3.38   |

Cost per step is flat, so step count buys time linearly and the only question is
where the image stops changing.

**40 steps ships, decided by convergence rather than by eye.** Distance to a
60-step reference, per matched prompt and seed:

| Prompt      | mean MAD 25→60 | mean MAD 40→60 | ratio |
| ----------- | -------------- | -------------- | ----- |
| S1 text     | 15.00          | 10.95          | 1.46  |
| S2 texture  | 15.04          | 6.07           | 2.50  |
| S3 portrait | 11.09          | 5.57           | 1.99  |

40 is closer to the converged result in **9 of 9 pairs**, by a mean factor of
1.99. This needs no aesthetic judgement: 25 steps is roughly twice as far from
where the schedule is heading. For continuity, lap.var also rose in 9 of 9 pairs
(+31.6% mean, range +7.3 to +48.0), but the convergence ratio is what decided it.

Drop to 25 while iterating on a prompt; the composition is already settled there,
only the refinement is not.

### The shift default is right, and the obvious reading of it is wrong

`supported_models.QwenImage21` sets `shift: 0.69` under a comment calling it
"scheduler mu". It really is mu, not the multiplicative alpha, and the code path
is what settles it: `QwenImage21` is built with `ModelType.FLUX`, which selects
`ModelSamplingFlux`, whose `sigma()` is
`flux_time_shift(mu, 1.0, t) = exp(mu) / (exp(mu) + (1/t - 1))`. The effective
alpha is therefore exp(0.69) = 1.9937.

Measured against `ModelSamplingAuraFlow`, which takes alpha directly, at 2048²,
25 steps, seed 777:

| Override   | Time  | MAD vs untouched | lap.var |
| ---------- | ----- | ---------------- | ------- |
| none       | 83.3s | 0                | 774.0   |
| shift 0.69 | 84.2s | 15.61            | 795.0   |
| shift 2.00 | 84.0s | **0.85**         | 774.7   |
| shift 3.72 | 83.2s | 14.16            | 763.5   |

The untouched model lands on alpha 2.00, which is the exponentiation showing up
in pixels. Forcing 0.69 as alpha is the error, not the default.

3.72 is exp of the mu that diffusers' *dynamic* shifting would choose at 2048²,
where seq_len 16384 overshoots the scheduler config's 8192 ceiling. ComfyUI's mu
is static and calibrated for 1024². Matching the reference costs the same time
and measures slightly **less** acute, so the static value stays and no workflow
here wires a sampling override.

### Edit, `QwenImage21Cache` device

1 MP reference, 40 steps, all four at a matched cache state.

| device | Time  | Peak VRAM |
| ------ | ----- | --------- |
| auto   | 27.0s | 18.00 GiB |
| gpu    | 28.7s | 19.94 GiB |
| cpu    | 29.6s | 18.05 GiB |
| off    | 48.0s | 18.29 GiB |

The prefix cache is worth **44%**. `auto` is both the fastest and the lightest,
so the shipped default needs no change; `off` exists to rule the cache out when
debugging, not as a tuning option.

### Adherence, nine prompts at 2048², 40 steps

Three seeds each at shipped defaults, scored against the pass conditions in
*The benchmark prompt set*. Median 140.8s per render at 19.95 GiB peak.

| Prompt          | Pass | What failed                                     |
| --------------- | ---- | ----------------------------------------------- |
| C1 counting     | 2/3  | seed 1337 drew one ball, not three              |
| C2 position     | 1/3  | no bear at 777, dog not right of it at 42       |
| C3 color attr   | 0/3  | "purple" bound to the wine, no black apple ever |
| C4 two object   | 3/3  | -                                               |
| C5 transparency | 3/3  | -                                               |
| C6 architecture | 3/3  | -                                               |
| C7 illustration | 2/3  | seed 1337 graded the sky                        |
| C8 landscape    | 3/3  | -                                               |
| C9 CJK text     | 2/3  | seed 777 split into two columns, glyphs garbled |

**Attribute binding is the weak axis, not rendering.** The four GenEval lines
score 6/12 against 10/12 for the four added ones: geometry, flat shading, depth
recession and CJK glyphs all hold, but a color belonging to one of two objects
lands on whichever noun is nearest, and the second object is often dropped.

**C5 is the only one scored mechanically**, and it carries the most weight,
because the Transparent workflow's whole claim rests on it. Alpha spans 0-255
across 256 levels with 19-22% of pixels fully transparent. Every other render is
the control: all are 4-channel too, since this VAE is RGBA, yet none holds one
fully transparent pixel and their alpha means sit at 254.3 to 255.0. Four bands
proves nothing on this model; only varying alpha does.

## Klein 9B

First measurement on this box. The Klein numbers in
[`hardware-16gb-ada.md`](./hardware-16gb-ada.md) were taken on the other machine
and do not transfer.

| Sidebar | Checkpoint | Settings                            | Time                      | Peak VRAM |
| ------- | ---------- | ----------------------------------- | ------------------------- | --------- |
| 1 Turbo | distilled  | 1440², 4 steps, cfg 1               | **6.7s** warm, 20.1s cold | 17.97 GiB |
| 2 Draft | base       | 1440², 20 steps, cfg 5              | 64.7s                     | 20.71 GiB |
| 3 Print | base       | 1440², 28 steps, cfg 5, 4x to 4472² | 124.8s                    | 19.98 GiB |
| 4 Edit  | distilled  | 1 MP reference, 4 steps, cfg 1      | 8.8s                      | 19.10 GiB |

DiT, encoder and VAE total 17.17 GiB against 22.6 usable, so **there is no
evict/reload on a prompt change here**. Consecutive Turbo runs at different seeds
measured 7.5s then 6.7s; the Ada box pays 7.4–8.4s for that same swap because its
14.76 GiB cannot hold both. The settings above were tuned on Ada and are kept
unchanged, since nothing in these numbers argues against them.

## The benchmark prompt set

The prompts, the seeds and the scoring rules are [`benchmarks.md`](./benchmarks.md).
They are kept there rather than here because they have to stay fixed across
machines and sessions for these numbers to mean anything, which makes them a
contract rather than a measurement.

Scoring for the characterization prompts is by eye, so **those results are not
comparable to published GenEval scores.**

## Previews

`--preview-method taesd` with a derived `taef2_decoder`
([`models.md`](./models.md) → *Preview decoder*). Correlation between the last
preview frame and the final render, same seed:

| Model          | Previewer           | Correlation |
| -------------- | ------------------- | ----------- |
| Klein 9B       | taef2 TAESD         | 0.998       |
| Klein 9B       | latent2rgb          | 0.948       |
| Qwen-Image-2.1 | latent2rgb (forced) | 0.878       |

Costs 2.4% (91.0s against 88.8s at 2048², 25 steps). Qwen cannot be improved:
its latent format declares no decoder. Its preview is soft rather than wrong.

## Desktop responsiveness: only one lever works

This GPU drives the display, and a render pins it at 99% utilisation. What was
tried:

| Approach                      | Result                                                        |
| ----------------------------- | ------------------------------------------------------------- |
| `--vram-headroom 2.5`         | **works.** Desktop floor 2.85 → 3.96 GiB, no time cost        |
| Process priority Idle         | useless: utilisation unchanged, render ~30% slower            |
| `nvidia-smi -pl` / `-lgc`     | refused by firmware, and pointless: already at the 95 W cap   |
| MIG                           | unavailable on this laptop GPU                                |
| Per-step yield, 25%           | +10% time, idle samples 14.8% → 23.3%                         |
| Per-step yield, 50%           | +47% time, idle samples 34.1%                                 |

The card is **power-limited, not clock-limited**: 94.7 W median against a 95 W
cap for 86% of a render, SM clocks at ~1300 of 3090 MHz. There is no headroom to
give away, which is why every throttling approach either fails or just removes
work.

Yielding the GPU between model evaluations does free time, but at step
granularity the gaps land about 3.3s apart while a 60 Hz desktop wants one every
16.7 ms, so it converts a constant stall into an intermittent one. Finer
granularity is available through the block hooks, but
`comfy/ldm/qwen_image21/model.py` disables the prefix KV cache whenever a block
is hooked, which costs 44% on edits. Neither trade is worth shipping.

The effective lever is less work: 1440² renders in ~33s against ~83s and peaks
at 17.1 GiB against 19.9.

## Installed on this box

Verified against the filesystem 2026-09-20. Source repos and quant tables are
[`models.md`](./models.md).

| Role                     | File                                          | GiB   |
| ------------------------ | --------------------------------------------- | ----- |
| FLUX.2-dev DiT           | `flux2_dev_fp8mixed.safetensors`              | 33.02 |
| FLUX.2-dev encoder       | `mistral_3_small_flux2_fp4_mixed.safetensors` | 11.43 |
| Klein 9B DiT (distilled) | `flux-2-klein-9b-fp8.safetensors`             | 8.79  |
| Klein 9B DiT (base)      | `flux-2-klein-base-9b-fp8.safetensors`        | 8.91  |
| Klein 9B encoder         | `qwen_3_8b_fp8mixed.safetensors`              | 8.07  |
| Qwen-Image-2.1 DiT       | `qwen_image_2.1_int8_convrot.safetensors`     | 6.76  |
| Qwen-Image-2.1 encoder   | `qwen3vl_8b_int8_convrot.safetensors`         | 8.71  |
| Qwen-Image-2.1 VAE       | `qwen_image_2.1_vae_bf16.safetensors`         | 0.63  |
| FLUX.2 VAE               | `flux2-vae.safetensors`                       | 0.31  |
| Upscaler                 | `4xNomos2_hq_dat2.pth`                        | 0.13  |

86.76 GiB total. All three model families are complete, so every one of the
eleven sidebar entries resolves its weights.

`flux2-dev-Q4_K_M.gguf` (18.70) was benchmarked here but is no longer installed.

Residency against 22.6 GiB usable, which is what decides whether a prompt change
costs an encoder reload:

| Set                       | Total | Co-resident |
| ------------------------- | ----- | ----------- |
| Qwen-Image-2.1, int8 pair | 16.10 | yes         |
| Klein 9B, fp8 pair        | 17.17 | yes         |
| FLUX.2-dev                | 44.76 | no, streams |
