$port = 30141
$conns = netstat -ano | Select-String ":$port\s" | Select-String "LISTENING"
$pids = @()
foreach ($c in $conns) {
  $parts = $c.ToString().Trim() -split '\s+'
  $pid_ = $parts[-1]
  if ($pid_ -match '^\d+$' -and $pid_ -notin $pids) { $pids += $pid_ }
}
foreach ($p in $pids) {
  try { Stop-Process -Id ${p} -Force -ErrorAction Stop; Write-Output "killed ${p}" } catch { Write-Output "skip ${p}: $_" }
}
Start-Sleep -Milliseconds 500
$left = netstat -ano | Select-String ":$port\s" | Select-String "LISTENING"
if ($left) { Write-Output "STILL LISTENING" } else { Write-Output "port $port free" }
