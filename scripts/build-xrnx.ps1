<#
.SYNOPSIS
  Packages the tool folder into a Renoise tool file (.xrnx).

.DESCRIPTION
  A .xrnx file is a zip archive of the content of tool/, with manifest.xml
  at the root of the archive. The script also writes a SHA-256 checksum
  file next to it. Used both locally and by the release workflow.

.PARAMETER Tag
  Release tag, for example "v1.2.0". When given, the version (without a
  leading "v") is written into the packaged manifest.xml and used in the
  file name. The repository files are never modified.

.PARAMETER OutDir
  Output folder, relative to the repository root. Default: dist

.EXAMPLE
  ./scripts/build-xrnx.ps1
  ./scripts/build-xrnx.ps1 -Tag v1.0.0
#>
param(
  [string]$Tag = "",
  [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$project = Split-Path -Leaf $root
$toolDir = Join-Path $root "tool"
$manifestPath = Join-Path $toolDir "manifest.xml"

if (-not (Test-Path $manifestPath)) {
  throw "manifest.xml not found in $toolDir"
}

$label = if ($Tag) { $Tag } else { "dev" }
$outPath = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
$xrnx = Join-Path $outPath "$project-$label.xrnx"
if (Test-Path $xrnx) { Remove-Item $xrnx -Force }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$manifest = [System.IO.File]::ReadAllText($manifestPath, $utf8)
if ($Tag) {
  $version = $Tag -replace '^[vV]', ''
  if ($manifest -notmatch '<Version>[^<]*</Version>') {
    throw "manifest.xml has no <Version> element"
  }
  $manifest = $manifest -replace '<Version>[^<]*</Version>', "<Version>$version</Version>"
}

$zip = [System.IO.Compression.ZipFile]::Open($xrnx, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $files = Get-ChildItem -Path $toolDir -Recurse -File | Sort-Object FullName
  foreach ($file in $files) {
    # Zip entry names always use forward slashes, on every platform.
    $entryName = $file.FullName.Substring($toolDir.Length + 1) -replace '\\', '/'
    $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
      if ($entryName -eq "manifest.xml") {
        $bytes = $utf8.GetBytes($manifest)
      } else {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
      }
      $stream.Write($bytes, 0, $bytes.Length)
    } finally {
      $stream.Dispose()
    }
  }
} finally {
  $zip.Dispose()
}

# Check the archive: manifest.xml and main.lua must be at its root.
$check = [System.IO.Compression.ZipFile]::OpenRead($xrnx)
try {
  $names = $check.Entries | ForEach-Object { $_.FullName }
} finally {
  $check.Dispose()
}
foreach ($required in @("manifest.xml", "main.lua")) {
  if ($names -notcontains $required) {
    throw "The archive is invalid: $required is missing at its root"
  }
}

$hash = (Get-FileHash -Path $xrnx -Algorithm SHA256).Hash.ToLower()
$fileName = Split-Path -Leaf $xrnx
[System.IO.File]::WriteAllText("$xrnx.sha256", "$hash  $fileName`n", $utf8)

Write-Host "Built $OutDir/$fileName ($($names.Count) files)"
Write-Host "SHA-256: $hash"
