---
name: comfyui
description: Operating the local ComfyUI install in D:\Arbeit\ai_comfyui, covering FLUX.2 Klein 9B image generation and editing, VRAM budgeting, the ComfyUI HTTP API, model placement, workflow deployment, and launch flags. Use when running, debugging, or extending ComfyUI; when working with flux2, klein, GGUF quants, text encoders, or diffusion models; when editing start_comfyui.ps1, rebuild_comfyui.ps1, deploy_workflows.ps1, or requirements_override.txt; when workflows do not appear in the ComfyUI sidebar; or when a generation OOMs, fails, or produces wrong output. Includes the conda activation gotcha that produces false "torch missing" diagnoses.
---

# ComfyUI (D:\Arbeit\ai_comfyui)

Thin wrapper repo around ComfyUI as a git submodule.

**Measurements live in `docs/`, not here.** This file holds only what is true
regardless of which GPU or model is installed.

| Doc | Covers |
|---|---|
| [`docs/hardware-16gb-ada.md`](../../../docs/hardware-16gb-ada.md) | **Current box.** RTX 4070 Ti SUPER 16 GiB + Klein 9B: resolution, steps, CFG, VRAM, workflow defaults |
| [`docs/hardware-24gb-blackwell.md`](../../../docs/hardware-24gb-blackwell.md) | Archived. RTX PRO 5000 24 GiB + FLUX.2-dev. Still valid *for that hardware* |
| [`docs/models.md`](../../../docs/models.md) | Model manifest, sources, quant tables, encoder compatibility |

**Re-read files before asserting their contents.** Memory of
`requirements_override.txt` and of the installed package set is unreliable after
context pruning. Read the file. The same applies to the docs above — do not
recite remembered benchmark numbers.

## Environment invariants

**Always activate conda in the same command.** The shell is fresh per invocation:

```powershell
conda activate ComfyUI; python .\vendor\ComfyUI\main.py ...
```

**GOTCHA — `conda run` gives false negatives.** `conda run -n ComfyUI python -c
"import torch"` from a non-activated shell reports `ModuleNotFoundError` while
torch is installed and working. It resolves to the *identical* interpreter
(`C:\Miniconda\envs\ComfyUI\python.exe`), so the interpreter is not the variable.
Treat its output as unreliable: use `conda activate ComfyUI; <cmd>`, never a bare
`conda run`, before concluding anything is missing.

Nine conda envs exist (`base`, `ComfyUI`, `c3`, `fm`, `kinema`, `llama.cpp`,
`open-webui`). Only `ComfyUI` is correct.

**Do not run `rebuild_comfyui.ps1` without reason.** It moves submodules.

## Layout

```
start_comfyui.ps1            launcher: deploy_workflows.ps1 + conda activate + main.py
deploy_workflows.ps1         publishes workflows/*_ui.json into the ComfyUI sidebar
rebuild_comfyui.ps1          submodule update + pip install
requirements_override.txt    torch pins + ComfyUI/custom-node reqs
docs/                        hardware profiles + model manifest
workflows/                   DURABLE workflow copies (tracked)
vendor/ComfyUI/              submodule
  models/{diffusion_models,text_encoders,vae,upscale_models}/   gitignored
  user/default/workflows/    DEPLOYED copies - gitignored, wiped by re-clone
  blueprints/                upstream's own templates (v0.36.0+), separate system
  output/                    generated images
```

## Workflows

Every UI workflow needs an API twin and vice versa — the formats are **not**
interchangeable and there is no conversion endpoint. API format is
`{id: {class_type, inputs}}`; UI format needs `nodes`/`links` arrays.

| Repo file | Sidebar path |
|---|---|
| `flux2_klein9b_turbo_ui.json` | `FLUX.2 Klein 9B/1 Turbo` |
| `flux2_klein9b_draft_ui.json` | `FLUX.2 Klein 9B/2 Draft` |
| `flux2_klein9b_print_ui.json` | `FLUX.2 Klein 9B/3 Print` |
| `flux2_klein9b_edit_ui.json` | `FLUX.2 Klein 9B/4 Edit` |
| `upscale_4x_ui.json` | `Utility/Upscale 4x` |
| `flux2_dev_*` | not deployed — dev weights are not installed |

### Workflows missing from the sidebar

