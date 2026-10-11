param(
  [string]$DeliveryRoot = 'C:\Users\7\Desktop\小学班级管理系统\交付'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceRoot = Split-Path $PSScriptRoot -Parent
$versions = @('v1.0', 'v2.0', 'v3.0', 'v4.0')
$rootEntries = @(Get-ChildItem -LiteralPath $DeliveryRoot -Force)
if (($rootEntries.Name | Sort-Object) -join ',' -ne ($versions -join ',')) { throw 'Delivery root must contain only version directories' }
foreach ($version in $versions) {
  $items = @(Get-ChildItem -LiteralPath (Join-Path $DeliveryRoot $version) -Force)
  if ($items.Count -ne 1 -or $items[0].PSIsContainer -or $items[0].Name -ne "班级管理系统_$version.zip") { throw "Version directory must contain only its ZIP: $version" }
}
$seedSource = Join-Path $sourceRoot 'assets\tts_seed'
$seeds = @(Get-ChildItem -LiteralPath $seedSource -Recurse -File -Filter '*.wav')
if ($seeds.Count -ne 213) { throw 'Expected 213 source WAV resources' }
$seedHashes = @{}
foreach ($seed in $seeds) { $seedHashes[$seed.FullName.Substring($seedSource.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $seed.FullName).Hash }
$expectedHashes = @{
  'v1.0' = '5DD24A2CEA3CD99BD9365E7CF303B4609F0ACCEE947ECBA2BF29979C1B41F60F'
  'v2.0' = '43765AF09E26237C73951BC9CF4D78B359FE957BA0A5414C1BEDF951D6597EA3'
  'v3.0' = '182BF8D8927DCD64463D63C7DD7F7EADA9D0647E685A908FC0529F01069736EB'
  'v4.0' = '4DE0FF1250A9B27A042A346D88E5F167CF7244EECD041C0FD09A710113BAC6DC'
}
$rows = @()
foreach ($relative in @('v4.0\班级管理系统_v4.0.zip', 'v1.0\班级管理系统_v1.0.zip', 'v2.0\班级管理系统_v2.0.zip', 'v3.0\班级管理系统_v3.0.zip')) {
  $path = Join-Path $DeliveryRoot $relative
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  $count = 0
  $seedCount = 0
  $currentNames = @{}
  try {
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName.EndsWith('/')) { continue }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $digest = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
      finally { $stream.Dispose(); $sha.Dispose() }
      $count++
      if ($relative.StartsWith('v4.0\')) {
        $name = $entry.FullName.Replace('\', '/')
        $prefix = '班级管理系统/'
        if ($name.StartsWith($prefix)) { $name = $name.Substring($prefix.Length) }
        if ($name.StartsWith('/') -or $name.Contains(':') -or ($name.Split('/') -contains '..')) { throw "Unsafe zip path: $name" }
        if ($currentNames.ContainsKey($name)) { throw "Duplicate ZIP entry: $name" }
        $currentNames[$name] = $true
        $seedPrefix = 'data/flutter_assets/assets/tts_seed/'
        if ($name.StartsWith($seedPrefix) -and $name.EndsWith('.wav')) {
          $seedName = $name.Substring($seedPrefix.Length)
          if (-not $seedHashes.ContainsKey($seedName) -or $seedHashes[$seedName] -ne $digest) { throw "Seed mismatch: $seedName" }
          $seedCount++
        }
      }
    }
    if ($relative.StartsWith('v4.0\')) {
      if ($seedCount -ne 213) { throw 'Expected 213 offline WAV resources inside v4 ZIP' }
      foreach ($name in @('classroom_manager.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat', '使用说明.txt')) {
        if (-not $currentNames.ContainsKey($name)) { throw "Missing runtime file in ZIP: $name" }
      }
    }
  } finally { $zip.Dispose() }
  $archiveHash = (Get-FileHash -LiteralPath $path).Hash
  $version = $relative.Split('\')[0]
  if ($archiveHash -ne $expectedHashes[$version]) { throw "Archive hash changed: $version" }
  $rows += [PSCustomObject]@{ Path = $relative; Files = $count; SHA256 = $archiveHash }
}
$rows | ConvertTo-Json
Write-Output 'PASS: version directories contain only ZIPs; archive hashes unchanged; 213 WAV resources match source; runtime files and instructions present inside v4 ZIP.'
