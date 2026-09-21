# Hardware profile: 16 GiB Ada

Read when choosing resolution, steps, CFG or a VRAM budget on the Ada box.

**Identify the machine before trusting a number here.** This repository is used
from two, and neither is "the current one": this profile is the box with an
**RTX 4070 Ti SUPER, 15.99 GiB, sm_89** alongside a second unused card, and the
other is [`hardware-24gb-blackwell.md`](./hardware-24gb-blackwell.md).
`GET /system_stats` says which one you are on.

All figures below were measured 2026-09-19 against a running server on the Ada
box. None of them transfer to Blackwell.

## Baseline

|              |                                                        |
| ------------ | ------------------------------------------------------ |
| GPU (cuda:0) | **RTX 4070 Ti SUPER, 15.99 GiB**, sm_89 Ada, cap (8,9) |
| GPU (cuda:1) | RTX 2060 SUPER, 8 GiB, sm_75 — unused by ComfyUI       |
| RAM          | **127.9 GiB** (~103 free)                              |
| torch        | 2.11.0+cu130, Python 3.14.7                            |
| ComfyUI      | v0.36.0 (`ee71d5c4`)                                   |

`nvidia-smi` lists the 2060 first, but CUDA's default `FASTEST_FIRST` ordering
puts the 4070 Ti SUPER at index 0, which is what ComfyUI picks up. Confirm with
`GET /system_stats` rather than `nvidia-smi` ordering.

**fp8 is native here.** `mm.supports_fp8_compute()` returns `True` on sm_89, so
the fp8 checkpoints run on fp8 tensor cores exactly as they did on sm_120. The
"use fp8, not GGUF" conclusion from the Blackwell profile still applies.

Usable VRAM is **~14.76 GiB** (`vram_free` at idle); the desktop holds ~1.2 GiB.

## Installed on this box

As of 2026-09-19. Source repos and quant tables are [`models.md`](./models.md).

| Role            | File                                   | GiB  |
| --------------- | -------------------------------------- | ---- |
| DiT (distilled) | `flux-2-klein-9b-fp8.safetensors`      | 8.79 |
| DiT (base)      | `flux-2-klein-base-9b-fp8.safetensors` | 8.91 |
| Text encoder    | `qwen_3_8b_fp8mixed.safetensors`       | 8.07 |
| VAE             | `flux2-vae.safetensors`                | 0.31 |
| Upscaler        | `4xNomos2_hq_dat2.pth`                 | 0.13 |

**Encoder and DiT are not co-resident**: the set above totals 17.3 GiB against
14.76 usable, so the encoder evicts before the DiT loads.

The eviction is cheap though. Measured on the distilled model at 1440²/4 steps:

| Case                                    | Time           |
| --------------------------------------- | -------------- |
| same prompt, new seed                   | **7.0–7.6s**   |
| **new prompt** (encoder evict + reload) | **14.4–15.8s** |

So a prompt change costs **~7.4–8.4s**. Negligible against a 62s base render,
but it doubles a 7s distilled one. Conditioning is cached per prompt, so seed
sweeps never pay it.

## Klein 9B differs structurally from dev

Confirmed against the shipped blueprint and the Comfy-Org template:

|         | FLUX.2-dev          | Klein 9B base                      | Klein 9B distilled |
| ------- | ------------------- | ---------------------------------- | ------------------ |
| steps   | 20–50               | 20–28                              | 4                  |
| encoder | Mistral-Small-3 24B | `qwen_3_8b_fp8mixed`, `type=flux2` | same               |

Which guider each of them needs, and why klein base alone has a live negative
prompt, is `docs/workflows.md` → *Guider choice is per model, not preference*.

**cfg 1.0 costs exactly half**, measured at 1440²/20 steps: cfg 1.0 = 31.5s,
cfg 2.0–8.0 = 61.0–63.7s flat. The mechanism behind the factor of two is in the
same section.

## Resolution

Klein base, 20 steps, cfg 5, seed 42. Times are **server-side**
`execution_start → execution_success`.

| Output | MP   | Time   | s/MP | Peak VRAM | Text                        |
| ------ | ---- | ------ | ---- | --------- | --------------------------- |
| 1024²  | 1.00 | 27.8s  | 27.8 | 13.25 GiB | **"EGN" — dropped a glyph** |
| 1440²  | 1.98 | 62.7s  | 31.7 | 12.21 GiB | "EGON" correct              |
| 2048²  | 4.00 | 160.1s | 40.0 | 11.74 GiB | "EGON" correct, best detail |

Two results worth noting:

- **Peak VRAM falls as resolution rises** (13.25 → 11.74 GiB). Same DynamicVRAM
  eviction behavior the 24 GiB box showed, reproducing on 16 GiB. 4 MP does not
  OOM.
- **Cost per megapixel worsens** here (27.8 → 40.0 s/MP), the *opposite* of the
  Blackwell box (93.9 → 80.5, improving). Do not assume high-res is efficient on
  this card.

1024² dropping a glyph is n=1 and compositions differ entirely across
resolutions, so treat it as suggestive rather than proven. It is still a reason
to prefer 1440² for anything with text.

## Step counts, and why MAD alone is misleading

Klein base, 1440², cfg 5, seed 42, reference = 28 steps.

