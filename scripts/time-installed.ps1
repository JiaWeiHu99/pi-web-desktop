$installed = "C:/Users/Administrator/Desktop/pi-web-test-install/Pi Web.exe"
Write-Output ("exists: " + (Test-Path $installed))
if (-not (Test-Path $installed)) { exit 1 }
# 清理可能残留的旧实例
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $installed -PassThru
$ok = $false
for ($i = 1; $i -le 25; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:30141/" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -eq 200) { $ok = $true; break }
  } catch {}
}
$sw.Stop()
if ($ok) {
  Write-Output ("installed app ready in " + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + "s")
} else {
  Write-Output "NOT ready in 25s"
}
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
