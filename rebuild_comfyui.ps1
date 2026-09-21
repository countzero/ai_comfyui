#Requires -Version 5.0

<#
.SYNOPSIS
Automatically rebuild ComfyUI for a Windows environment.

.DESCRIPTION
This script automatically rebuilds ComfyUI for a Windows environment.

.PARAMETER version
Specifies a ComfyUI commit or tag to checkout a specific version. Defaults to
upstream's latest release. The custom-node submodules are unaffected: they stay
at the commit recorded in this repository.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\rebuild_comfyui.ps1

.EXAMPLE
.\rebuild_comfyui.ps1 -version "v0.3.59"

#>

# Without CmdletBinding an unrecognized argument lands in $args instead of
# failing, so a mistyped -verison would silently build the default version.
[CmdletBinding()]
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

# Only vendor/ComfyUI is advanced per build. The custom nodes stay at the commit
# recorded here, because advancing them is a decision with its own commit rather
# than a side effect of a rebuild. They also track "main" where ComfyUI tracks
# "master", so the single blanket update this replaces could not serve all three.
$pinnedPaths = git config --file .gitmodules --get-regexp '^submodule\..+\.path$' |
    ForEach-Object { ($_ -split '\s+', 2)[1] } |
    Where-Object { $_ -ne 'vendor/ComfyUI' }

foreach ($pinnedPath in $pinnedPaths) {
    Write-Host "Syncing ${pinnedPath} to its recorded commit..." -ForegroundColor "DarkYellow"
    git -C $pinnedPath fetch origin
    git submodule update --init --force -- $pinnedPath
}

git submodule update --init --force -- vendor/ComfyUI

# A tag pushed without a release being cut is not reachable by the fetch that
# --init performs, so ask for tags before checking one out.
git -C .\vendor\ComfyUI fetch origin --tags

# We are checking out a specific version (tag / commit)
# of the repository to enable quick debugging.
git -C .\vendor\ComfyUI checkout $version

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
