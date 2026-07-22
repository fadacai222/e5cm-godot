[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$ProjectRoot = '',
    [string]$EvidenceName = 'runtime-assets-20260717'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path (Split-Path -Parent $ProjectRoot) 'E5CM-CG'
}

$runtimeDirectories = @('UI-img', '冷资源', 'backmovies', 'icon', 'songs')
$allowedExtensions = @(
    '.json', '.sm', '.ssc',
    '.mp3', '.ogg', '.wav',
    '.jpg', '.jpeg', '.png', '.webp',
    '.mp4', '.avi', '.mpg', '.mpeg', '.webm', '.mov',
    '.ttf', '.otf', '.ico'
)
$excludedPatterns = @('*.css', '*.txt', '*.html', '*.js',
    '*.sfk', '*.db', '*.rar', '*.pyc', '*.import')
$destinationRoot = Join-Path $ProjectRoot 'assets\e5cm_runtime'
$evidenceRoot = Join-Path $ProjectRoot ('parity\resource_migration\' + $EvidenceName)
$sourceManifestPath = Join-Path $evidenceRoot 'source_manifest.jsonl'
$destinationManifestPath = Join-Path $evidenceRoot 'project_manifest.jsonl'
$summaryPath = Join-Path $evidenceRoot 'verification_summary.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RuntimeFiles {
    param([string]$Root)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $generatedSongIndex = Join-Path $resolvedRoot 'song_index.json'
    $files = foreach ($directory in $runtimeDirectories) {
        $path = Join-Path $resolvedRoot $directory
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Missing runtime directory: $path"
        }
        Get-ChildItem -LiteralPath $path -Recurse -File |
            Where-Object {
                $_.FullName -ne $generatedSongIndex -and
                $allowedExtensions -contains $_.Extension.ToLowerInvariant()
            }
    }
    return @($files | Sort-Object FullName)
}

function New-HashedManifest {
    param(
        [string]$Root,
        [string]$OutputPath
    )
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $rows = [System.Collections.Generic.List[object]]::new()
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($file in (Get-RuntimeFiles -Root $Root)) {
        $relativePath = $file.FullName.Substring($resolvedRoot.Length).Replace('\', '/')
        $row = [pscustomobject]@{
            path = $relativePath
            bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $rows.Add($row)
        $lines.Add(($row | ConvertTo-Json -Compress))
    }
    [System.IO.File]::WriteAllLines($OutputPath, $lines, $utf8NoBom)
    return $rows
}

function Get-ManifestStats {
    param([System.Collections.Generic.List[object]]$Rows)
    return [pscustomobject]@{
        files = $Rows.Count
        bytes = [int64](($Rows | Measure-Object -Property bytes -Sum).Sum)
    }
}

New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

Write-Output '[1/4] Hashing source runtime assets...'
$sourceRows = New-HashedManifest -Root $SourceRoot -OutputPath $sourceManifestPath

Write-Output '[2/4] Copying runtime assets into the Godot project...'
foreach ($directory in $runtimeDirectories) {
    $sourceDirectory = Join-Path $SourceRoot $directory
    $destinationDirectory = Join-Path $destinationRoot $directory
    $arguments = @(
        $sourceDirectory, $destinationDirectory,
        '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:1', '/MT:16',
        '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XF'
    ) + $excludedPatterns
    & robocopy @arguments | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Robocopy failed for $directory with exit code $LASTEXITCODE"
    }
}

$unexpectedFiles = @(Get-ChildItem -LiteralPath $destinationRoot -Recurse -File |
    Where-Object {
        $_.Extension.ToLowerInvariant() -ne '.import' -and
        $allowedExtensions -notcontains $_.Extension.ToLowerInvariant()
    })
if ($unexpectedFiles.Count -gt 0) {
    throw "Unexpected non-runtime files found in destination: $($unexpectedFiles[0].FullName)"
}

Write-Output '[3/4] Hashing copied project assets...'
$destinationRows = New-HashedManifest -Root $destinationRoot -OutputPath $destinationManifestPath

$sourceByPath = @{}
foreach ($row in $sourceRows) {
    $sourceByPath[$row.path] = $row
}
$mismatches = [System.Collections.Generic.List[object]]::new()
foreach ($row in $destinationRows) {
    if (-not $sourceByPath.ContainsKey($row.path)) {
        $mismatches.Add([pscustomobject]@{ path = $row.path; reason = 'extra' })
        continue
    }
    $source = $sourceByPath[$row.path]
    if ($source.bytes -ne $row.bytes -or $source.sha256 -ne $row.sha256) {
        $mismatches.Add([pscustomobject]@{ path = $row.path; reason = 'hash_or_size' })
    }
    $sourceByPath.Remove($row.path)
}
foreach ($missingPath in $sourceByPath.Keys) {
    $mismatches.Add([pscustomobject]@{ path = $missingPath; reason = 'missing' })
}

$baselineSource = Join-Path $SourceRoot 'godot重构\baseline.json'
$baselineDestination = Join-Path $ProjectRoot 'parity\fixtures\sm_parser_baseline.json'
if (Test-Path -LiteralPath $baselineSource -PathType Leaf) {
    Copy-Item -LiteralPath $baselineSource -Destination $baselineDestination -Force
}

$sourceStats = Get-ManifestStats -Rows $sourceRows
$destinationStats = Get-ManifestStats -Rows $destinationRows
$summary = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
    projectRuntimeRoot = [System.IO.Path]::GetFullPath($destinationRoot)
    includedDirectories = $runtimeDirectories
    allowedExtensions = $allowedExtensions
    excludedPatterns = $excludedPatterns
    source = [ordered]@{
        files = $sourceStats.files
        bytes = $sourceStats.bytes
        manifest = $sourceManifestPath
        manifestSha256 = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    project = [ordered]@{
        files = $destinationStats.files
        bytes = $destinationStats.bytes
        manifest = $destinationManifestPath
        manifestSha256 = (Get-FileHash -LiteralPath $destinationManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    mismatches = $mismatches
    verified = ($mismatches.Count -eq 0 -and
        $sourceStats.files -eq $destinationStats.files -and
        $sourceStats.bytes -eq $destinationStats.bytes)
    baselineFixture = [ordered]@{
        path = $baselineDestination
        sha256 = if (Test-Path -LiteralPath $baselineDestination) {
            (Get-FileHash -LiteralPath $baselineDestination -Algorithm SHA256).Hash.ToLowerInvariant()
        } else { '' }
    }
}
[System.IO.File]::WriteAllText(
    $summaryPath,
    ($summary | ConvertTo-Json -Depth 8),
    $utf8NoBom
)

Write-Output '[4/4] Verification complete.'
Write-Output ("FILES={0} BYTES={1} VERIFIED={2}" -f
    $destinationStats.files, $destinationStats.bytes, $summary.verified)
Write-Output ("SUMMARY={0}" -f $summaryPath)
if (-not $summary.verified) {
    exit 1
}
