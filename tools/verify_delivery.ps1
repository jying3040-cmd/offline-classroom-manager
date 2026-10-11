param(
  [string]$DeliveryRoot = 'C:\Users\7\Desktop\小学班级管理系统\交付'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceRoot = Split-Path $PSScriptRoot -Parent
$current = Join-Path $DeliveryRoot 'v4.0\班级管理系统'
$rows = @()
foreach ($relative in @('v4.0\班级管理系统_v4.0.zip', '历史\v1.0\班级管理系统_v1.0.zip', '历史\v2.0\班级管理系统_v2.0.zip', '历史\v3.0\班级管理系统_v3.0.zip')) {
  $path = Join-Path $DeliveryRoot $relative
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  $count = 0
  try {
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName.EndsWith('/')) { continue }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $digest = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
      finally { $stream.Dispose(); $sha.Dispose() }
      $count++
      if ($relative.StartsWith('v4.0\')) {
        $name = $entry.FullName.Replace('/', '\')
        $prefix = '班级管理系统\'
        if ($name.StartsWith($prefix)) { $name = $name.Substring($prefix.Length) }
        $target = [IO.Path]::GetFullPath((Join-Path $current $name))
        if (-not $target.StartsWith($current + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe zip path: $name" }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Missing unpacked file: $name" }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $digest) { throw "Zip/directory mismatch: $name" }
      }
    }
    if ($relative.StartsWith('v4.0\')) {
      if (@(Get-ChildItem -LiteralPath $current -Recurse -File).Count -ne $count) { throw 'Unexpected extra files in current delivery' }
    }
  } finally { $zip.Dispose() }
  $rows += [PSCustomObject]@{ Path = $relative; Files = $count; SHA256 = (Get-FileHash -LiteralPath $path).Hash }
}
$seedSource = Join-Path $sourceRoot 'assets\tts_seed'
$seedTarget = Join-Path $current 'data\flutter_assets\assets\tts_seed'
$seeds = @(Get-ChildItem -LiteralPath $seedSource -Recurse -File -Filter '*.wav')
if ($seeds.Count -ne 213 -or @(Get-ChildItem -LiteralPath $seedTarget -Recurse -File -Filter '*.wav').Count -ne 213) { throw 'Expected 213 offline WAV resources' }
foreach ($seed in $seeds) {
  $target = Join-Path $seedTarget $seed.FullName.Substring($seedSource.Length + 1)
  if ((Get-FileHash -LiteralPath $seed.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Seed mismatch: $target" }
}
foreach ($name in @('classroom_manager.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data\app.so', 'data\icudtl.dat', '使用说明.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $current $name) -PathType Leaf)) { throw "Missing runtime file: $name" }
}
$rows | ConvertTo-Json
Write-Output 'PASS: all archives readable; v4 zip matches directory; 213 WAV resources match source; runtime files present.'
