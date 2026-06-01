<#
.SYNOPSIS
    Copies the BluForge runtime files from this dev repo into an Ashita addons
    directory so code changes take effect in-game.

.DESCRIPTION
    Development is kept in this repo (E:\AshitaDev\bluforge); the in-game addon
    folder holds only the files required to run. This script syncs the runtime
    files over, creating the target (and its data subfolder) if needed.

.PARAMETER Target
    The in-game addon directory to deploy to. Defaults to E:\Ashita\addons\bluforge.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Target "D:\Ashita\addons\bluforge"
#>
param(
    [string]$Target = "E:\Ashita\addons\bluforge"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# Only the files required for the addon to run.
$files = @(
    "bluforge.lua",
    "blu.lua",
    "ui.lua",
    "data\bludata.lua",
    "data\spells.json"
)

New-Item -ItemType Directory -Path (Join-Path $Target "data") -Force | Out-Null
foreach ($f in $files) {
    Copy-Item (Join-Path $root $f) (Join-Path $Target $f) -Force
    Write-Host "  -> $f"
}
Write-Host "Deployed runtime files to $Target"
