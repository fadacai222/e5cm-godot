param(
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE 'Desktop\e5cm-content'),
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$UserDataRoot = (Join-Path $env:APPDATA 'Godot\app_userdata\e5cm-godot')
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$sourceSongs = Join-Path $projectRoot 'assets\e5cm_runtime\songs'
$destinationSongs = Join-Path $DestinationRoot 'songs'
$godotImported = Join-Path $projectRoot '.godot\imported'
$userDataRoot = [System.IO.Path]::GetFullPath($UserDataRoot)
$configPath = Join-Path $userDataRoot 'songs_root.txt'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$projectProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like 'Godot*.exe' -and [string]$_.CommandLine -like "*$projectRoot*"
})
if ($projectProcesses.Count -gt 0) {
    $pids = ($projectProcesses | Select-Object -ExpandProperty ProcessId) -join ', '
    throw "This project is still open in Godot (PID: $pids). Close the game/editor and run this script again."
}

$sourceHasSongs = Test-Path -LiteralPath $sourceSongs -PathType Container
$destinationHasSongs = Test-Path -LiteralPath $destinationSongs -PathType Container

if ($sourceHasSongs -and $destinationHasSongs) {
    $realSourceEntries = @(Get-ChildItem -LiteralPath $sourceSongs -Force | Where-Object { $_.Name -ne '.gdignore' })
    if ($realSourceEntries.Count -gt 0) {
        throw "Both source and destination contain song data. Nothing was changed.`nSource: $sourceSongs`nDestination: $destinationSongs"
    }
}

if (-not $destinationHasSongs) {
    if (-not $sourceHasSongs) {
        throw "Song library not found: $sourceSongs"
    }
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    Write-Host 'Moving the song library outside the Godot project...'
    Move-Item -LiteralPath $sourceSongs -Destination $destinationSongs
}

# Keep an ignored placeholder so songs are not accidentally imported again.
New-Item -ItemType Directory -Path $sourceSongs -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $sourceSongs '.gdignore'),
    "# External song library placeholder. Real songs are stored outside res://.`r`n",
    $utf8NoBom
)

New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null
[System.IO.File]::WriteAllText($configPath, $destinationSongs, $utf8NoBom)

# Remove the old duplicate imports. Godot will rebuild only the small core assets.
if (Test-Path -LiteralPath $godotImported) {
    Write-Host 'Removing the old .godot/imported duplicate cache...'
    Remove-Item -LiteralPath $godotImported -Recurse -Force
}

$filesystemCaches = @(
    (Join-Path $projectRoot '.godot\editor\filesystem_cache*'),
    (Join-Path $projectRoot '.godot\uid_cache.bin')
)
foreach ($pattern in $filesystemCaches) {
    Remove-Item -Path $pattern -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Migration completed.'
Write-Host "External songs: $destinationSongs"
Write-Host "Runtime config: $configPath"
Write-Host 'On the next start Godot will import only core UI/audio assets, not the 51GB song library.'
