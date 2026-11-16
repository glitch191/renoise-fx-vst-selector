<#
.SYNOPSIS
  Copies the tool folder into Renoise's user tools folder for development.

.DESCRIPTION
  Installs tool/ as <Renoise configuration>/<version>/Scripts/Tools/<tool id>.xrnx,
  where <tool id> is read from manifest.xml. Only that one folder is written:
  no other tool is touched. Your data (notes, ratings, edits) lives outside
  that folder and is kept.

  After running it, use "Tools > Reload All Tools" in Renoise, or restart
  Renoise.

.PARAMETER RenoiseVersion
  Name of the versioned configuration folder, for example "V3.5.4".
  Default: the most recent one found.

.EXAMPLE
  ./scripts/install-dev.ps1
  ./scripts/install-dev.ps1 -RenoiseVersion V3.5.4
#>
param(
  [string]$RenoiseVersion = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$toolDir = Join-Path $root "tool"
$manifest = Get-Content (Join-Path $toolDir "manifest.xml") -Raw
if ($manifest -notmatch '<Id>\s*([^<\s]+)\s*</Id>') {
  throw "manifest.xml has no <Id> element"
}
$toolId = $Matches[1]

$configRoot = Join-Path $env:APPDATA "Renoise"
if (-not (Test-Path $configRoot)) {
  throw "Renoise configuration folder not found: $configRoot. Start Renoise once, then run this script again."
}

if (-not $RenoiseVersion) {
  $latest = Get-ChildItem $configRoot -Directory -Filter "V*" |
    Sort-Object { [version]($_.Name -replace '^V', '' -replace '[^0-9.].*$', '') } |
    Select-Object -Last 1
  if (-not $latest) {
    throw "No versioned Renoise folder found in $configRoot"
  }
  $RenoiseVersion = $latest.Name
}

$toolsDir = Join-Path $configRoot "$RenoiseVersion\Scripts\Tools"
if (-not (Test-Path $toolsDir)) {
  throw "Tools folder not found: $toolsDir"
}

$target = Join-Path $toolsDir "$toolId.xrnx"
if (Test-Path $target) {
  Remove-Item $target -Recurse -Force
}
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item -Path (Join-Path $toolDir "*") -Destination $target -Recurse -Force

Write-Host "Installed $toolId for Renoise $RenoiseVersion"
Write-Host "In Renoise: Tools > Reload All Tools (or restart Renoise)."
