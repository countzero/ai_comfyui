# ComfyUI's Workflows sidebar reads only from vendor/ComfyUI/user/default/workflows/,
# which is gitignored and therefore wiped by any submodule re-clone. Republish the
# durable copies from workflows/ on every launch so the sidebar cannot silently empty.
& "$PSScriptRoot\deploy_workflows.ps1"

Write-Host "Starting ComfyUI..." -ForegroundColor "Yellow"

conda activate ComfyUI

# Flags are benchmark-derived (1024x1024, 20 steps, median of 3). The numbers
# behind each one live in the profile for the machine they were measured on,
# docs/hardware-24gb-blackwell.md and docs/hardware-16gb-ada.md.
#   --high-ram                              prefer RAM over disk for offload
#   --fast fp16_accumulation cublas_ops     -10% vs baseline. Matches full --fast exactly,
#                                           so autotune / fp8_matrix_mult add nothing and are
#                                           left off (upstream flags them quality-deteriorating).
#   --preview-method taesd                  decodes previews through vae_approx/taef2_decoder,
#                                           which covers every FLUX.2 workflow. "auto" cannot:
#                                           it rewrites itself to latent2rgb before the TAESD
#                                           branch is reachable. A model with no approximate
#                                           decoder, Qwen-Image-2.1 among them, falls back to
#                                           latent2rgb by itself, so this is never worse.
#                                           Costs 2.4% (91.0s vs 88.8s at 2048 square, 25 steps).
#   --vram-headroom 2.5                     this GPU also drives the display. At 2048 square the
#                                           sampler otherwise peaks at 21.04 GiB and leaves the
#                                           desktop 2.85 GiB; with the reserve it peaks at 19.93
#                                           and leaves 3.96, and did not measure slower.
# Rejected: --enable-triton-backend (0% on GGUF, fp8 and int8), --fast-disk (RAM is faster here),
#           --highvram / --gpu-only (whether a DiT and its encoder co-reside is a property of the
#           machine, not of the flag), --lowvram (no-op under DynamicVRAM).
# Also rejected, for desktop responsiveness: lowering the process priority. Setting the server to
# Idle left GPU utilisation at its 99% median and made the render about 30% slower, because
# Windows priority governs the CPU feeding the queue, not GPU scheduling. Capping power or locking
# clocks is refused outright by this laptop's firmware, and would be pointless anyway: the card
# already sits at its 95 W limit for 86% of a render with SM clocks at 1300 of 3090 MHz.
$command = "python .\vendor\ComfyUI\main.py --high-ram --fast fp16_accumulation cublas_ops --preview-method taesd --vram-headroom 2.5"

Write-Host $command -ForegroundColor "Green"

Invoke-Expression $command