The sidebar lists **only** `vendor/ComfyUI/user/default/workflows/`. That path is
under `/user/`, which `vendor/ComfyUI/.gitignore:20` ignores, so a submodule
re-clone or `git submodule update --force` **silently empties it** — this is what
happened at v0.36.0.

Fix: run `./deploy_workflows.ps1` (or just relaunch; `start_comfyui.ps1` calls
it). It skips files that already exist so UI-side edits survive; `-Force`
overwrites. Verify with `GET /api/userdata?dir=workflows&recurse=true` — the
sidebar renders subdirectories as a tree.

`vendor/ComfyUI/blueprints/` is a **different** system (upstream's bundled
templates) and does not feed that sidebar.

## FLUX.2 node graph

```
UNETLoader ─┐
CLIPLoader(type=flux2) → CLIPTextEncode ─┤
                         CLIPTextEncode(neg) ─┤
                                    CFGGuider ← model, positive, negative, cfg
                         EmptyFlux2LatentImage ─┤
                         Flux2Scheduler(steps,w,h) ─┤
                         KSamplerSelect(euler) ─┤
                         RandomNoise(seed) ─┤
                                    SamplerCustomAdvanced ←┘
                                    → VAEDecode → SaveImage
```

FLUX.2-specific nodes (`comfy_extras/nodes_flux.py`):

- **`EmptyFlux2LatentImage`** — emits **128-channel** latents at `h//16, w//16`.
  Plain `EmptyLatentImage` is wrong (4-ch).
- **`Flux2Scheduler`** — `steps, width, height` → SIGMAS, so the **custom sampler
  path** (`SamplerCustomAdvanced`) is required, not `KSampler`.

Guider choice is per-model, not preference:

| Model | Guider | Negative |
|---|---|---|
| FLUX.2-dev | `FluxGuidance(4)` → `BasicGuider` | unsupported |
| Klein base (undistilled) | `CFGGuider(cfg=5)` | **real negative prompt works** |
| Klein distilled | `CFGGuider(cfg=1)` | `ConditioningZeroOut` |

**`cfg=1.0` costs half** — ComfyUI short-circuits to one model eval; any cfg > 1
runs positive and negative passes.

Image editing adds `LoadImage → ImageScaleToTotalPixels → VAEEncode →
ReferenceLatent`, chaining one `ReferenceLatent` per reference. Set
`resolution_steps=16` so the reference lands on the VAE stride. Feed
`GetImageSize` into both `EmptyFlux2LatentImage` and `Flux2Scheduler` to size the
output from the reference.

Set width/height on **both** `EmptyFlux2LatentImage` and `Flux2Scheduler`, and
keep dimensions divisible by 16.

`comfyui-workflow-templates` ships **no local JSON**; build from
`/object_info/{node_class}` or copy from `vendor/ComfyUI/blueprints/`.

## `compute_empirical_mu` branches at `seq_len > 4300`

`Flux2Scheduler` → `get_schedule(steps, seq_len)` → `compute_empirical_mu`
(`comfy_extras/nodes_flux.py:188`), where `seq_len = width*height/256`. Below the
threshold `mu` interpolates on `num_steps`; above it `mu` is **step-independent**.

| Dim | seq_len | step-dependent? |
|---|---|---|
| 1024² | 4,096 | **yes** |
| 1440² | 8,100 | no |
| 2048² | 16,384 | no |

**Consequence: at 1024², changing steps changes the composition.** A draft→print
handoff that varies only the step count is therefore valid at **≥1440² only**.

### Seeds are NOT portable across resolutions

Same seed at a different resolution gives a **different image**, not a bigger one:

1. **Sigma schedule is resolution-dependent** — `seq_len` feeds `mu`.
2. **Noise field is spatially unrelated** — `comfy.sample.prepare_noise` does
   `torch.manual_seed(seed)` then `randn(latent.size())`. The same value *stream*
   lands at different spatial positions.

Carry a composition forward as a **latent** (`VAEEncode` + `ReferenceLatent`) or
upscale the pixels. Seeds are likewise **not** comparable between the base and
distilled checkpoints — different weights, different trajectories.

## HTTP API (127.0.0.1:8188)

Drive with `curl` / `Invoke-RestMethod`. No MCP needed.

