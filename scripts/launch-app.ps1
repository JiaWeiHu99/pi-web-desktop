$appDir = "C:/Users/Administrator/Desktop/pi-web-desktop-app"
$out = "C:/Users/Administrator/Desktop/pi-web-src/app-test.log"
$err = "C:/Users/Administrator/Desktop/pi-web-src/app-test-err.log"
Remove-Item $out, $err -ErrorAction SilentlyContinue
$electron = "$appDir/node_modules/electron/dist/electron.exe"
$p = Start-Process -FilePath $electron `
  -ArgumentList $appDir `
  -WorkingDirectory $appDir `
  -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-src/app.pid" -Value $p.Id
Write-Output ("Electron PID=" + $p.Id)
