Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$exe = "C:/Users/Administrator/Desktop/pi-web-desktop/dist/win-unpacked/Pi Web.exe"
$outDir = "C:/Users/Administrator/Desktop/pi-web-desktop/docs"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = "$outDir/screenshot-local.png"

$p = Start-Process -FilePath $exe -PassThru
Set-Content -Path "C:/Users/Administrator/Desktop/pi-web-src-screenshot.pid" -Value $p.Id

# 等待窗口出现
$win = $null
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 2
  $proc = Get-Process -Name "Pi Web" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($proc) { $win = $proc; break }
}
if (-not $win) { Write-Output "NO WINDOW"; exit 1 }

# 再等页面加载
Start-Sleep -Seconds 6

# 用 Win32 获取窗口位置
Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public class Win32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

$handle = $win.MainWindowHandle
[Win32]::SetForegroundWindow($handle) | Out-Null
Start-Sleep -Seconds 1
$rect = New-Object RECT
[Win32]::GetWindowRect($handle, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
Write-Output ("window: ${w}x${h} at ($($rect.Left),$($rect.Top))")

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output ("saved: $outPath")
