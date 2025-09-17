Write-Host "Starting ComfyUI..." -ForegroundColor "Yellow"

conda activate ComfyUI

$command = "python .\vendor\ComfyUI\main.py --preview-method auto"

Write-Host $command -ForegroundColor "Green"

Invoke-Expression $command
