$exe = "C:/Users/Administrator/Desktop/pi-web-desktop-app/dist/win-unpacked/Pi Web.exe"
$out = "C:/Users/Administrator/Desktop/pi-web-src/unpacked-test.log"
$err = "C:/Users/Administrator/Desktop/pi-web-src/unpacked-test-err.log"
Remove-Item $out, $err -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $exe -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-src/unpacked.pid" -Value $p.Id
Write-Output ("Unpacked PID=" + $p.Id)
