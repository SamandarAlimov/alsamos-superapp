param(
  [switch]$SkipFlutterClean
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsBuild = Join-Path $repoRoot 'build\windows\x64'

$targets = @(
  'mpv-dev-x86_64-20230924-git-652a1dd.7z',
  'ANGLE.7z',
  'libmpv',
  'ANGLE',
  'plugins\media_kit_libs_windows_video'
)

foreach ($target in $targets) {
  $path = Join-Path $windowsBuild $target
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
    Write-Host "Removed $path"
  }
}

if (-not $SkipFlutterClean) {
  Push-Location $repoRoot
  try {
    & 'D:\web\flutter\flutter\bin\flutter.bat' clean
    & 'D:\web\flutter\flutter\bin\flutter.bat' pub get
  } finally {
    Pop-Location
  }
}
