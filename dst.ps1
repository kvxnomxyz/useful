#Requires -Version 5.1
# DiskStressTest.ps1 - kvxnom.xyz

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Draw-Header {
    param([string]$Drive, [string]$Label, [string]$Model, [long]$FileSizeMB)
    $line = "=" * 60
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  DISK STRESS TEST  --  kvxnom.xyz" -ForegroundColor Yellow
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  Drive  : " -NoNewline -ForegroundColor Gray
    Write-Host "$Drive  [$Label]" -ForegroundColor White
    Write-Host "  Model  : " -NoNewline -ForegroundColor Gray
    Write-Host $Model -ForegroundColor White
    Write-Host "  File   : " -NoNewline -ForegroundColor Gray
    Write-Host "$FileSizeMB MB" -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
}

function Format-Speed {
    param([double]$MBps)
    if ($MBps -ge 1000) {
        return ("{0:N2} GB/s" -f ($MBps / 1024))
    }
    return ("{0:N2} MB/s" -f $MBps)
}

function Get-SpeedBar {
    param([double]$MBps, [double]$MaxMBps, [int]$Width = 40)
    $fill = 0
    if ($MaxMBps -gt 0) {
        $fill = [int](($MBps / $MaxMBps) * $Width)
    }
    if ($fill -gt $Width) { $fill = $Width }
    $bar = ("#" * $fill) + ("-" * ($Width - $fill))
    return "[$bar]"
}

# Step 1 - File size
Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       DISK STRESS TEST  setup              " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$fileSizeMB = 0
do {
    $userInput = Read-Host "  Enter test file size in Megabytes (e.g. 512)"
    $valid = [int]::TryParse($userInput.Trim(), [ref]$fileSizeMB) -and ($fileSizeMB -ge 1)
    if (-not $valid) {
        Write-Host "  ! Enter a whole number >= 1" -ForegroundColor Red
    }
} while (-not $valid)

# Step 2 - Create temp source file
Write-Host ""
Write-Host "  Allocating $fileSizeMB MB temp file ..." -ForegroundColor DarkGray

$tempSource = [System.IO.Path]::Combine($env:TEMP, ("kxdisktest_src_" + $PID + ".tmp"))

try {
    $fs = [System.IO.File]::Open($tempSource, 'Create', 'Write', 'None')
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $chunkSize = 4 * 1024 * 1024
    $chunk = New-Object byte[] $chunkSize
    $totalTarget = $fileSizeMB * 1MB
    $written = 0L
    while ($written -lt $totalTarget) {
        $rng.GetBytes($chunk)
        $toWrite = [Math]::Min($chunkSize, $totalTarget - $written)
        $fs.Write($chunk, 0, $toWrite)
        $written += $toWrite
    }
    $fs.Close()
    $rng.Dispose()
} catch {
    Write-Host "  ERROR creating temp file: $_" -ForegroundColor Red
    exit 1
}

# Step 3 - Drive picker
Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       SELECT TARGET DRIVE                  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$diskMap = @{}
try {
    $diskDrives = Get-WmiObject Win32_DiskDrive
    foreach ($disk in $diskDrives) {
        $partitions = $disk.GetRelated('Win32_DiskPartition')
        foreach ($part in $partitions) {
            $logicals = $part.GetRelated('Win32_LogicalDisk')
            foreach ($logical in $logicals) {
                $diskMap[$logical.DeviceID] = $disk.Model.Trim()
            }
        }
    }
} catch {}

$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
$driveList = @()

foreach ($d in $drives) {
    $letter = $d.Name + ":"
    $root   = $d.Root
    $label  = $d.Description
    if (-not $label -or $label -eq '') { $label = "(no label)" }
    $freeGB  = [Math]::Round($d.Free / 1GB, 1)
    $totalGB = [Math]::Round(($d.Free + $d.Used) / 1GB, 1)
    $model   = if ($diskMap.ContainsKey($letter)) { $diskMap[$letter] } else { "Unknown" }
    $obj = [PSCustomObject]@{
        Index   = $driveList.Count + 1
        Letter  = $letter
        Root    = $root
        Label   = $label
        FreeGB  = $freeGB
        TotalGB = $totalGB
        Model   = $model
    }
    $driveList += $obj
}

