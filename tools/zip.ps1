# Builds a release zip by hand, for an upload on CurseForge without GitHub.
# The zip holds only the addon folder: TouchOfTheGrave/TouchOfTheGrave.toc and
# TouchOfTheGrave/TouchOfTheGrave.lua. The version comes from the TOC.
#
# Usage (from any folder):
#   powershell -ExecutionPolicy Bypass -File tools\zip.ps1
# Output: dist\TouchOfTheGrave-<version>.zip

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root "TouchOfTheGrave"
$toc = Join-Path $addon "TouchOfTheGrave.toc"

$versionLine = Select-String -Path $toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw "No '## Version:' line in $toc" }
$version = $versionLine.Matches[0].Groups[1].Value

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "TouchOfTheGrave-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

# ZipArchive in place of Compress-Archive: Windows PowerShell 5.1 writes
# backslashes in the entry names, and the zip must use forward slashes.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $addon -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($addon.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "TouchOfTheGrave/$relative") | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Output "Wrote $zipPath"
