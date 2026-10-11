# Generate bundled TTS audio for the textbook word list.
# Input : tools/tts_seed_words.txt  (lines: g01|w01|<word in Chinese>)
# Output: assets/tts_seed/<group>/<file>.wav  (16kHz/16bit/mono, zh-CN voice)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_tts_seed.ps1
param(
  [string]$listPath = "$PSScriptRoot\tts_seed_words.txt",
  [string]$root = "$PSScriptRoot\..\assets\tts_seed"
)
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($root)
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $zh = $synth.GetInstalledVoices() |
    Where-Object { $_.VoiceInfo.Culture.Name -like 'zh*' } |
    Sort-Object { if ($_.VoiceInfo.Culture.Name -eq 'zh-CN') { 0 } else { 1 } } |
    Select-Object -First 1
  if ($zh) {
    Write-Output ("voice: " + $zh.VoiceInfo.Name)
    $synth.SelectVoice($zh.VoiceInfo.Name)
  } else {
    Write-Output 'voice: (default, no zh voice found)'
  }
  # Slightly slower than normal, same as runtime TtsService.
  $synth.Rate = -1
  # 16kHz/16bit/mono: plays fine with MFPlay, about half the default size.
  $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo -ArgumentList 16000, Sixteen, Mono
  $count = 0
  Get-Content -Path $listPath -Encoding UTF8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    $parts = $_.Split('|')
    if ($parts.Count -lt 3) { return }
    $dir = Join-Path $root $parts[0]
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $synth.SetOutputToWaveFile((Join-Path $dir ($parts[1] + '.wav')), $format)
    $synth.Speak($parts[2])
    $count++
  }
  Write-Output ("generated: " + $count)
} finally {
  $synth.Dispose()
}
