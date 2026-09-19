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
FLUX.2-dev GGUF as of 2026-09-19.

## Environment invariants

**Always activate conda in the same command.** The shell is fresh per invocation:

```powershell
conda activate ComfyUI; python .\vendor\ComfyUI\main.py ...
```

**GOTCHA — `conda run` gives false negatives.** `conda run -n ComfyUI python -c
"import torch"` from a non-activated shell reported `ModuleNotFoundError` while
torch 2.11.0+cu130 was installed and working. It resolves to the *identical*
interpreter (`C:\Miniconda\envs\ComfyUI\python.exe`), so the interpreter is not
the variable. This caused a wrong "environment is broken" diagnosis that nearly
triggered an unnecessary rebuild. Use `conda activate ComfyUI; <cmd>`, never a
bare `conda run`, before concluding anything is missing.

Nine conda envs exist (`base`, `ComfyUI`, `c3`, `fm`, `kinema`, `llama.cpp`,
`open-webui`). Only `ComfyUI` is correct.

**Re-read files before asserting their contents.** Claims about
`requirements_override.txt` and installed packages were both wrong when made
from memory after context pruning. Read the file.

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
workflows/flux2_dev_gguf_api.json      working FLUX.2 API-format workflow
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
| `--lowvram` | **No-op** — *"Doesn't do anything if dynamic vram is enabled."* Removed. |
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
| `workflows/flux2_dev_fp8_api.json` | API | fp8 | **fastest** — default choice |
| `workflows/flux2_dev_fp8_ui.json` | UI | fp8 | **fastest** — canvas editor |
| `workflows/flux2_print_20mp_api.json` | API | fp8 | 4 MP → 4x → 20 MP print master |
| `workflows/flux2_print_20mp_ui.json` | UI | fp8 | same, canvas editor |
| `workflows/flux2_dev_gguf_api.json` | API | GGUF | 2x slower; smaller footprint |
| `workflows/flux2_dev_gguf_ui.json` | UI | GGUF | same, canvas editor |

UI copies are deployed to `vendor/ComfyUI/user/default/workflows/` as
**FLUX.2-dev fp8**, **FLUX.2 Print 20MP**, and **FLUX.2-dev GGUF**. Every UI
workflow needs an API twin (and vice versa) — the formats are not
interchangeable, so adding one means adding both.

fp8 uses `UNETLoader` (`unet_name`, `weight_dtype`); GGUF uses `UnetLoaderGGUF`
(`unet_name` only). `weight_dtype` options: `default`, `fp8_e4m3fn`,
`fp8_e4m3fn_fast`, `fp8_e5m2` — `default` benchmarked fine.

## Print pipeline (20 MP)

`flux2_print_20mp_*.json`. Measured: **310.4s total, peak 23.13 GiB**, output
4472×4472 = 20.0 MP, 23 MB PNG = **37.9 × 37.9 cm at 300 DPI**.

```
FLUX.2 fp8 @ 2048²  →  ImageUpscaleWithModel (4xNomos2_hq_dat2)  →  8192² (67 MP)
                    →  ImageScale lanczos 4472×4472              →  20 MP master
```

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
`vendor/ComfyUI/user/default/workflows/FLUX.2-dev GGUF.json`. **The two formats
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
const wf = await (await fetch('/api/userdata/workflows%2FFLUX.2-dev%20GGUF.json')).json();
await app.loadGraphData(wf, true, true, 'FLUX.2-dev GGUF');
await app.queuePrompt(0, 1);          // Run
```

Calling `loadGraphData` before the canvas exists throws
`Cannot read properties of undefined (reading 'setGraph')`. Poll for
`app && app.canvas && app.graph` first.

Node chain:

```
UnetLoaderGGUF(flux2-dev-Q4_K_M.gguf) ─┐
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
| PowerShell vars are case-insensitive | `$wf` and `$Wf` are the *same variable*. Clobbering a parsed-JSON object with its own filename parameter cost real debugging time in the bench harness. |
