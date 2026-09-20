# Workflows

Read when building or editing a workflow graph, or when the sidebar is wrong.

## The two formats are not interchangeable

Every UI workflow needs an API twin and vice versa, and there is no conversion
endpoint. API format is `{id: {class_type, inputs}}`; UI format needs `nodes` and
`links` arrays. `workflows/` holds both halves of each pair, `<name>_ui.json` and
`<name>_api.json`, and is the durable copy of both.

`comfyui-workflow-templates` ships no local JSON. Build a new graph from
`/object_info/{node_class}` or copy one out of `vendor/ComfyUI/blueprints/`.

## Workflows missing from the sidebar

The sidebar lists only `vendor/ComfyUI/user/default/workflows/`. That path is
under `/user/`, which `vendor/ComfyUI/.gitignore:20` ignores, so a submodule
re-clone or `git submodule update --force` silently empties it. That is what
emptied it when the submodule moved to v0.36.0.

Run `./deploy_workflows.ps1` to republish, or just relaunch, since
`start_comfyui.ps1` calls it. It skips files that already exist so that edits
saved from the UI survive; `-Force` overwrites them. Which repo file lands at
which sidebar path is the `$workflows` table in that script. Verify a deployment
with `GET /api/userdata?dir=workflows&recurse=true`; the sidebar renders
subdirectories as a tree.

`vendor/ComfyUI/blueprints/` is a different system, upstream's own bundled
templates, and does not feed that sidebar.

A workflow tab titled "Unsaved Workflow" is not on disk at all. It lives in the
browser's localStorage and survives a redeploy. Close it with
`app.extensionManager.workflow.closeWorkflow(w, {warnIfUnsaved: false})`.

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

Two nodes in `comfy_extras/nodes_flux.py` are FLUX.2-specific:

- **`EmptyFlux2LatentImage`** emits 128-channel latents at `h//16, w//16`. Plain
  `EmptyLatentImage` is wrong, being 4-channel.
- **`Flux2Scheduler`** takes `steps, width, height` and returns SIGMAS, so the
  custom sampler path (`SamplerCustomAdvanced`) is required rather than
  `KSampler`.

Set width and height on **both** `EmptyFlux2LatentImage` and `Flux2Scheduler`,
and keep both divisible by 16.

A wrong CLIP `type` fails silently: a Mistral encoder loaded as `type=lumina2`
loads without error and yields garbage. Every FLUX.2 variant needs `type=flux2`
(`docs/models.md` → *Encoders are not interchangeable*).

### Guider choice is per model, not preference

| Model              | Guider                            | Negative prompt       |
| ------------------ | --------------------------------- | --------------------- |
| FLUX.2-dev         | `FluxGuidance(4)` → `BasicGuider` | not supported         |
| Klein 9B base      | `CFGGuider(cfg=5)`                | live                  |
| Klein 9B distilled | `CFGGuider(cfg=1)`                | `ConditioningZeroOut` |

BFL's "negative prompts are not supported" guidance describes dev and distilled
guidance. Klein base is undistilled and runs true CFG, so its negative prompt is
live; klein distilled runs at cfg 1, where the negative is ignored.

`cfg = 1.0` costs half of any higher value, because ComfyUI short-circuits to a
single model evaluation while any cfg above 1 runs a positive and a negative
pass. Measured on the current card in
`docs/hardware-16gb-ada.md` → *Klein 9B differs structurally from dev*.

### Image editing

Editing adds `LoadImage → ImageScaleToTotalPixels → VAEEncode → ReferenceLatent`,
chaining one `ReferenceLatent` per reference image. Set `resolution_steps=16` so
the reference lands on the VAE stride. Feed `GetImageSize` into both
`EmptyFlux2LatentImage` and `Flux2Scheduler` to size the output from the
reference.

`ImageScaleToTotalPixels` caps at 16 MP. For a 20 MP master use `ImageScale` with
an explicit width and height, to a maximum of 16384 per side.

## `compute_empirical_mu` branches at `seq_len > 4300`

`Flux2Scheduler` calls `get_schedule(steps, seq_len)`, which calls
`compute_empirical_mu` (`comfy_extras/nodes_flux.py:188`), where
`seq_len = width * height / 256`. Below the threshold `mu` interpolates on
`num_steps`; above it `mu` is step-independent.

| Dimensions | `seq_len` | Step-dependent |
| ---------- | --------- | -------------- |
| 1024²      | 4,096     | yes            |
| 1440²      | 8,100     | no             |
| 2048²      | 16,384    | no             |

So at 1024² changing the step count changes the composition. Two consequences: a
draft-to-print handoff that varies only the step count is valid at 1440² and
above, and an A/B of two step counts measures nothing at 1024².

BFL recommends up to 2 MP and caps FLUX.2 at 4 MP, which makes 1440² (1.98 MP)
the top of the recommended band and 2048² the ceiling. 1024² is 1 MP, not 2.

## Seeds are not portable across resolutions

The same seed at a different resolution gives a different image, not a bigger
one, for two independent reasons:

1. **The sigma schedule is resolution-dependent**, since `seq_len` feeds `mu`.
2. **The noise field is spatially unrelated.** `comfy.sample.prepare_noise` calls
   `torch.manual_seed(seed)` and then `randn(latent.size())`, so the same value
   stream lands at different spatial positions.

Carry a composition forward as a latent (`VAEEncode` plus `ReferenceLatent`) or
upscale the pixels instead. Seeds are likewise not comparable between the base
and distilled checkpoints, which are different weights and therefore different
trajectories.