if ($driveList.Count -eq 0) {
    Write-Host "  No drives found." -ForegroundColor Red
    Remove-Item $tempSource -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host ("  {0,-4} {1,-6} {2,-18} {3,-10} {4,-10} {5}" -f "#", "Drive", "Label", "Free", "Total", "Model") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

foreach ($d in $driveList) {
    $row = "  {0,-4} {1,-6} {2,-18} {3,-10} {4,-10} {5}" -f $d.Index, $d.Letter, $d.Label, ($d.FreeGB.ToString() + " GB"), ($d.TotalGB.ToString() + " GB"), $d.Model
    Write-Host $row -ForegroundColor White
}

Write-Host ""

$selInt = 0
do {
    $sel = Read-Host "  Enter drive number (1-$($driveList.Count))"
    $selValid = [int]::TryParse($sel.Trim(), [ref]$selInt) -and ($selInt -ge 1) -and ($selInt -le $driveList.Count)
    if (-not $selValid) {
        Write-Host "  ! Invalid selection." -ForegroundColor Red
    }
} while (-not $selValid)

$chosen = $driveList[$selInt - 1]

$neededBytes = $fileSizeMB * 1MB
if (($chosen.FreeGB * 1GB) -lt ($neededBytes * 1.05)) {
    Write-Host "  WARNING: Drive may not have enough free space!" -ForegroundColor Yellow
    $confirm = Read-Host "  Continue anyway? (y/n)"
    if ($confirm -notmatch '^[yY]') {
        Remove-Item $tempSource -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

$destFile = [System.IO.Path]::Combine($chosen.Root, ("kxdisktest_" + $PID + ".tmp"))

# Step 4 - Stress loop
Clear-Host
Write-Host ("`n" * 28)

$iteration  = 0
$totalBytes = 0L
$speeds     = [System.Collections.Generic.List[double]]::new()
$maxSpeed   = 0.0
$minSpeed   = [double]::MaxValue
$sw         = [System.Diagnostics.Stopwatch]::new()

[Console]::CursorVisible = $false
[Console]::TreatControlCAsInput = $true

$running = $true

try {
    while ($running) {

        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Q') { $running = $false; break }
            if (($key.Modifiers -band [ConsoleModifiers]::Control) -and ($key.Key -eq 'C')) {
                $running = $false; break
            }
        }
        if (-not $running) { break }

        $sw.Restart()
        try {
            [System.IO.File]::Copy($tempSource, $destFile, $true)
        } catch {
            Start-Sleep -Milliseconds 200
            continue
        }
        $sw.Stop()

        $elapsed = $sw.Elapsed.TotalSeconds
        if ($elapsed -gt 0) {
            $speedMBps = $fileSizeMB / $elapsed
            $speeds.Add($speedMBps)
            if ($speeds.Count -gt 20) { $speeds.RemoveAt(0) }
            $totalBytes += ($fileSizeMB * 1MB)
            if ($speedMBps -gt $maxSpeed) { $maxSpeed = $speedMBps }
            if ($speedMBps -lt $minSpeed) { $minSpeed = $speedMBps }
        }

        try { Remove-Item $destFile -Force -ErrorAction SilentlyContinue } catch {}

        $iteration++

        $avgSpeed = 0.0
        if ($speeds.Count -gt 0) {
            $sum = 0.0
            foreach ($s in $speeds) { $sum += $s }
            $avgSpeed = $sum / $speeds.Count
        }
        $lastSpeed = if ($speeds.Count -gt 0) { $speeds[$speeds.Count - 1] } else { 0.0 }
        $totalMB   = [Math]::Round($totalBytes / 1MB, 1)
        $totalGB   = [Math]::Round($totalBytes / 1GB, 2)

        [Console]::SetCursorPosition(0, 0)

        Draw-Header -Drive $chosen.Letter -Label $chosen.Label -Model $chosen.Model -FileSizeMB $fileSizeMB

        Write-Host ""

        $speedColor = 'Red'
        if ($lastSpeed -ge 400) { $speedColor = 'Green' }
        elseif ($lastSpeed -ge 100) { $speedColor = 'Yellow' }

        Write-Host "  Current  : " -NoNewline -ForegroundColor Gray
        Write-Host ((Format-Speed $lastSpeed).PadRight(14)) -NoNewline -ForegroundColor $speedColor
        Write-Host (Get-SpeedBar $lastSpeed $maxSpeed) -ForegroundColor $speedColor

        Write-Host "  Average  : " -NoNewline -ForegroundColor Gray
        Write-Host (Format-Speed $avgSpeed) -ForegroundColor White

        Write-Host "  Peak     : " -NoNewline -ForegroundColor Gray
        Write-Host (Format-Speed $maxSpeed) -ForegroundColor Cyan

        Write-Host "  Min      : " -NoNewline -ForegroundColor Gray
        if ($minSpeed -eq [double]::MaxValue) {
            Write-Host "--" -ForegroundColor DarkGray
        } else {
            Write-Host (Format-Speed $minSpeed) -ForegroundColor DarkRed
        }

        Write-Host ""
        Write-Host "  Iterations : " -NoNewline -ForegroundColor Gray
        Write-Host $iteration -ForegroundColor White

        Write-Host "  Data wrote : " -NoNewline -ForegroundColor Gray
        $dataStr = $totalMB.ToString() + " MB  (" + $totalGB.ToString() + " GB)"
        Write-Host $dataStr -ForegroundColor White

        Write-Host ""
        Write-Host "  Press Q or Ctrl+C to stop..." -ForegroundColor DarkGray

        for ($i = 0; $i -lt 4; $i++) { Write-Host (" " * 70) }

        Start-Sleep -Milliseconds 100
    }
} finally {
    [Console]::TreatControlCAsInput = $false
    [Console]::CursorVisible = $true

    try { Remove-Item $destFile   -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item $tempSource -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host ""
    Write-Host "  Test stopped. Temp files cleaned up." -ForegroundColor Green

    if ($speeds.Count -gt 0) {
        $sum = 0.0
        foreach ($s in $speeds) { $sum += $s }
        $finalAvg = $sum / $speeds.Count

        Write-Host ""
        Write-Host "  -- Final Summary -----------------------" -ForegroundColor Cyan
        Write-Host "  Iterations : $iteration" -ForegroundColor White
        Write-Host "  Total data : $([Math]::Round($totalBytes / 1MB, 1)) MB" -ForegroundColor White
        Write-Host "  Avg speed  : $(Format-Speed $finalAvg)" -ForegroundColor White
        Write-Host "  Peak speed : $(Format-Speed $maxSpeed)" -ForegroundColor Cyan
        Write-Host "  Min  speed : $(Format-Speed $minSpeed)" -ForegroundColor DarkRed
        Write-Host ""
    }
}
