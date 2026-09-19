---
name: comfyui
description: >
  Operating the local ComfyUI install in D:\Arbeit\ai_comfyui, covering FLUX.2-dev
  GGUF image generation, VRAM budgeting on a 24 GiB RTX PRO 5000 Blackwell, the
  ComfyUI HTTP API, model placement, and launch flags. Use when running, debugging,
  or extending ComfyUI; when working with flux2, GGUF quants, text encoders, or
  diffusion models; when editing start_comfyui.ps1, rebuild_comfyui.ps1, or
  requirements_override.txt; or when a generation OOMs, fails, or produces wrong
  output. Includes the conda activation gotcha that produces false "torch missing"
  diagnoses.
---

# ComfyUI (D:\Arbeit\ai_comfyui)

Thin wrapper repo around ComfyUI as a git submodule. Verified working for
FLUX.2-dev fp8 as of 2026-09-19.

## Environment invariants

**Always activate conda in the same command.** The shell is fresh per invocation:

```powershell
conda activate ComfyUI; python .\vendor\ComfyUI\main.py ...
```

**GOTCHA — `conda run` gives false negatives.** `conda run -n ComfyUI python -c
"import torch"` from a non-activated shell reports `ModuleNotFoundError` while
torch 2.11.0+cu130 is installed and working. It resolves to the *identical*
interpreter (`C:\Miniconda\envs\ComfyUI\python.exe`), so the interpreter is not
the variable. Treat its output as unreliable: use `conda activate ComfyUI; <cmd>`,
never a bare `conda run`, before concluding anything is missing.

Nine conda envs exist (`base`, `ComfyUI`, `c3`, `fm`, `kinema`, `llama.cpp`,
`open-webui`). Only `ComfyUI` is correct.

**Re-read files before asserting their contents.** Memory of
`requirements_override.txt` and of the installed package set is unreliable after
context pruning. Read the file.

## Verified baseline

| | |
|---|---|
| GPU | RTX PRO 5000 Blackwell Laptop, **23.89 GiB**, sm_120, cap (12,0) |
| RAM | 191 GiB (~164 free) |
| torch | 2.11.0+cu130, Python 3.14.7 |
| ComfyUI | v0.36.0 |
| Disks | `C:` ~81 GB free, `D:` ~1480 GB free |

`requirements_override.txt` correctly pins `torch==2.11.0+cu130` /
`torchvision==0.26.0+cu130` / `torchaudio==2.11.0+cu130`. It is **not** stale.

**Do not run `rebuild_comfyui.ps1` without reason.** All three submodules are
checked out *ahead* of the commits recorded in the parent repo (pre-existing
drift, never committed). The working tree is what FLUX.2 support was verified
against; a rebuild would move it.

## Layout

```
start_comfyui.ps1                      launcher (conda activate + main.py)
rebuild_comfyui.ps1                    submodule update + pip install
requirements_override.txt              torch pins + ComfyUI/custom-node reqs
vendor/ComfyUI/                        submodule
  models/{diffusion_models,text_encoders,vae}/    gitignored (.gitignore:6)
  custom_nodes/ComfyUI-GGUF/           copied in by rebuild script
  output/                              generated images
workflows/flux2_draft_api.json         working FLUX.2 API-format workflow
```

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

**No FLUX.2 GGUF model is installed.** `models/diffusion_models/` holds only
`flux2_dev_fp8mixed.safetensors`. The table above is the justification; to use
GGUF for FLUX.2 again, fetch it from `city96/FLUX.2-dev-gguf`.

**GGUF support itself is present and must stay.** The `vendor/ComfyUI-GGUF`
submodule, the installed `custom_nodes/ComfyUI-GGUF/`, `rebuild_comfyui.ps1:99`
and `requirements_override.txt:18` are all in place, so `UnetLoaderGGUF`
registers and any other GGUF model loads normally. Do not rip out the submodule
or the build wiring.

## Quality settings — what BFL actually documents

