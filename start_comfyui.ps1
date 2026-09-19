Write-Host "Starting ComfyUI..." -ForegroundColor "Yellow"

conda activate ComfyUI

# Flags are benchmark-derived (1024x1024, 20 steps, median of 3):
#   --high-ram                              191 GiB RAM box; prefer RAM over disk for offload
#   --fast fp16_accumulation cublas_ops     -10% vs baseline. Matches full --fast exactly,
#                                           so autotune / fp8_matrix_mult add nothing and are
#                                           left off (upstream flags them quality-deteriorating).
# Rejected: --enable-triton-backend (0% on both GGUF and fp8), --fast-disk (RAM is faster here),
#           --highvram / --gpu-only (would try to hold 30+ GiB in 24 GiB), --lowvram (no-op).
$command = "python .\vendor\ComfyUI\main.py --high-ram --fast fp16_accumulation cublas_ops --preview-method auto"

Write-Host $command -ForegroundColor "Green"

Invoke-Expression $command
