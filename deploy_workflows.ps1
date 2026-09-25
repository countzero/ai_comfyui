<#
.SYNOPSIS
    Publishes the repo's UI workflows into ComfyUI's user directory.

.DESCRIPTION
    ComfyUI's Workflows sidebar reads only from
    vendor/ComfyUI/user/default/workflows/. That path sits under /user/, which
    vendor/ComfyUI/.gitignore ignores, so it is wiped by any submodule re-clone
    or `git submodule update --force`. That is exactly what emptied the sidebar
    when the submodule moved to v0.36.0.

    workflows/ in the repo root is therefore the durable copy and this script
    republishes it. Existing files are left alone by default so that edits saved
    from the ComfyUI UI survive; pass -Force to overwrite them.

    Anything in the target tree that $workflows does not name is deleted, which
    makes the table the single source of truth for the sidebar. Without that the
    target only ever accumulates: renaming an entry leaves the old path behind
    and the sidebar shows both layouts at once. The cost is that a workflow
    created in the UI and never added to the table does not survive a deploy.

    Only *_ui.json files are published. The *_api.json twins drive POST /prompt
    and would render as broken graphs in the canvas. A workflow missing either
    half is warned about rather than skipped, since the _ui half still deploys
    and a sidebar entry without an API twin is usable from the canvas.

.PARAMETER Force
    Overwrite workflows already present in the user directory.

.EXAMPLE
    ./deploy_workflows.ps1
    ./deploy_workflows.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$sourceDirectory = Join-Path $PSScriptRoot "workflows"
$targetDirectory = Join-Path $PSScriptRoot "vendor\ComfyUI\user\default\workflows"

# Maps a repo file to its display path in the sidebar. ComfyUI hides the .json
# extension and renders subdirectories as a tree, so the numeric prefixes are
# what force pipeline order against the sidebar's alphabetical sort. "Dev" is
# capitalized so that it sorts above "Klein 9B" rather than below it.
$workflows = [ordered]@{
    "flux2_dev_draft_ui.json"     = "FLUX.2 Dev\1 Draft.json"
    "flux2_dev_print_ui.json"     = "FLUX.2 Dev\2 Print.json"
    "flux2_dev_edit_ui.json"      = "FLUX.2 Dev\3 Edit.json"
    "flux2_klein9b_turbo_ui.json" = "FLUX.2 Klein 9B\1 Turbo.json"
    "flux2_klein9b_draft_ui.json" = "FLUX.2 Klein 9B\2 Draft.json"
    "flux2_klein9b_print_ui.json" = "FLUX.2 Klein 9B\3 Print.json"
    "flux2_klein9b_edit_ui.json"  = "FLUX.2 Klein 9B\4 Edit.json"
    "krea2_turbo_t2i_ui.json"     = "Krea 2\1 Text to Image.json"
    "krea2_turbo_print_ui.json"   = "Krea 2\2 Print.json"
    "qwen_image21_t2i_ui.json"    = "Qwen-Image 2.1\1 Text to Image.json"
    "qwen_image21_edit_ui.json"   = "Qwen-Image 2.1\2 Edit.json"
    "qwen_image21_rgba_ui.json"   = "Qwen-Image 2.1\3 Transparent.json"
    "upscale_4x_ui.json"          = "Utility\Upscale 4x.json"
}

Write-Host "Deploying workflows to ComfyUI..." -ForegroundColor "Yellow"

# Only the _ui half is published, so a missing _api twin is invisible here until
# something tries to POST /prompt with it. Nothing else checks the pairing.
Get-ChildItem -LiteralPath $sourceDirectory -File -Filter "*.json" |
    ForEach-Object { $_.Name -replace '_(ui|api)\.json$', '' } |
    Group-Object |
    Where-Object { $_.Count -ne 2 } |
    ForEach-Object { Write-Warning "Unpaired workflow, needs a _ui.json and an _api.json: $($_.Name)" }

if (-Not (Test-Path -LiteralPath $targetDirectory)) {
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

# Windows paths compare case-insensitively, so the sidebar treats a table entry
# and a target file differing only in case as the same file.
$mappedPaths = [System.Collections.Generic.HashSet[String]]::new(
    [String[]]$workflows.Values,
    [StringComparer]::OrdinalIgnoreCase
)

$pruned = 0

foreach ($targetFile in (Get-ChildItem -LiteralPath $targetDirectory -Recurse -File)) {

    $relativePath = $targetFile.FullName.Substring($targetDirectory.Length).TrimStart('\')

    if ($mappedPaths.Contains($relativePath)) {
        continue
    }

    Remove-Item -LiteralPath $targetFile.FullName -Force
    Write-Host "  prune   ${relativePath}" -ForegroundColor "DarkYellow"
    $pruned++
}

# Deepest first, so a nested directory is gone before its parent is tested.
Get-ChildItem -LiteralPath $targetDirectory -Recurse -Directory |
    Sort-Object -Property { $_.FullName.Length } -Descending |
    Where-Object { -Not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File) } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

$deployed = 0
$skipped = 0

foreach ($sourceName in $workflows.Keys) {

    $sourcePath = Join-Path $sourceDirectory $sourceName
    $targetPath = Join-Path $targetDirectory $workflows[$sourceName]

    if (-Not (Test-Path -LiteralPath $sourcePath)) {
        Write-Warning "Missing source workflow: ${sourceName}"
        continue
    }

    if ((Test-Path -LiteralPath $targetPath) -And (-Not $Force)) {
        Write-Host "  skip    $($workflows[$sourceName]) (exists)" -ForegroundColor "DarkGray"
        $skipped++
        continue
    }

    $targetParent = Split-Path -Path $targetPath -Parent

    if (-Not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    Write-Host "  deploy  $($workflows[$sourceName])" -ForegroundColor "Green"
    $deployed++
}

Write-Host "Deployed ${deployed}, skipped ${skipped}, pruned ${pruned}." -ForegroundColor "Yellow"

if ($skipped -gt 0 -And -Not $Force) {
    Write-Host "Use -Force to overwrite workflows edited in the ComfyUI UI." -ForegroundColor "DarkGray"
}
