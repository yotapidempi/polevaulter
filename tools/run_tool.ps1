# Runs tools/test_ride.gd for one scenario with a timeout and prints its log.
# Usage: run_tool.ps1 <scenario> [timeout seconds]
param([string]$Scen = "vault", [int]$Seconds = 60)
$project = Split-Path $PSScriptRoot -Parent
$out = Join-Path $project "test_out\$Scen"
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "log.txt"
$env:SCEN = $Scen
$p = Start-Process -FilePath "D:\Jesse\code\Godot\Godot_v4.7.2-stable_win64_console.exe" `
	-ArgumentList "--path", $project, "--resolution", "960x540", "--script", "res://tools/test_ride.gd" `
	-RedirectStandardOutput $log -RedirectStandardError (Join-Path $out "err.txt") -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($Seconds * 1000)) {
	Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*test_ride.gd*" -and $_.Name -like "Godot*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
	"TIMED OUT"
}
Get-Content $log | Where-Object { $_ -notmatch "^Godot Engine|^OpenGL|^$" }
Get-Content (Join-Path $out "err.txt") | Where-Object { $_ -match "ERROR|Parse|error|WARNING" } | Select-Object -First 12
