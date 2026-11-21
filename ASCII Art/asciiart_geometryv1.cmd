@echo off
setlocal
rem ---------------------------------------------------------------------------
rem  asciiart.cmd - animated geometric / fractal ASCII art, no build required.
rem
rem  Just double-click this file, or run it from a terminal:
rem      asciiart.cmd              cycles icosahedron -> seed -> sierpinski
rem      asciiart.cmd icosa        just the rotating icosahedron
rem      asciiart.cmd seed         just the Seed of Life
rem      asciiart.cmd sierpinski   just the Sierpinski triangle
rem  Press any key (or Ctrl-C) to quit.
rem
rem  Needs Windows 10/11 (PowerShell ships built in). Colours render best in
rem  Windows Terminal; the script also tries to enable colour in the classic
rem  console window.
rem
rem  How it works: the batch lines above bootstrap PowerShell, which reads this
rem  same file and runs only the portion after the #==PSCODE==# marker below.
rem ---------------------------------------------------------------------------
set "ASCIIART_SCENE=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText('%~f0'); $m=[char]35+'==PSCODE=='; Invoke-Expression $f.Substring($f.LastIndexOf($m))"
exit /b

#==PSCODE==#
# ===========================  PowerShell section  ==========================

$ESC = [char]27

# Try to turn on ANSI colour in the classic console (Windows Terminal already
# supports it). Harmless if it fails.
try {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VT {
  [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
  [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
  [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
}
'@
  $h = [VT]::GetStdHandle(-11)
  $mode = 0
  [void][VT]::GetConsoleMode($h, [ref]$mode)
  [void][VT]::SetConsoleMode($h, $mode -bor 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
} catch { }

# A rainbow of xterm-256 colour codes, walked once per second.
$PALETTE = 196,202,208,214,226,154,46,48,51,39,33,21,93,129,201,198
$PN = $PALETTE.Count

$scene = if ($env:ASCIIART_SCENE) { $env:ASCIIART_SCENE } else { 'all' }

# Terminal size (with sensible fallbacks).
$W = [Console]::WindowWidth
$H = [Console]::WindowHeight - 1
if ($W -lt 20) { $W = 100 }
if ($H -lt 10) { $H = 40 }

# Each cell is about twice as tall as wide; scale x to keep shapes proportional.
$ASPECT = 2.0

# Character + colour buffers.
$ch  = New-Object char[] ($W * $H)
$col = New-Object int[]  ($W * $H)

function Clear-Buf {
  for ($i = 0; $i -lt $ch.Length; $i++) { $ch[$i] = ' '; $col[$i] = -1 }
}

function Put([int]$x, [int]$y, [char]$c, [int]$slot) {
  if ($x -lt 0 -or $x -ge $W -or $y -lt 0 -or $y -ge $H) { return }
  $idx = $y * $W + $x
  $ch[$idx]  = $c
  $col[$idx] = ((($slot % $PN) + $PN) % $PN)
}

function Put-Text([int]$x, [int]$y, [string]$s, [int]$slot) {
  for ($i = 0; $i -lt $s.Length; $i++) { Put ($x + $i) $y $s[$i] $slot }
}

# Bresenham line.
function Draw-Line([int]$x0, [int]$y0, [int]$x1, [int]$y1, [char]$c, [int]$slot) {
  $dx = [Math]::Abs($x1 - $x0); $sx = if ($x0 -lt $x1) { 1 } else { -1 }
  $dy = -[Math]::Abs($y1 - $y0); $sy = if ($y0 -lt $y1) { 1 } else { -1 }
  $err = $dx + $dy
  while ($true) {
    Put $x0 $y0 $c $slot
    if ($x0 -eq $x1 -and $y0 -eq $y1) { break }
    $e2 = 2 * $err
    if ($e2 -ge $dy) { $err += $dy; $x0 += $sx }
    if ($e2 -le $dx) { $err += $dx; $y0 += $sy }
  }
}

# ---- Scene 1: rotating wireframe icosahedron -----------------------------
function Draw-Icosa([double]$t) {
  $P = (1 + [Math]::Sqrt(5)) / 2          # golden ratio
  $v = @(
    @(0, 1, $P),  @(0, 1, -$P),  @(0, -1, $P),  @(0, -1, -$P),
    @(1, $P, 0),  @(1, -$P, 0),  @(-1, $P, 0),  @(-1, -$P, 0),
    @($P, 0, 1),  @($P, 0, -1),  @(-$P, 0, 1),  @(-$P, 0, -1)
  )
  $ay = $t * 0.9; $ax = $t * 0.55
  $cy = [Math]::Cos($ay); $sy = [Math]::Sin($ay)
  $cx = [Math]::Cos($ax); $sx = [Math]::Sin($ax)
  $dist  = 6.0
  $scale = [Math]::Min($H * 0.5, $W * 0.5 / $ASPECT) / 2.4
  $ox = $W / 2.0; $oy = $H / 2.0

  $px = New-Object int[] 12
  $py = New-Object int[] 12
  for ($i = 0; $i -lt 12; $i++) {
    $x = $v[$i][0]; $y = $v[$i][1]; $z = $v[$i][2]
    $x1 = $x * $cy + $z * $sy;   $z1 = -$x * $sy + $z * $cy   # yaw
    $y1 = $y * $cx - $z1 * $sx;  $z2 = $y * $sx + $z1 * $cx   # pitch
    $k = $dist / ($dist - $z2)                               # perspective
    $px[$i] = [int][Math]::Round($ox + $x1 * $k * $scale * $ASPECT)
    $py[$i] = [int][Math]::Round($oy - $y1 * $k * $scale)
  }

  $off = [int]$t; $e = 0
  for ($i = 0; $i -lt 12; $i++) {
    for ($j = $i + 1; $j -lt 12; $j++) {
      $dx = $v[$i][0] - $v[$j][0]; $dy = $v[$i][1] - $v[$j][1]; $dz = $v[$i][2] - $v[$j][2]
      if ([Math]::Abs($dx * $dx + $dy * $dy + $dz * $dz - 4.0) -lt 0.1) {
        Draw-Line $px[$i] $py[$i] $px[$j] $py[$j] '*' ($e + $off)
        $e++
      }
    }
  }
  for ($i = 0; $i -lt 12; $i++) { Put $px[$i] $py[$i] '@' ($i + $off) }
}

# ---- Scene 2: Seed of Life -----------------------------------------------
function Draw-Circle([double]$ccx, [double]$ccy, [double]$R, [int]$slot) {
  for ($a = 0.0; $a -lt 6.2832; $a += 0.02) {
    $x = [int][Math]::Round($ccx + [Math]::Cos($a) * $R * $ASPECT)
    $y = [int][Math]::Round($ccy + [Math]::Sin($a) * $R)
    Put $x $y 'O' $slot
  }
}
function Draw-Seed([double]$t) {
  $ox = $W / 2.0; $oy = $H / 2.0
  $R  = [Math]::Min($H * 0.5 / 1.05, $W * 0.5 / $ASPECT / 1.05) / 3.0
  $off = [int]$t
  Draw-Circle $ox $oy $R (0 + $off)                    # centre
  for ($k = 0; $k -lt 6; $k++) {                       # six around it
    $a = $k * [Math]::PI / 3.0
    Draw-Circle ($ox + [Math]::Cos($a) * $R * $ASPECT) ($oy + [Math]::Sin($a) * $R) $R ($k + 1 + $off)
  }
}

# ---- Scene 3: Sierpinski triangle (Pascal's triangle mod 2) --------------
function Draw-Sierpinski([double]$t) {
  $rows = $H - 2
  if ($rows -gt [int]($W / 2)) { $rows = [int]($W / 2) }
  $off = [int]$t
  $startY = [int](($H - $rows) / 2)
  for ($r = 0; $r -lt $rows; $r++) {
    $level = if ($r -eq 0) { 0 } else { [int][Math]::Log($r, 2) + 1 }
    for ($c = 0; $c -le $r; $c++) {
      if (($r -band $c) -eq $c) {                       # C(r,c) is odd -> filled
        $x = [int]($W / 2) + (2 * $c - $r)
        $y = $startY + $r
        Put $x $y '/' ($level + $off)
      }
    }
  }
}

function Render {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("$ESC[H")
  $cur = -999
  for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
      $idx = $y * $W + $x
      $slot = $col[$idx]
      if ($slot -lt 0) {
        if ($cur -ne -1) { [void]$sb.Append("$ESC[0m"); $cur = -1 }
        [void]$sb.Append(' ')
      } else {
        $code = $PALETTE[$slot]
        if ($code -ne $cur) { [void]$sb.Append("$ESC[38;5;${code}m"); $cur = $code }
        [void]$sb.Append($ch[$idx])
      }
    }
    [void]$sb.Append("$ESC[0m"); $cur = -1
    if ($y -lt $H - 1) { [void]$sb.Append("`n") }
  }
  [Console]::Out.Write($sb.ToString())
}

# ---- main loop -----------------------------------------------------------
[Console]::TreatControlCAsInput = $true
[Console]::CursorVisible = $false
[Console]::Write("$ESC[2J")
$start = Get-Date
try {
  while ($true) {
    if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }

    $t = ((Get-Date) - $start).TotalSeconds
    $active = $scene
    if ($scene -eq 'all') {
      $active = @('icosa', 'seed', 'sierpinski')[[int]($t / 9.0) % 3]
    }

    Clear-Buf
    switch ($active) {
      'seed'       { Draw-Seed $t }
      'sierpinski' { Draw-Sierpinski $t }
      default      { Draw-Icosa $t }
    }
    Put-Text 1 ($H - 1) "[$active]  press any key to quit" ([int]$t)
    Render
    Start-Sleep -Milliseconds 50    # ~20 fps
  }
}
finally {
  [Console]::Write("$ESC[0m$ESC[2J$ESC[H")
  [Console]::CursorVisible = $true
  [Console]::TreatControlCAsInput = $false
}
