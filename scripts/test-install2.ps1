# Clean controlled silent-install test
$setup = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-setup.exe"
$target = "C:/pi-web-clean-test"
# clean everything first
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:/Users/Administrator/Desktop/Pi Web.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "C:/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Pi Web.lnk" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Output "== install /S /D=$target =="
$p = Start-Process -FilePath $setup -ArgumentList "/S", "/D=$target" -PassThru -Wait
Write-Output ("exit: " + $p.ExitCode)
Start-Sleep -Seconds 8
Write-Output ("installed dir exists: " + (Test-Path "$target/Pi Web.exe"))
if (Test-Path $target) {
  Write-Output ("size: " + [Math]::Round((Get-ChildItem $target -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 0) + " MB")
}

# launch it
Write-Output "== launch installed app =="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p2 = Start-Process -FilePath "$target/Pi Web.exe" -PassThru
$ok = $false
for ($i = 1; $i -le 25; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:30141/" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -eq 200) { $ok = $true; break }
  } catch {}
}
$sw.Stop()
if ($ok) { Write-Output ("ready in " + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + "s") } else { Write-Output "NOT ready in 25s" }
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output "== done =="
