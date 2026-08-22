# 验证 zip 绿色版: 解压后应秒开
$zip = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-win.zip"
$out = "C:/Users/Administrator/Desktop/zip-test"
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out | Out-Null
Write-Output "== extracting =="
$sw1 = [System.Diagnostics.Stopwatch]::StartNew()
Expand-Archive -Path $zip -DestinationPath $out -Force
$sw1.Stop()
Write-Output ("extract took " + [Math]::Round($sw1.Elapsed.TotalSeconds, 1) + "s")
$app = Get-ChildItem $out -Filter "Pi Web.exe" -Recurse | Select-Object -First 1
Write-Output ("app: " + $app.FullName)
if (-not $app) { exit 1 }
Write-Output "== launch =="
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $app.FullName -PassThru
$ok = $false
for ($i = 1; $i -le 25; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:30141/" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -eq 200) { $ok = $true; break }
  } catch {}
}
$sw2.Stop()
if ($ok) { Write-Output ("zip version ready in " + [Math]::Round($sw2.Elapsed.TotalSeconds, 1) + "s") } else { Write-Output "NOT ready in 25s" }
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "== done =="
