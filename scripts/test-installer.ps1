$setup = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/PiWeb-0.1.0-setup.exe"
$installDir = "C:/Users/Administrator/Desktop/pi-web-test-install"
Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "== silent install =="
$p = Start-Process -FilePath $setup -ArgumentList "/S", "/D=$installDir" -PassThru -Wait
Write-Output ("installer exit: " + $p.ExitCode)
Start-Sleep -Seconds 2
Get-ChildItem $installDir -ErrorAction SilentlyContinue | Select-Object -First 5 Name | Format-Table -AutoSize | Out-String
Write-Output ("installed size: " + [Math]::Round((Get-ChildItem $installDir -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 0) + " MB")
