param(
  [string]$Destination = "$env:USERPROFILE\.codex\skills",
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptDir "su-pinterest-inspiration"

if (-not (Test-Path -LiteralPath $source)) {
  throw "Skill source not found: $source"
}

$targetRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $Destination)).Path)
$target = Join-Path $targetRoot "su-pinterest-inspiration"

if ($Clean -and (Test-Path -LiteralPath $target)) {
  $backup = "$target.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Move-Item -LiteralPath $target -Destination $backup
  Write-Host "Backed up existing skill to $backup"
}

Copy-Item -LiteralPath $source -Destination $targetRoot -Recurse -Force
Write-Host "Installed/updated skill at $target"
Write-Host 'Invoke it in Codex with: Use $su-pinterest-inspiration ...'
