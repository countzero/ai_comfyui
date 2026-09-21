#Requires -Version 5.0

<#
.SYNOPSIS
Automatically rebuild ComfyUI for a Windows environment.

.DESCRIPTION
This script automatically rebuilds ComfyUI for a Windows environment.

.PARAMETER version
Checks out one specific ComfyUI tag or commit.

.PARAMETER latest
Moves the submodule pointers to the upstream branch head, then checks out
upstream's latest release. Leaves a pointer bump to commit.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\rebuild_comfyui.ps1

.EXAMPLE
.\rebuild_comfyui.ps1 -version "v0.3.59"

.EXAMPLE
.\rebuild_comfyui.ps1 -latest

#>

Param (
    [String]
    $version,

    [switch]
    $latest,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

if ($latest -And $version) {
    Write-Host "Pass either -version or -latest, not both." -ForegroundColor "Red"
    exit 1
}

if ($latest) {

    $path = [regex]::Match(
        (git -C .\vendor\ComfyUI\ ls-remote --get-url),
        '(?<=github\.com:).*?(?=\.git)'
    ).Value

    $version = (
        (Invoke-WebRequest "https://api.github.com/repos/${path}/releases/latest") | `
        ConvertFrom-Json
    ).tag_name
}

Write-Host "Building the ComfyUI project..." -ForegroundColor "Yellow"
Write-Host "Version: $(if ($version) { $version } else { 'as recorded' })" -ForegroundColor "DarkYellow"

# We are resetting every submodule to their head prior
# to updating them to avoid any merge conflicts.
git submodule foreach --recursive git reset --hard

# --remote discards the recorded pointer for the upstream branch head, which is
# what made a checkout of this repository unable to reproduce the ComfyUI its
# benchmarks were measured against. Without it the recorded commit is restored.
if ($latest) {
    git submodule update --init --recursive --remote --merge --force
} else {
    git submodule update --init --recursive --force
}

if ($version) {

    # A tag pushed without a release being cut is not reachable by the fetch the
    # line above performs, so ask for tags before checking one out.
    git -C .\vendor\ComfyUI fetch --tags
    git -C .\vendor\ComfyUI checkout $version
}

# Copies custom nodes into the correct directory.
function Copy-CustomNodes {

    Param ([String] $name)

    $sourcePath = "vendor\${name}"
    $destinationPath = "vendor\ComfyUI\custom_nodes\${name}"

    Write-Host "Copying custom node from '${sourcePath}' to '${destinationPath}'..." -ForegroundColor "Yellow"

    # We want to make sure that only the currently checked out files are present.
    if (Test-Path $destinationPath) {
        Write-Host "Removing existing directory '${destinationPath}'..." -ForegroundColor "DarkYellow"
        Remove-Item -Path $destinationPath -Recurse -Force
    }

    Write-Host "Creating destination directory '${destinationPath}'..." -ForegroundColor "DarkYellow"
    mkdir -Force "${destinationPath}"

    Get-ChildItem -Path "${sourcePath}" -Recurse | `
    Where-Object { $_.Name -ne '.git' } | `
    ForEach-Object {

        $itemPath = $_.FullName.Replace("${sourcePath}", "${destinationPath}")

        if ($_.PSIsContainer) {
            mkdir -Force $itemPath
        } else {
            Copy-Item $_.FullName -Destination $itemPath
        }
    }

    Write-Host "Successfully installed the custom node '${name}'." -ForegroundColor "Yellow"
}

Copy-CustomNodes -Name 'ComfyUI-GGUF'
Copy-CustomNodes -Name 'ComfyUI-VideoHelperSuite'

conda activate ComfyUI

# We are installing the latest available version of all ComfyUI
# project dependencies and also overriding some package versions.
pip install `
    --upgrade `
    --upgrade-strategy "eager" `
    --requirement ./requirements_override.txt

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install the Python dependencies." -ForegroundColor "Red"
    exit $LASTEXITCODE
}

conda list

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "Successfully finished the build in ${durationInSeconds} seconds." -ForegroundColor "Yellow"
Write-Host "You can now start ComfyUI by executing: .\start_comfyui.ps1" -ForegroundColor "Yellow"