| Steps  | Time      | s/step | MAD      | border   | centre | c/b  |
| ------ | --------- | ------ | -------- | -------- | ------ | ---- |
| 4      | 13.3s     | 3.32   | 45.06    | 34.93    | 56.56  | 1.62 |
| 6      | 19.5s     | 3.25   | 42.63    | 33.69    | 47.28  | 1.40 |
| 8      | 25.5s     | 3.19   | 33.11    | 30.21    | 33.51  | 1.11 |
| 10     | 31.5s     | 3.15   | 23.01    | 22.27    | 23.71  | 1.06 |
| 12     | 37.8s     | 3.15   | 19.78    | 18.96    | 21.71  | 1.15 |
| 16     | 49.9s     | 3.12   | 13.93    | 15.51    | 12.18  | 0.79 |
| **20** | **61.9s** | 3.10   | **5.08** | **3.00** | 8.59   | 2.86 |
| 28     | 86.5s     | 3.09   | 0        | 0        | 0      | —    |

`border` is the mean abs diff over the outer 1/8 frame, `centre` the middle
quarter. The ratio separates *subject refinement* from *whole-frame drift*.

**Klein base does not stabilize until ~20 steps.** Border diff stays at 15–35
through 16 steps, then collapses to 3.00 at 20. A ratio near 1.0 (steps 8–12)
means the background is changing as much as the subject — the whole frame is
still moving, including global tone and lighting.

A 10-step draft therefore predicts gross subject layout but **not** the final
tone, contrast or background. Only at 20 steps does the image become a faithful
preview of the 28-step render.

> An earlier reading of the 10-vs-20 diff heatmap concluded "composition locks at
> 10 steps". The border/centre numbers disprove it — border diff was 20.28, not
> near zero. Eyeballing a heatmap is not a substitute for measuring where the
> energy sits.

Contrast with the **distilled** model at the same resolution, reference = 20 steps:

| Steps | Time     | MAD   | border   | centre | c/b       |
| ----- | -------- | ----- | -------- | ------ | --------- |
| 2     | 5.3s     | 27.03 | —        | —      | —         |
| **4** | **7.0s** | 24.76 | **6.43** | 56.64  | **8.81**  |
| 6     | 10.0s    | 21.54 | —        | —      | —         |
| 8     | 13.0s    | 17.03 | **2.82** | 39.54  | **14.04** |
| 12    | 19.9s    | 11.78 | —        | —      | —         |
| 20    | 31.0s    | 0     | 0        | 0      | —         |

The distilled model converges **locally**: at 4 steps the background is already
settled (border 6.43) and all remaining change is inside the subject. Its 4-step
output renders "EGON" cleanly. This is why it, not a low-step base render, is the
right fast-iteration tool.

Seeds are **not** comparable between base and distilled — different weights,
different trajectories.

## CFG

Klein base, 1440², 20 steps, seed 42.

| cfg     | Time      | MAD vs 5 | contrast | saturation | note                           |
| ------- | --------- | -------- | -------- | ---------- | ------------------------------ |
| 1.0     | 31.5s     | 44.41    | 44.7     | 69.4       | under-guided, flat             |
| 2.0     | 63.7s     | 38.95    | 46.1     | 76.9       |                                |
| 3.0     | 61.0s     | 26.45    | 52.8     | 81.9       | **circular vignette artifact** |
| 4.0     | 61.1s     | 9.17     | 58.8     | 79.0       |                                |
| **5.0** | **61.1s** | 0        | 62.1     | 73.7       | **default** (BFL / template)   |
| 6.0     | 61.1s     | 23.21    | 59.8     | 71.9       |                                |
| 8.0     | 61.1s     | 25.01    | 65.3     | 74.8       | clean, higher contrast         |

Contrast rises roughly monotonically with cfg. **4–5 is the stable band** (MAD
9.17 between them, vs 23–26 to either side). cfg 3 produced a visible circular
vignette. cfg 8 looked clean and was not over-saturated, but one prompt is not
grounds to deviate from BFL's documented 5.

## Workflow defaults, and what they cost

| Sidebar              | Model     | Config                              | Measured                     |
| -------------------- | --------- | ----------------------------------- | ---------------------------- |
| `1 Turbo`            | distilled | 1440², 4 steps, cfg 1               | **7.0s**                     |
| `2 Draft`            | base      | 1440², 20 steps, cfg 5              | **61.9s**                    |
| `3 Print`            | base      | 1440², 28 steps, cfg 5, +4x upscale | **124.3s** → 19.07 MP, 24 MB |
| `4 Edit`             | distilled | reference-sized, 4 steps, cfg 1     | **9.4s**                     |
| `Utility/Upscale 4x` | none      | 4xNomos2_hq_dat2                    | 13.7s                        |

Draft is 20 steps rather than a lower count precisely because of the border-diff
result above: below 20 it is not a faithful preview. Draft → Print remains
seed-portable because `seq_len = 1440²/256 = 8100 > 4300`, so `mu` is
step-independent and only the step count changes.

Peak VRAM never exceeded **14.45 GiB** across all four workflows, against 14.76
usable — comfortable but not spacious. The Edit workflow is the tightest.

## Benchmarking method

Every number above is a server-side `execution_start → execution_success` delta
read back from `GET /history/{id}`, never a client-side measurement. The two
traps that make a client number wrong are `docs/http-api.md` → *Timing a run*,
and both were hit here: the 160.1s render in the resolution table first read as
59s.

Determinism was verified: identical parameters produced **MAD 0.0000** between
two separate runs, so any non-zero difference in these tables is a real effect of
the parameter being varied.
