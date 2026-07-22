[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Source = '',
    [string]$Destination = '',
    [string]$ProjectRoot = '',
    [switch]$KeepSource
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path (Split-Path -Parent $ProjectRoot) 'e5cm_runtime.__long_task_hold__'
}
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $ProjectRoot 'assets\e5cm_runtime'
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

$sourceFull = Get-NormalizedFullPath -Path $Source
$destinationFull = Get-NormalizedFullPath -Path $Destination
$projectFull = Get-NormalizedFullPath -Path $ProjectRoot

if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) {
    throw "Source runtime directory does not exist: $sourceFull"
}
if ([System.IO.Path]::GetFileName($sourceFull) -ne 'e5cm_runtime.__long_task_hold__') {
    throw "Refusing unexpected source directory: $sourceFull"
}
if (-not $destinationFull.StartsWith($projectFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Destination must be inside the Godot project: $destinationFull"
}
if ($sourceFull.Equals($destinationFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and destination are the same directory.'
}

$runningGodot = @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like 'Godot*' -or $_.ProcessName -like 'e5cm*' })
if ($runningGodot.Count -gt 0) {
    throw "Close running Godot/E5CM processes before migration: $($runningGodot.ProcessName -join ', ')"
}

$sourceFiles = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Force)
$sourceBytes = [int64](($sourceFiles | Measure-Object -Property Length -Sum).Sum)
$driveName = ([System.IO.Path]::GetPathRoot($destinationFull)).TrimEnd('\').TrimEnd(':')
$drive = Get-PSDrive -Name $driveName
$requiredFree = [int64]($sourceBytes * 1.08)
if ([int64]$drive.Free -lt $requiredFree) {
    throw "Insufficient free space. Required with headroom: $requiredFree; available: $($drive.Free)"
}

Write-Output ("SOURCE={0}" -f $sourceFull)
Write-Output ("DESTINATION={0}" -f $destinationFull)
Write-Output ("SOURCE_FILES={0} SOURCE_BYTES={1}" -f $sourceFiles.Count, $sourceBytes)

if ($WhatIfPreference) {
    Write-Output 'WHATIF: validation passed; no files were copied or deleted.'
    return
}

New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null

if ($PSCmdlet.ShouldProcess($destinationFull, "Merge runtime files from $sourceFull")) {
    $robocopyArgs = @(
        $sourceFull,
        $destinationFull,
        '/E',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/R:2',
        '/W:2',
        '/MT:16',
        '/XJ',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP'
    )
    & robocopy @robocopyArgs
    $robocopyExit = $LASTEXITCODE
    if ($robocopyExit -gt 7) {
        throw "Robocopy failed with exit code $robocopyExit. Source remains untouched."
    }
}

Write-Output 'VERIFYING: size and SHA-256 for every source file...'
$mismatches = [System.Collections.Generic.List[object]]::new()
$verifiedFiles = 0
$verifiedBytes = [int64]0
foreach ($sourceFile in $sourceFiles) {
    $relative = $sourceFile.FullName.Substring($sourceFull.Length).TrimStart('\', '/')
    $destinationFile = Join-Path $destinationFull $relative
    if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) {
        $mismatches.Add([pscustomobject]@{ path = $relative; reason = 'missing' })
        continue
    }
    $destinationInfo = Get-Item -LiteralPath $destinationFile
    if ([int64]$destinationInfo.Length -ne [int64]$sourceFile.Length) {
        $mismatches.Add([pscustomobject]@{ path = $relative; reason = 'size' })
        continue
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        $mismatches.Add([pscustomobject]@{ path = $relative; reason = 'sha256' })
        continue
    }
    $verifiedFiles += 1
    $verifiedBytes += [int64]$sourceFile.Length
}

$verified = $mismatches.Count -eq 0 -and
    $verifiedFiles -eq $sourceFiles.Count -and
    $verifiedBytes -eq $sourceBytes

$evidenceRoot = Join-Path $projectFull 'parity\resource_migration'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summaryPath = Join-Path $evidenceRoot ("runtime-hold-finalization-$timestamp.json")
$summary = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    source = $sourceFull
    destination = $destinationFull
    sourceFiles = $sourceFiles.Count
    sourceBytes = $sourceBytes
    verifiedFiles = $verifiedFiles
    verifiedBytes = $verifiedBytes
    mismatchCount = $mismatches.Count
    mismatches = @($mismatches | Select-Object -First 100)
    verified = $verified
    sourceDeleted = $false
}

if (-not $verified) {
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    throw "Verification failed with $($mismatches.Count) mismatch(es). Source remains untouched. Summary: $summaryPath"
}

if (-not $KeepSource -and $PSCmdlet.ShouldProcess($sourceFull, 'Delete verified source runtime directory')) {
    Remove-Item -LiteralPath $sourceFull -Recurse -Force
    if (Test-Path -LiteralPath $sourceFull) {
        throw "Source deletion did not complete: $sourceFull"
    }
    $summary.sourceDeleted = $true
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Output ("VERIFIED={0} FILES={1} BYTES={2}" -f $verified, $verifiedFiles, $verifiedBytes)
Write-Output ("SOURCE_DELETED={0}" -f $summary.sourceDeleted)
Write-Output ("SUMMARY={0}" -f $summaryPath)
