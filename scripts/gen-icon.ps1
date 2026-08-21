$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = "C:/Users/Administrator/Desktop/pi-web-desktop-app/build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Draw-Icon($size, $outPath) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $s = $size / 256.0

  # rounded rect background
  $rect = New-Object System.Drawing.RectangleF((8 * $s), (8 * $s), (240 * $s), (240 * $s))
  $radius = 44 * $s
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $radius * 2
  $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
  $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
  $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
  $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
  $path.CloseFigure()

  $c1 = [System.Drawing.Color]::FromArgb(255, 15, 23, 42)
  $c2 = [System.Drawing.Color]::FromArgb(255, 30, 41, 59)
  $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, 45.0)
  Write-Output ("rect type: " + $rect.GetType().Name + " size=" + $size)
  $g.FillPath($brush, $path)

  # border
  $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 51, 65, 85), [Math]::Max(2, 2 * $s))
  $g.DrawPath($pen, $path)

  # terminal prompt chevron: two green lines + underline cursor
  $green = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 74, 222, 128), [Math]::Max(4, 26 * $s))
  $green.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $green.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $green.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

  $g.DrawLine($green, 56 * $s, 84 * $s, 134 * $s, 128 * $s)
  $g.DrawLine($green, 134 * $s, 128 * $s, 56 * $s, 172 * $s)

  # underline cursor
  $g.DrawLine($green, 66 * $s, 196 * $s, 200 * $s, 196 * $s)

  $g.Dispose()
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output ("generated {0} ({1} bytes)" -f $outPath, (Get-Item $outPath).Length)
}

Draw-Icon 256 "$outDir/icon.png"
Draw-Icon 256 "$outDir/icon-256.png"
Draw-Icon 64  "$outDir/icon-64.png"
Draw-Icon 48  "$outDir/icon-48.png"
Draw-Icon 32  "$outDir/icon-32.png"
Draw-Icon 16  "$outDir/icon-16.png"
