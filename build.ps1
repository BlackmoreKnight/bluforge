<#
.SYNOPSIS
    Builds the BluForge release zip containing only the files required for the
    addon to run, laid out so it extracts straight into an Ashita addons folder.

.DESCRIPTION
    Produces bluforge-<version>.zip in the output directory. This mirrors what
    the GitHub Actions release workflow builds, for local testing.

.PARAMETER Version
    Version label used in the output file name (e.g. v1.2). Defaults to the
    addon.version declared in bluforge.lua, prefixed with 'v'.

.PARAMETER OutDir
    Directory to write the zip into. Defaults to the current directory.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Version v1.2 -OutDir dist
#>
param(
    [string]$Version,
    [string]$OutDir = "."
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot

# Derive the version from bluforge.lua if not supplied.
if ([string]::IsNullOrEmpty($Version)) {
    $line = Select-String -Path (Join-Path $root "bluforge.lua") -Pattern "addon.version\s*=\s*'([^']+)'" | Select-Object -First 1
    if ($line) { $Version = "v" + $line.Matches[0].Groups[1].Value } else { $Version = "vdev" }
}

# Only the files required for the addon to run.
$map = [ordered]@{
    "bluforge/bluforge.lua"     = "$root\bluforge.lua"
    "bluforge/blu.lua"          = "$root\blu.lua"
    "bluforge/ui.lua"           = "$root\ui.lua"
    "bluforge/data/bludata.lua" = "$root\data\bludata.lua"
    "bluforge/data/spells.json" = "$root\data\spells.json"
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$zip = Join-Path (Resolve-Path $OutDir) "bluforge-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($name in $map.Keys) {
    $entry = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $os = $entry.Open()
    $bytes = [System.IO.File]::ReadAllBytes($map[$name])
    $os.Write($bytes, 0, $bytes.Length)
    $os.Dispose()
}
$archive.Dispose(); $fs.Dispose()

Write-Host "Built $zip"
[System.IO.Compression.ZipFile]::OpenRead($zip).Entries | ForEach-Object { "  $($_.FullName)" }
