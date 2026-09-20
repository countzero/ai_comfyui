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
    and would render as broken graphs in the canvas.

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
# what force pipeline order against the sidebar's alphabetical sort.
#
# The flux2_dev_* workflows are deliberately absent: their weights
# (flux2_dev_fp8mixed, mistral_3_small_flux2_fp4_mixed) are no longer installed,
# so publishing them would only produce red nodes.
$workflows = [ordered]@{
    "flux2_klein9b_turbo_ui.json" = "FLUX.2 Klein 9B\1 Turbo.json"
    "flux2_klein9b_draft_ui.json" = "FLUX.2 Klein 9B\2 Draft.json"
    "flux2_klein9b_print_ui.json" = "FLUX.2 Klein 9B\3 Print.json"
    "flux2_klein9b_edit_ui.json"  = "FLUX.2 Klein 9B\4 Edit.json"
    "upscale_4x_ui.json"          = "Utility\Upscale 4x.json"
}

Write-Host "Deploying workflows to ComfyUI..." -ForegroundColor "Yellow"

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
