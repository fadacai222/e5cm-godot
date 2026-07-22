[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$EvidenceName = 'runtime-assets-20260717'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$runtimeRoot = Join-Path $ProjectRoot 'assets\e5cm_runtime'
$evidenceRoot = Join-Path $ProjectRoot ('parity\resource_migration\' + $EvidenceName)
$manifestPath = Join-Path $evidenceRoot 'image_path_normalization.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$runtimePrefix = [System.IO.Path]::GetFullPath($runtimeRoot).TrimEnd('\') + '\'

function Get-ImageFormat {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 12
        $read = $stream.Read($bytes, 0, 12)
    } finally {
        $stream.Dispose()
    }
    if ($read -ge 8 -and ($bytes[0..7] -join ',') -eq '137,80,78,71,13,10,26,10') {
        return 'png'
    }
    if ($read -ge 3 -and $bytes[0] -eq 255 -and $bytes[1] -eq 216 -and $bytes[2] -eq 255) {
        return 'jpg'
    }
    if ($read -ge 12 -and
        [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'RIFF' -and
        [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4) -eq 'WEBP') {
        return 'webp'
    }
    return 'unknown'
}

$changes = [System.Collections.Generic.List[object]]::new()
$images = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @('.png', '.jpg', '.jpeg', '.webp') })

foreach ($file in $images) {
    $extension = $file.Extension.TrimStart('.').ToLowerInvariant()
    if ($extension -eq 'jpeg') {
        $extension = 'jpg'
    }
    $detected = Get-ImageFormat -Path $file.FullName
    if ($detected -eq 'unknown') {
        throw "Unknown image format: $($file.FullName)"
    }
    if ($extension -eq $detected) {
        continue
    }

    $target = [System.IO.Path]::ChangeExtension($file.FullName, $detected)
    $targetFull = [System.IO.Path]::GetFullPath($target)
    if (-not $targetFull.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Normalization target escaped runtime root: $targetFull"
    }
    $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if (Test-Path -LiteralPath $targetFull) {
        $targetHash = (Get-FileHash -LiteralPath $targetFull -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($targetHash -ne $sourceHash) {
            throw "Conflicting normalized image target: $targetFull"
        }
        Remove-Item -LiteralPath $file.FullName -Force
    } else {
        Move-Item -LiteralPath $file.FullName -Destination $targetFull
    }

    $oldImport = $file.FullName + '.import'
    $newImport = $targetFull + '.import'
    if (Test-Path -LiteralPath $oldImport) {
        Remove-Item -LiteralPath $oldImport -Force
    }
    if (Test-Path -LiteralPath $newImport) {
        Remove-Item -LiteralPath $newImport -Force
    }
    $verifiedHash = (Get-FileHash -LiteralPath $targetFull -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($verifiedHash -ne $sourceHash) {
        throw "Normalized image hash changed: $targetFull"
    }

    $changes.Add([pscustomobject]@{
        oldPath = $file.FullName.Substring($runtimePrefix.Length).Replace('\', '/')
        newPath = $targetFull.Substring($runtimePrefix.Length).Replace('\', '/')
        bytes = [int64](Get-Item -LiteralPath $targetFull).Length
        sha256 = $sourceHash
        detectedFormat = $detected
    })
}

$remainingMismatches = 0
foreach ($file in Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @('.png', '.jpg', '.jpeg', '.webp') }) {
    $extension = $file.Extension.TrimStart('.').ToLowerInvariant()
    if ($extension -eq 'jpeg') {
        $extension = 'jpg'
    }
    if ((Get-ImageFormat -Path $file.FullName) -ne $extension) {
        $remainingMismatches++
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    runtimeRoot = $runtimeRoot
    changedFiles = $changes.Count
    remainingMismatches = $remainingMismatches
    changes = $changes
}
[System.IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 6),
    $utf8NoBom
)
Write-Output ("NORMALIZED={0} REMAINING_MISMATCHES={1}" -f
    $changes.Count, $remainingMismatches)
Write-Output ("MANIFEST={0}" -f $manifestPath)
if ($remainingMismatches -ne 0) {
    exit 1
}
