$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$rect = New-Object System.Drawing.RectangleF(8, 8, 240, 240)
$c1 = [System.Drawing.Color]::FromArgb(255, 15, 23, 42)
$c2 = [System.Drawing.Color]::FromArgb(255, 30, 41, 59)
$brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, 45.0)
Write-Output ("brush OK: " + $brush.GetType().Name)
