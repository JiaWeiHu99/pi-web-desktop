$exe = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-portable.exe"
$run = $args[0]
if (-not $run) { $run = 1 }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $exe -PassThru
$ok = $false
for ($i = 1; $i -le 30; $i++) {
  Start-Sleep -Seconds 2
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:30141/" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -eq 200) { $ok = $true; break }
  } catch {}
}
$sw.Stop()
if ($ok) {
  Write-Output ("launch #$run ready in " + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + "s")
} else {
  Write-Output ("launch #$run NOT ready in 60s")
}
