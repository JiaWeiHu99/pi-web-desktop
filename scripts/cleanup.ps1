# 全量清理: Pi Web 相关残留
Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 失效快捷方式(指向已不存在的目录)
Remove-Item "C:/Users/Administrator/Desktop/Pi Web.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "C:/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Pi Web.lnk" -Force -ErrorAction SilentlyContinue

# 测试残留目录
Remove-Item "C:/pi-web-clean-test" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:/Users/Administrator/Desktop/pi-web-test-install" -Recurse -Force -ErrorAction SilentlyContinue

# portable 解压缓存(确保下次重新解压)
Remove-Item "C:/Users/Administrator/AppData/Local/Temp/pi-web-desktop" -Recurse -Force -ErrorAction SilentlyContinue

# 安装器残留临时目录(仅 ns 开头的)
Get-ChildItem "C:/Users/Administrator/AppData/Local/Temp" -Directory -Filter "ns*.tmp" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "cleanup done"
Write-Output ("remaining Pi Web procs: " + @(Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue).Count)
