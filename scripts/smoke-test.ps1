$log = "C:/Users/Administrator/Desktop/pi-web-desktop/scripts/smoke.log"
$err = "C:/Users/Administrator/Desktop/pi-web-desktop/scripts/smoke-err.log"
Remove-Item $log, $err -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "F:\Program Files\nodejs\node.exe" `
  -ArgumentList 'C:/Users/Administrator/Desktop/pi-web-desktop/server/bin/pi-web.js --no-open -p 13999' `
  -WorkingDirectory "C:/Users/Administrator/Desktop/pi-web-desktop/server" `
  -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -WindowStyle Hidden
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-desktop/scripts/smoke.pid" -Value $p.Id
Write-Output ("PID=" + $p.Id)
