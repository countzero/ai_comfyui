# ComfyUI's Workflows sidebar reads only from vendor/ComfyUI/user/default/workflows/,
# which is gitignored and therefore wiped by any submodule re-clone. Republish the
# durable copies from workflows/ on every launch so the sidebar cannot silently empty.
& "$PSScriptRoot\deploy_workflows.ps1"

Write-Host "Starting ComfyUI..." -ForegroundColor "Yellow"

conda activate ComfyUI

# Flags are benchmark-derived (1024x1024, 20 steps, median of 3):
#   --high-ram                              128 GiB RAM box; prefer RAM over disk for offload
#   --fast fp16_accumulation cublas_ops     -10% vs baseline. Matches full --fast exactly,
#                                           so autotune / fp8_matrix_mult add nothing and are
#                                           left off (upstream flags them quality-deteriorating).
# Rejected: --enable-triton-backend (0% measured), --fast-disk (RAM is faster here),
#           --highvram / --gpu-only (klein 9B DiT + Qwen3-8B encoder are 17 GiB combined and
#           cannot co-reside in this card's 16 GiB), --lowvram (no-op under DynamicVRAM).
$command = "python .\vendor\ComfyUI\main.py --high-ram --fast fp16_accumulation cublas_ops --preview-method auto"

Write-Host $command -ForegroundColor "Green"

Invoke-Expression $command