| Endpoint | Use |
|---|---|
| `GET /system_stats` | GPU, VRAM total/free, torch version, **active argv** |
| `GET /models/{folder}` | Installed models — use `unet_gguf` for GGUF |
| `GET /object_info/{node_class}` | Exact node schema |
| `POST /prompt` | Enqueue API-format workflow → `prompt_id` |
| `GET /history/{prompt_id}` | Results, timings, **full Python tracebacks** |
| `POST /free` | Unload models, free VRAM |
| `POST /interrupt`, `GET`/`POST /queue` | Cancel, inspect, clear |
| `GET /view`, `POST /upload/image` | Fetch outputs, push inputs |
| `GET /api/userdata?dir=workflows&recurse=true` | What the sidebar will list |

**Context safety: never `GET /object_info` bare — it is megabytes.** Always
`/object_info/{node_class}`.

### Timing runs correctly

**Client wall-clock lies** — it includes queue wait and model load. Read the
server-side delta from `GET /history/{id}`:

```
status.messages → ('execution_start', {timestamp}), ('execution_success', {timestamp})
```

**Aborting the client does not cancel the queue.** ComfyUI finishes the job;
resubmitting the identical prompt then returns a **fully cached** result in ~0s
while the poller waits for the queue to drain. Check `execution_cached` — if its
node count equals the total, the run measured nothing. Use `POST /interrupt` and
`POST /queue` (clear) to really cancel.

Vary the seed to defeat caching when you need a fresh render.

### Recover the prompt and seed from any output PNG

`SaveImage` embeds the full **API-format workflow** in a PNG text chunk:

```python
from PIL import Image; import json
wf = json.loads(Image.open('output/flux2_klein9b_print_00001_.png').info['prompt'])
```

This round-trips straight back into `POST /prompt`.

## Tool selection

- **`curl`/Bash — drive everything.** Full API coverage, and output can be
  filtered before it reaches context.
- **chrome-devtools — look, don't drive.** Good for screenshots and
  `list_console_messages`, and for `app.loadGraphData` to validate that a UI
  workflow opens cleanly. The graph is a `<canvas>` (litegraph), so
  `take_snapshot` yields a useless a11y tree and `click(uid)` cannot reach nodes.
  It caches `/api/userdata` aggressively — cache-bust after redeploying.
- **MCP — not installed, not needed.**

## Gotchas

| Issue | Detail |
|---|---|
| `conda run` false negative | Reports torch missing when it is installed. Use `conda activate`. |
| Sidebar empty | `user/default/workflows/` was wiped. Run `deploy_workflows.ps1`. |
| Wall-clock timings wrong | Use server-side `execution_start`→`execution_success`. |
| Client abort ≠ cancel | The queue keeps running; the next identical prompt returns cached. |
| Fully cached run | `execution_cached` == node count means nothing was measured. |
| Wrong CLIP `type` fails silently | A Mistral encoder loaded as `type=lumina2` loads fine and yields garbage. FLUX.2 needs `type=flux2`. |
| `/models/diffusion_models` empty for GGUF | `.gguf` not in default extensions; query `/models/unet_gguf`. |
| `--lowvram` | No-op under DynamicVRAM. |
| Seed ≠ portable across resolution | Sigma schedule *and* noise layout both change. |
| Seed ≠ portable base↔distilled | Different weights entirely. |
| Steps change composition at 1024² | `seq_len=4096` is under the 4300 threshold. A/B steps at ≥1440². |
| 1024² is 1 MP, not 2 | BFL recommends **up to 2 MP** (≈1440²) and caps at **4 MP** (2048²). |
| `ImageScaleToTotalPixels` caps at 16 MP | For a 20 MP master use `ImageScale` with explicit width/height (max 16384/side). |
| `POST /free` doesn't drop `nvidia-smi` usage | `cudaMallocAsync` keeps its pool. Check `torch_vram_total` in `/system_stats`. |
| PowerShell vars are case-insensitive | `$wf` and `$Wf` are the *same variable*. |
| PowerShell mangles `python -c` f-strings | Escaped quotes inside a format spec raise `SyntaxError`. Use single-quoted PS strings with double quotes inside Python. |
| Stale "Unsaved Workflow" tab | Lives in **browser localStorage**, not on disk. Close via `app.extensionManager.workflow.closeWorkflow(w, {warnIfUnsaved:false})`. |
| `nvidia-smi` GPU order ≠ CUDA order | CUDA defaults to `FASTEST_FIRST`. Trust `/system_stats`. |
