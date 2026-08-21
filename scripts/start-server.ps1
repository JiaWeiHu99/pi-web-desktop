$log = "C:/Users/Administrator/Desktop/pi-web-src/server-test.log"
$err = "C:/Users/Administrator/Desktop/pi-web-src/server-test-err.log"
Remove-Item $log, $err -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "F:\Program Files\nodejs\node.exe" `
  -ArgumentList 'C:/Users/Administrator/Desktop/pi-web-src/package/bin/pi-web.js --no-open' `
  -WorkingDirectory "C:/Users/Administrator/Desktop/pi-web-src/package" `
  -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -WindowStyle Hidden
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-src/server.pid" -Value $p.Id
Write-Output ("PID=" + $p.Id)
