$procs = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'npm|pi-web-src|next|node.exe' -or $_.Name -in @('cmd.exe','npm.exe','npm.cmd')
} | Select-Object ProcessId, Name, @{N='Cmd';E={ if ($_.CommandLine) { $_.CommandLine.Substring(0, [Math]::Min(180, $_.CommandLine.Length)) } else { '' } }}
$procs | Format-Table -AutoSize | Out-String -Width 260
