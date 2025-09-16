#Requires -Version 5.0

<#
.SYNOPSIS
Automatically rebuild ComfyUI for a Windows environment.

.DESCRIPTION
This script automatically rebuilds ComfyUI for a Windows environment.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\rebuild_comfyui.ps1

.EXAMPLE
.\rebuild_comfyui.ps1 -version "v0.3.59"

#>

Param (
    [String]
    $version,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

# We are defaulting the optional version to the tag of the
# "latest" release in GitHub to avoid unstable versions.
if (!$version) {

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
Write-Host "Version: ${version}" -ForegroundColor "DarkYellow"

# We are resetting every submodule to their head prior
# to updating them to avoid any merge conflicts.
git submodule foreach --recursive git reset --hard

git submodule update --remote --merge --force

# We are checking out a specific version (tag / commit)
# of the repository to enable quick debugging.
git -C ./vendor/ComfyUI checkout $version

conda activate ComfyUI

# We are installing the latest available version of all ComfyUI
# project dependencies and also overriding some package versions.
pip install `
    --upgrade `
    --upgrade-strategy "eager" `
    --requirement ./requirements_override.txt

conda list

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "Successfully finished the build in ${durationInSeconds} seconds." -ForegroundColor "Yellow"

Write-Host "Starting ComfyUI..." -ForegroundColor "Yellow"

python .\vendor\ComfyUI\main.py
