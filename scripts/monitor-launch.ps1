$exe = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-portable.exe"
$p = Start-Process -FilePath $exe -PassThru
Write-Output ("启动 PID=" + $p.Id)
# 监控: 进程 / 窗口 / 端口
for ($i = 1; $i -le 20; $i++) {
  Start-Sleep -Seconds 15
  $sec = $i * 15
  $procs = Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue
  $n = @($procs).Count
  $win = $procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  $port = ""
  try { $r = Invoke-WebRequest -Uri "http://127.0.0.1:30141/" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop; $port = "HTTP " + $r.StatusCode } catch { $port = "端口未开" }
  $title = if ($win) { $win.MainWindowTitle } else { "-" }
  Write-Output ("[$($sec)s] 进程数=$n 窗口='$title' $port")
  if ($n -gt 0 -and $port -eq "HTTP 200") { Write-Output "=== 启动成功 ==="; break }
}
