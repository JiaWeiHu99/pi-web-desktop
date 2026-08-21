$exe = "C:/Users/Administrator/Desktop/pi-web-desktop-app/dist/PiWeb-0.1.0-portable.exe"
$p = Start-Process -FilePath $exe -PassThru
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-src/portable.pid" -Value $p.Id
Write-Output ("Portable PID=" + $p.Id)
