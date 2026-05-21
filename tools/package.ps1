param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$pluginFile = Join-Path $Root 'AI+SU.rb'
$distDir = Join-Path $Root 'dist'
$stageDir = Join-Path $distDir 'stage'
$packageFile = Join-Path $distDir 'AI+SU.rbz'
$zipFile = Join-Path $distDir 'AI+SU.zip'

if (-not (Test-Path -LiteralPath $pluginFile)) {
  throw "Missing plugin file: $pluginFile"
}

if (Test-Path -LiteralPath $stageDir) {
  Remove-Item -LiteralPath $stageDir -Recurse -Force
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
Copy-Item -LiteralPath $pluginFile -Destination (Join-Path $stageDir 'AI+SU.rb') -Force

if (Test-Path -LiteralPath $packageFile) {
  Remove-Item -LiteralPath $packageFile -Force
}
if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipFile -Force
Move-Item -LiteralPath $zipFile -Destination $packageFile -Force
Remove-Item -LiteralPath $stageDir -Recurse -Force

Write-Host "Created $packageFile"
