@echo off
setlocal
rem ---------------------------------------------------------------------------
rem  matrixart.cmd - digital 0/1 rain that gradually assembles into "ART".
rem  No build step: just double-click, or run it from a terminal.
rem  Press any key (or Ctrl-C) to quit.
rem
rem  Needs Windows 10/11 (PowerShell is built in). Colours render best in
rem  Windows Terminal; the script also tries to enable colour in the classic
rem  console window. The batch lines here just launch PowerShell, which reads
rem  this same file and runs the script section below the marker.
rem ---------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText('%~f0'); $m=[char]35+'==PSCODE=='; Invoke-Expression $f.Substring($f.LastIndexOf($m))"
exit /b

#==PSCODE==#
# ===========================  PowerShell section  ==========================

$ESC = [char]27

# Best-effort: enable ANSI colour in the classic console (Windows Terminal is
# fine already). Harmless if it fails.
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
  $hOut = [VT]::GetStdHandle(-11)
  $mode = 0
  [void][VT]::GetConsoleMode($hOut, [ref]$mode)
  [void][VT]::SetConsoleMode($hOut, $mode -bor 0x0004)
} catch { }

# ---- phase timing (seconds); the whole thing loops -----------------------
$T_RAIN = 4.0       # pure rain
$T_ASM  = 9.0       # digits assembling into letters
$T_HOLD = 7.0       # word held, rain dimmed
$CYCLE  = $T_RAIN + $T_ASM + $T_HOLD

$rng = New-Object System.Random

# ---- terminal size (with fallbacks) --------------------------------------
$W = [Console]::WindowWidth
$H = [Console]::WindowHeight - 1
if ($W -lt 20) { $W = 100 }
if ($H -lt 10) { $H = 40 }

# ---- rain state ----------------------------------------------------------
$rg     = New-Object char[]   ($W * $H)   # glyph at each cell
$headY  = New-Object double[] $W          # head row per column (may be < 0)
$speed  = New-Object double[] $W          # fall speed (rows/sec)
$trail  = New-Object double[] $W          # trail length (rows)
for ($i = 0; $i -lt $rg.Length; $i++) { $rg[$i] = [char]'0' }
for ($x = 0; $x -lt $W; $x++) {
  $headY[$x] = -($rng.NextDouble() * 2.0 * $H)
  $speed[$x] = 8.0 + $rng.NextDouble() * 22.0
  $trail[$x] = 8.0 + $rng.Next(0, 13)
}

# ---- letters (the cells that spell ART) ----------------------------------
$FONT_A = @("01110","10001","10001","11111","10001","10001","10001")
$FONT_R = @("11110","10001","10001","11110","10100","10010","10001")
$FONT_T = @("11111","00100","00100","00100","00100","00100","00100")
$fonts  = @($FONT_A, $FONT_R, $FONT_T)
$colOff = @(0, 6, 12)
$fontCols = 17; $fontRows = 7

$blockH = [Math]::Min([int](0.55 * $H / $fontRows), [int](0.70 * $W / ($fontCols * 2)))
if ($blockH -lt 1) { $blockH = 1 }
$blockW = $blockH * 2; if ($blockW -lt 2) { $blockW = 2 }
$wordW = $fontCols * $blockW; $wordH = $fontRows * $blockH
$ox = [int](($W - $wordW) / 2); $oy = [int](($H - $wordH) / 2)

$isL     = New-Object bool[]   ($W * $H)   # is this cell part of ART?
$lglyph  = New-Object char[]   ($W * $H)   # fixed 0/1 once locked
$lreveal = New-Object double[] ($W * $H)   # when it locks (this cycle)
$lcells  = New-Object System.Collections.Generic.List[int]

for ($li = 0; $li -lt 3; $li++) {
  for ($fr = 0; $fr -lt $fontRows; $fr++) {
    $rowStr = $fonts[$li][$fr]
    for ($fc = 0; $fc -lt 5; $fc++) {
      if ($rowStr[$fc] -eq '1') {
        for ($by = 0; $by -lt $blockH; $by++) {
          for ($bx = 0; $bx -lt $blockW; $bx++) {
            $cx = $ox + ($colOff[$li] + $fc) * $blockW + $bx
            $cy = $oy + $fr * $blockH + $by
            if ($cx -ge 0 -and $cx -lt $W -and $cy -ge 0 -and $cy -lt $H) {
              $idx = $cy * $W + $cx
              $isL[$idx]    = $true
              $lglyph[$idx] = if ($rng.Next(2) -eq 1) { [char]'1' } else { [char]'0' }
              $lcells.Add($idx)
            }
          }
        }
      }
    }
  }
}

