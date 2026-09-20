# HTTP API

Read when driving the server over HTTP, or when timing a run.

The server listens on `127.0.0.1:8188`. `curl` and `Invoke-RestMethod` cover
every endpoint it has, so nothing here needs a browser or an MCP server.

## Endpoints

| Endpoint                                       | Use                                                       |
| ---------------------------------------------- | --------------------------------------------------------- |
| `GET /system_stats`                            | GPU, VRAM total and free, torch version, the active argv  |
| `GET /models/{folder}`                         | Installed models                                          |
| `GET /object_info/{node_class}`                | Exact node schema                                         |
| `POST /prompt`                                 | Enqueue an API-format workflow, returns a `prompt_id`     |
| `GET /history/{prompt_id}`                     | Results, timings, and full Python tracebacks              |
| `POST /free`                                   | Unload models and free VRAM                               |
| `POST /interrupt`, `GET`/`POST /queue`         | Cancel, inspect, clear                                    |
| `GET /view`, `POST /upload/image`              | Fetch outputs, push inputs                                |
| `GET /api/userdata?dir=workflows&recurse=true` | What the sidebar will list                                |

`GET /system_stats` is also the authority on which GPU ComfyUI is using, since
CUDA's device order is not `nvidia-smi`'s.

Two endpoints have surprises. `GET /object_info` without a node class returns
megabytes of JSON, so always name the class. `GET /models/diffusion_models`
returns nothing for GGUF weights, which is a file-extension default rather than
a missing model (`docs/models.md` → *fp8 vs GGUF: fp8 wins*).

`POST /free` does not reduce what `nvidia-smi` reports, because `cudaMallocAsync`
keeps its pool. Read `torch_vram_total` from `GET /system_stats` instead.

## Timing a run

**Client wall-clock lies.** It includes queue wait and model load, which can be
most of the measurement. Read the server-side delta out of `GET /history/{id}`:

```powershell
$h.$id.status.messages   # ('execution_start', @{timestamp=...}), ('execution_success', ...)
```

**Aborting the client does not cancel the queue.** ComfyUI finishes the job it
was given. Resubmitting an identical prompt then returns a fully cached result in
about zero seconds while the poller waits for the queue to drain. Check
`execution_cached`: if its node count equals the total node count, the run
measured nothing. `POST /interrupt` plus `POST /queue` (clear) is the real
cancel, and varying the seed defeats the cache when a fresh render is what you
want.

Both traps have produced wrong numbers in this repository, so a timing that looks
too good is more likely to be one of them than a real result.

## Recovering the prompt and seed from an output PNG

`SaveImage` embeds the full API-format workflow in a PNG text chunk, which
round-trips straight back into `POST /prompt`:

```python
from PIL import Image; import json
wf = json.loads(Image.open('output/flux2_klein9b_print_00001_.png').info['prompt'])
```
