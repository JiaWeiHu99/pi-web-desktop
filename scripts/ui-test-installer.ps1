$setup = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-setup.exe"
$p = Start-Process -FilePath $setup -PassThru
Write-Output ("setup PID=" + $p.Id)
Start-Sleep -Seconds 8
$win = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object ProcessName, MainWindowTitle
$win | Format-Table -AutoSize | Out-String -Width 200
# 找到安装器窗口进程并结束
Get-Process | Where-Object { $_.MainWindowTitle -match 'Pi Web|Setup|Install' } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Write-Output ("closed: " + $_.ProcessName) }
Start-Sleep -Seconds 2
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Write-Output "closed stub" }