function Regen-Reveal {
  foreach ($idx in $lcells) {
    $lreveal[$idx] = $T_RAIN + $rng.NextDouble() * $T_ASM
  }
}
Regen-Reveal

# ---- advance the rain ----------------------------------------------------
function Update([double]$dt) {
  for ($x = 0; $x -lt $W; $x++) {
    $prev = $headY[$x]
    $headY[$x] += $speed[$x] * $dt
    $r0 = [int][Math]::Floor($prev) + 1
    $r1 = [int][Math]::Floor($headY[$x])
    for ($row = $r0; $row -le $r1; $row++) {
      if ($row -ge 0 -and $row -lt $H) {
        $rg[$row * $W + $x] = if ($rng.Next(2) -eq 1) { [char]'1' } else { [char]'0' }
      }
    }
    if ($headY[$x] - $trail[$x] -gt $H) {          # off-screen -> respawn with a gap
      $headY[$x] = -($rng.Next(0, $H) + $rng.Next(0, $H))
      $speed[$x] = 8.0 + $rng.NextDouble() * 22.0
      $trail[$x] = 8.0 + $rng.Next(0, 13)
    }
  }
}

# ---- draw one frame ------------------------------------------------------
function Render([double]$tl, [double]$t) {
  $sb = New-Object System.Text.StringBuilder (($W + 12) * $H)
  [void]$sb.Append("$ESC[H")

  if ($tl -lt $T_RAIN) { $dim = 1.0 }
  elseif ($tl -lt $T_RAIN + $T_ASM) { $dim = 1.0 - 0.5 * (($tl - $T_RAIN) / $T_ASM) }
  else { $dim = 0.45 }

  $tick = [int]($t * 3)
  $cur = -999
  for ($y = 0; $y -lt $H; $y++) {
    $base = $y * $W
    for ($x = 0; $x -lt $W; $x++) {
      $idx = $base + $x
      $code = -1; $glyph = ' '

      if ($isL[$idx] -and $tl -ge $lreveal[$idx]) {
        $g = $lglyph[$idx]
        if (((($idx * 7) + ($tick * 131)) % 13) -eq 0) {
          $g = if ($g -eq [char]'0') { [char]'1' } else { [char]'0' }
        }
        $glyph = $g; $code = 231
      } else {
        $dy = $headY[$x] - $y
        $L = $trail[$x]
        if ($dy -ge 0 -and $dy -lt $L) {
          $b = (1.0 - $dy / $L) * $dim
          if     ($b -gt 0.80) { $code = 46 }
          elseif ($b -gt 0.55) { $code = 40 }
          elseif ($b -gt 0.35) { $code = 34 }
          elseif ($b -gt 0.18) { $code = 28 }
          elseif ($b -gt 0.05) { $code = 22 }
          if ($code -gt 0) { $glyph = $rg[$idx] }
        }
      }

      if ($code -lt 0) {
        if ($cur -ne -1) { [void]$sb.Append("$ESC[0m"); $cur = -1 }
        [void]$sb.Append(' ')
      } else {
        if ($code -ne $cur) { [void]$sb.Append("$ESC[38;5;"); [void]$sb.Append($code); [void]$sb.Append('m'); $cur = $code }
        [void]$sb.Append($glyph)
      }
    }
    [void]$sb.Append("$ESC[0m"); $cur = -1
    if ($y -lt $H - 1) { [void]$sb.Append("`n") }
  }
  [Console]::Out.Write($sb.ToString())
  [Console]::Out.Write("$ESC[$($H + 1);1H$ESC[38;5;46mmatrix -> ART   press any key to quit$ESC[0m")
}

# ---- main loop -----------------------------------------------------------
[Console]::TreatControlCAsInput = $true
[Console]::CursorVisible = $false
[Console]::Write("$ESC[2J")
$start = Get-Date
$prev  = $start
$lastTl = 0.0
try {
  while ($true) {
    if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }

    $now = Get-Date
    $t  = ($now - $start).TotalSeconds
    $dt = ($now - $prev).TotalSeconds
    $prev = $now
    if ($dt -gt 0.1) { $dt = 0.1 }

    $tl = $t % $CYCLE
    if ($tl -lt $lastTl) { Regen-Reveal }   # new cycle -> reshuffle assembly
    $lastTl = $tl

    Update $dt
    Render $tl $t
    Start-Sleep -Milliseconds 35
  }
}
finally {
  [Console]::Write("$ESC[0m$ESC[2J$ESC[H")
  [Console]::CursorVisible = $true
  [Console]::TreatControlCAsInput = $false
}