Sourced from the [FLUX.2-dev model card](https://huggingface.co/black-forest-labs/FLUX.2-dev),
the [BFL FLUX.2 blog post](https://bfl.ai/blog/flux-2) and the
[FLUX.2 prompting guide](https://docs.bfl.ai/guides/prompting_guide_flux2).

| Setting | BFL guidance | Source |
|---|---|---|
| **Max resolution** | **4 MP (2048×2048)** — hard ceiling, stated three times | blog + prompting guide |
| **Recommended resolution** | **up to 2 MP** "for most use cases" | prompting guide |
| Dimensions | must be **multiples of 16** | prompting guide |
| **Steps** | **50**; *"28 steps can be a good trade-off"* | dev model card snippet |
| Guidance | `guidance_scale=4` (dev); 4.5, range 1.5–10 (flex) | dev card / guide |
| Negative prompts | **not supported** — describe what you want | prompting guide |
| Language | prompt in your native language for cultural accuracy | prompting guide |

The megapixel ladder — **1024² is only 1 MP, half the recommended band**:

| Dim | MP | Note |
|---|---|---|
| 1024² | 1.05 | half of BFL's recommendation |
| 1408² | 1.98 | ≈ the 2 MP recommendation |
| 1440² | 2.07 | ≈ 2 MP, benchmarked below |
| 2048² | 4.19 | hard maximum |

Caveat on provenance: the "≤2 MP recommended" line comes from the guide headed
*FLUX.2 [pro] & [max]*, and the `steps: 50 (max 50)` row is tagged `[flex]`. The
**50 / 28** figure is from the **[dev]** model card, so it applies directly here.

### Steps measured

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

### `compute_empirical_mu` branches at `seq_len > 4300`

`Flux2Scheduler` → `get_schedule(steps, seq_len)` → `compute_empirical_mu`, where
`seq_len = width*height/256`. Below the 4300 threshold `mu` interpolates on
`num_steps`; above it `mu` is **step-independent**:

| Dim | seq_len | mu(20) | mu(28) | mu(50) | |
|---|---|---|---|---|---|
| 1024² | 4,096 | 2.1980 | 2.1514 | 2.0234 | **STEP-DEPENDENT** |
| 1440² | 8,100 | 1.8278 | 1.8278 | 1.8278 | step-independent |
| 2048² | 16,384 | 3.2300 | 3.2300 | 3.2300 | step-independent |

**Consequence: at 1024², changing steps changes the composition**, because the
sigma curve reshapes. A/B-ing step counts with composition held constant is only
valid at **≥1440²**. The 1 MP table above therefore shows framing drift mixed
into any sharpness difference.

### Seeds are NOT portable across resolutions

Same seed at a different resolution gives a **different image**, not a bigger one.
Two independent mechanisms:

1. **Sigma schedule is resolution-dependent** — `seq_len` feeds `mu`. Second sigma
   is `0.9942` at 1024² vs `0.9979` at 2048²; trajectories diverge from step one.
2. **Noise field is spatially unrelated** — `comfy.sample.prepare_noise` does
   `torch.manual_seed(seed)` then `randn(latent.size())`. Latent is 128×64×64 at
   1024² vs 128×128×128 at 2048². The same value *stream* lands at different
   spatial positions (row 1 col 0: `-1.626` vs `0.679`).

So a seed-hunted composition **cannot** be re-rendered larger. Carry it forward as
a **latent** (`VAEEncode` + `SplitSigmasDenoise` low_sigmas, or `ReferenceLatent`)
or upscale the pixels. Budget accordingly: re-hunting 14 seeds costs ~10 min at
1 MP but ~50 min at 4 MP.

### Recover the prompt and seed from any output PNG

`SaveImage` embeds the full **API-format workflow** in a PNG text chunk:

```python
from PIL import Image; import json
wf = json.loads(Image.open('output/flux2_00053_.png').info['prompt'])
# -> {node_id: {class_type, inputs}} — replay or mutate it directly
```

This is the fastest way to reconstruct settings for an image whose parameters were
lost, and it round-trips straight back into `POST /prompt`.

## Launch flags

Current (`start_comfyui.ps1:5`):

```
python .\vendor\ComfyUI\main.py --high-ram --fast fp16_accumulation cublas_ops --preview-method auto
```

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

`PerformanceFeature` values are `fp16_accumulation`, `fp8_matrix_mult`,
`cublas_ops`, `autotune` (`comfy/cli_args.py`).

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

comfy-kitchen 0.2.34 ships with ComfyUI. Its `cuda` and `eager` backends are
available by default, and the Comfy model compiler + CUDA graphs are already on
(`--disable-comfy-compiler` / `--disable-cuda-graphs` exist to turn them off).

v0.36.0 uses **DynamicVRAM**, which supersedes the old static vram modes. From
`comfy/cli_args.py`:

| Flag | Verdict |
|---|---|
| `--lowvram` | **No-op** — *"Doesn't do anything if dynamic vram is enabled."* Not used. |
| `--high-ram` | **Use it.** *"Can improve performance on high RAM systems."* 191 GiB here. |
| `--fast-disk` | **Don't.** Prefers disk over unpinned RAM; RAM is abundant here. |
| `--highvram` / `--gpu-only` | **Don't.** Would try to hold encoder + DiT (30 GiB) in 24 GiB. |
| `--async-offload` | Already default-on for Nvidia. |
| `--reserve-vram`, `--vram-headroom` | Reserve for OOM tuning at higher resolution. |

## VRAM budget

Usable is **22.6 GiB**, not 23.89 — the desktop holds ~1.3 GiB (`/system_stats`
reports `vram_free` at idle).

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

Set width/height on **both** `EmptyFlux2LatentImage` and `Flux2Scheduler`, and
keep dimensions divisible by 16 (VAE stride).

Encoder and DiT **cannot** be co-resident (11.43 + 18.70 = 30.1 GiB). ComfyUI
evicts the encoder after prompt encoding and reloads from RAM only when the
prompt changes — conditioning is cached, so repeated seeds skip it.

## Text encoder is not swappable

FLUX.2 concatenates **three intermediate hidden layers**, so the conditioning
width is fixed by architecture:

- `comfy/text_encoders/flux.py` — `Flux2TEModel.encode_token_weights` stacks
  `out[:,0]`, `out[:,1]`, `out[:,2]` and reshapes.
- `Mistral3_24BModel` taps `layer=[10,20,30]`; hidden 5120 → **3 × 5120 = 15360**.
- `comfy/ldm/flux/model.py:96` — `self.txt_in = Linear(context_in_dim, hidden_size)`,
  hard-wired to 15360 from the checkpoint.
- `comfy/supported_models.py` — `Flux2.clip_target()` probes only
  `mistral3_24b` / `qwen3_8b` / `qwen3_4b`, else `return None`.

| Model | Required encoder | Taps | Width |
|---|---|---|---|
| FLUX.2-dev (32B) | Mistral-Small-3 24B | 10,20,30 | 15360 |
| FLUX.2-klein-9B | Qwen3-8B | 9,18,27 | 12288 |
| FLUX.2-klein-4B | Qwen3-4B | 9,18,27 | 7680 |

Substituting Llama/Gemma/T5/other Qwen sizes is not a config change; it needs DiT
retraining. What *can* vary: quantization, and the system prompt via
`Flux2Tokenizer.llama_template`.

## Model placement

ComfyUI-GGUF (`custom_nodes/ComfyUI-GGUF/nodes.py:32-33`) registers:

- `unet_gguf` → `["diffusion_models", "unet"]`
- `clip_gguf` → `["text_encoders", "clip"]`

**`GET /models/diffusion_models` returns empty for GGUF files** — `.gguf` is not
in ComfyUI's default extension set. Query **`/models/unet_gguf`** instead. The
file being absent from `diffusion_models` is not a problem.

`models/` is gitignored via `vendor/ComfyUI/.gitignore:6` (confirmed with
`git check-ignore -v`), so `git reset --hard` and `git submodule update --force`
cannot remove weights.

## HTTP API (127.0.0.1:8188)

Drive with `curl` / `Invoke-RestMethod`. No MCP needed.

| Endpoint | Use |
|---|---|
| `GET /system_stats` | GPU, VRAM total/free, torch version, **active argv** |
| `GET /models/{folder}` | Installed models — use `unet_gguf` for GGUF |
| `GET /object_info/{node_class}` | Exact node schema |
| `POST /prompt` | Enqueue API-format workflow → `prompt_id` |
| `GET /history/{prompt_id}` | Results **and full Python tracebacks** |
| `POST /free` | Unload models, free VRAM |
| `POST /interrupt`, `GET`/`POST /queue` | Cancel, inspect, clear |
| `GET /view`, `POST /upload/image` | Fetch outputs, push inputs |
| `GET /ws` | Live progress + previews |

**Context safety: never `GET /object_info` bare — it is megabytes.** Always
`/object_info/{node_class}`.

Completion check: poll `GET /history/{prompt_id}` until the response contains the
`prompt_id` key.

## Tool selection

- **`curl`/Bash — drive everything.** Full API coverage, zero dependencies,
  and output can be filtered before it reaches context.
- **chrome-devtools — look, don't drive.** Good for `take_screenshot` of results
  and `list_console_messages`. The graph is a `<canvas>` (litegraph), so
  `take_snapshot` yields a useless a11y tree and `click(uid)` cannot reach nodes.
- **MCP — not installed, not needed.** `artokun/comfyui-mcp` is deprecated
  (archives 2026-10-09). Official `Comfy-Org/comfy-mcp` (PyPI, beta) wraps
  `comfy-cli --where local`, which expects a standard workspace — this repo is a
  submodule + conda env. Its `launch_comfyui` would also bypass the tuned flags.

## Working FLUX.2 workflows

All verified end-to-end. API format drives `POST /prompt`; UI format opens in the
canvas.

| File | Format | Model | Use |
|---|---|---|---|
| `workflows/flux2_draft_api.json` | API | fp8 | **1440² @ 12 steps, 54s** — seed-hunt here |
| `workflows/flux2_draft_ui.json` | UI | fp8 | same, canvas editor |
| `workflows/flux2_print_api.json` | API | fp8 | **1440² @ 50 steps → 4x → 20 MP**, 272.5s |
| `workflows/flux2_print_ui.json` | UI | fp8 | same, canvas editor |
| `workflows/upscale_4x_api.json` | API | none | **upscale any PNG** — no diffusion, 24s |
| `workflows/upscale_4x_ui.json` | UI | none | same, canvas editor |

UI copies are deployed to `vendor/ComfyUI/user/default/workflows/` as
**FLUX.2 Draft**, **FLUX.2 Print**, and **Upscale 4x**. Every UI workflow needs
an API twin (and vice versa) — the formats are not interchangeable, so adding one
means adding both.

**`upscale_4x_*` carries no `flux2_` prefix deliberately** — it contains zero
diffusion nodes (`LoadImage`, `UpscaleModelLoader`, `ImageUpscaleWithModel`,
`ImageScale`, `SaveImage`) and works on any image from any source.

### Draft → Print is seed-portable, by design

Both run at **1440²**, and that is the whole point:

```
flux2_draft  1440² @ 12 steps   54.1s   ← seed-hunt + dial the prompt
flux2_print  1440² @ 50 steps  272.5s   ← SAME seed → SAME composition, full detail
```

Because `seq_len=8100 > 4300`, `mu` is step-independent at 1440², so changing only
the step count preserves the composition. Verified: mean abs diff between the
12-step and 50-step renders is detail-level, and the layout (poses, object
placement, glyph position) is identical.

**Never draft at 1024².** A composition found at 1 MP cannot be reproduced at any
other resolution — see *Seeds are NOT portable across resolutions*. Every seed
spent there is unusable for print.

### Standalone upscale — `upscale_4x_*.json`

Five nodes, no diffusion model touched:

```
LoadImage ─┐
           ├─→ ImageUpscaleWithModel(4xNomos2_hq_dat2) → ImageScale(lanczos) → SaveImage
UpscaleModelLoader ─┘
```

**Measured: 1024² → 4096² in 22.6–27.1s**, 16.8 MP, 24 MB, 34.7 cm at 300 DPI.
Because `SaveImage` only depends on the `LoadImage` branch, ComfyUI's
output-driven executor **never loads the 33 GiB UNet, Mistral encoder or VAE** —
peak torch VRAM stays at tens of MiB.

Verified at 1:1 against plain lanczos: letterforms gain clean hard edges, feather
barbs separate individually. It does introduce faint white speckle on smooth
surfaces — hallucinated micro-contrast, minor at print scale.

`LoadImage` has `image_upload: true`, so PNGs drag-drop onto the node in the UI;
via API put the file in `vendor/ComfyUI/input/` first. `LoadImageOutput` is an
alternative that reads `output/` directly with no copy.

`ImageScale` is set to 4096×4096 — a deliberate **no-op pass-through** for a
1024² source, so nothing is interpolated. It only downscales cleanly; setting it
above 4x the source stretches and softens.

fp8 uses `UNETLoader` (`unet_name`, `weight_dtype`); GGUF uses `UnetLoaderGGUF`
(`unet_name` only). `weight_dtype` options: `default`, `fp8_e4m3fn`,
`fp8_e4m3fn_fast`, `fp8_e5m2` — `default` benchmarked fine.

## Print pipeline (20 MP)

`flux2_print_*.json`. Measured: **272.5s total, peak 22.33 GiB**, output
4472×4472 = 20.0 MP, 30.4 MB PNG = **37.9 × 37.9 cm at 300 DPI**.

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

**`ImageUpscaleWithModel` tiles spatially.** `nodes_upscale_model.py` uses
`comfy.utils.tiled_scale` at `tile=512, overlap=32` with an OOM backoff loop
(`tile //= 2` down to 128) and writes to `intermediate_device()`. So a 67 MP
intermediate is safe on 24 GiB. This is the only *spatial* tiling in core —
`VAEDecodeTiled` tiles only the VAE, and SeedVR2's chunking is **temporal**
(video frames), not spatial.

To change print size, edit the `ImageScale` width/height. At 300 DPI: 4472² =
37.9 cm²; A3 portrait = 3508×4961. Max 16384 per side.

The UI copy is deployed to
`vendor/ComfyUI/user/default/workflows/FLUX.2 Print.json`. **The two formats
are not interchangeable** — API format is `{id: {class_type, inputs}}`, UI format
needs `nodes`/`links` arrays. There is no conversion endpoint; maintain both.

**The deployed copy is disposable.** `vendor/ComfyUI/.gitignore:20` ignores
`/user/`, so anything saved from the ComfyUI UI is untracked and dies with a
submodule re-clone. `workflows/` in the repo root is the durable copy — author
there, then copy into `user/default/workflows/` to expose it in the UI.

Saving from the UI bakes in whatever the widgets currently hold — including a
`control_after_generate: randomize` seed. Keep the repo copy on a fixed seed for
reproducibility and let the UI tab stay "modified"; that dirty dot is just the
randomized seed diverging from disk.

Load a workflow into the open canvas without clicking:

```js
// evaluate_script, after waiting for app && app.canvas && app.graph
const wf = await (await fetch('/api/userdata/workflows%2FFLUX.2%20Print.json')).json();
await app.loadGraphData(wf, true, true, 'FLUX.2 Print');
await app.queuePrompt(0, 1);          // Run
```

Calling `loadGraphData` before the canvas exists throws
`Cannot read properties of undefined (reading 'setGraph')`. Poll for
`app && app.canvas && app.graph` first.

Node chain:

```
UNETLoader(flux2_dev_fp8mixed.safetensors) ─┐
CLIPLoader(mistral_..., type=flux2) → CLIPTextEncode → FluxGuidance(4.0) ─┤
                                                      EmptyFlux2LatentImage ─┤
                                                      Flux2Scheduler(steps,w,h) ─┤
                                                      KSamplerSelect(euler) ─┤
                                                      RandomNoise(seed) ─┤
                          BasicGuider ← model,conditioning ────────────────┤
                                       SamplerCustomAdvanced ←─────────────┘
                                       → VAEDecode → SaveImage
```

FLUX.2-specific nodes (`comfy_extras/nodes_flux.py`):

- **`EmptyFlux2LatentImage`** — emits **128-channel** latents at `h//16, w//16`.
  Plain `EmptyLatentImage` is wrong (4-ch).
- **`Flux2Scheduler`** — `steps, width, height` → SIGMAS, so the **custom sampler
  path** (`SamplerCustomAdvanced`) is required, not `KSampler`.
- `FluxGuidance` applies — `model_base.Flux2` inherits `Flux.extra_conds`.

`comfyui-workflow-templates` ships **no local JSON**; build from node schemas or
`/object_info/{node_class}`.

## Gotchas

| Issue | Detail |
|---|---|
| `conda run` false negative | Reports torch missing when it is installed. Use `conda activate`. |
| `/models/diffusion_models` empty | `.gguf` not in default extensions; query `/models/unet_gguf`. |
| `--lowvram` | No-op under DynamicVRAM. Does not do what its name suggests. |
| Generic Mistral GGUFs | Comfy-Org's encoder is already 30/40-layer pruned (33.14 GiB bf16 vs unsloth's full 43.9 GiB). llama.cpp builds load 10 layers whose output is discarded — wasted VRAM *and* compute. Use the Comfy-Org safetensors. |
| mmproj / vision tower | Not needed. No `pixtral`/`vision_tower`/`patch_merger` anywhere in `comfy/text_encoders/`. FLUX.2 image refs go through the VAE latent path. |
| Sawtooth VRAM above 1 MP | Expected, not a fault. Weights stream from RAM; 4 MP is verified working on Q4_K_M. Only treat sawtooth as a problem *at* 1 MP, where residency is achievable. |
| Submodule drift | All three submodules sit ahead of recorded commits; `git status` always shows ` M vendor/...`. |
| Cold start | ~18s to `/system_stats` responding. |
| Stale "Unsaved Workflow" tab | The restored tab lives in **browser localStorage**, not in `user/default/workflows/` — that directory can be empty while a broken graph still loads. A leftover Z-Image graph referencing a missing `z_image_turbo_bf16.safetensors` produced a startup error toast. Close via `app.extensionManager.workflow.closeWorkflow(w, {warnIfUnsaved:false})`. |
| Wrong CLIP `type` fails silently | That stale graph had the Mistral encoder loaded with `type=lumina2`. It loads without error and yields garbage conditioning. FLUX.2 requires `type=flux2`. |
| GGUF 4-bit buys no speed | It dequantizes to bf16 before every matmul. Smaller on disk, **2x slower** than fp8. Pick GGUF only for footprint. |
| `--enable-triton-backend` | 0% measured on both GGUF and fp8. Installed but intentionally not in `requirements_override.txt`. |
| `ImageScaleToTotalPixels` caps at 16 MP | `max: 16.0`. For a 20 MP print master use `ImageScale` with explicit width/height (max 16384/side). |
| PowerShell vars are case-insensitive | `$wf` and `$Wf` are the *same variable*. Do not clobber a parsed-JSON object with its own filename parameter. |
| Seed ≠ portable across resolution | Same seed at a new size gives a **different image**. Sigma schedule *and* noise layout both change. Carry compositions forward as latents, never by re-seeding. |
| Steps change composition at 1024² | `seq_len=4096` is under `compute_empirical_mu`'s 4300 threshold, so `mu` depends on `num_steps`. A/B step counts at **≥1440²** only. |
| 1024² is 1 MP, not 2 | Easy to misread. BFL recommends **up to 2 MP** (≈1408²–1440²) and caps at **4 MP** (2048²). The default 1024² is *half* the recommended band. |
| `POST /free` doesn't drop `nvidia-smi` usage | The device is `cudaMallocAsync`; the allocator **keeps its pool** rather than returning it to the driver. Check `torch_vram_total` in `/system_stats` — tens of MiB means models really are unloaded, regardless of what `nvidia-smi` reports. |
| PowerShell mangles `python -c` f-strings | Escaped double quotes inside an f-string format spec (`f'{\"x\":>6}'`) raise `SyntaxError: '{' was never closed`. Use a **single-quoted** PowerShell string with double quotes inside Python, or `.format()`. |
