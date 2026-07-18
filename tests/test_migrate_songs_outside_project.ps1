$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = Join-Path $env:TEMP ('e5cm-migrate-test-' + [Guid]::NewGuid().ToString('N'))
$destinationRoot = Join-Path $env:TEMP ('e5cm-content-test-' + [Guid]::NewGuid().ToString('N'))
$userDataRoot = Join-Path $env:TEMP ('e5cm-userdata-test-' + [Guid]::NewGuid().ToString('N'))
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\migrate_songs_outside_project.ps1'

try {
    $sourceSongs = Join-Path $projectRoot 'assets\e5cm_runtime\songs'
    $songFolder = Join-Path $sourceSongs '竞速\club\fixture'
    $imported = Join-Path $projectRoot '.godot\imported'
    New-Item -ItemType Directory -Path $songFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $imported -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $songFolder 'fixture.sm'), '#TITLE:Fixture;', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllBytes((Join-Path $songFolder 'fixture.mp3'), [byte[]](1,2,3,4))
    [System.IO.File]::WriteAllBytes((Join-Path $imported 'duplicate.ctex'), [byte[]](5,6,7,8))

    & $scriptPath -DestinationRoot $destinationRoot -ProjectRoot $projectRoot -UserDataRoot $userDataRoot

    $destinationSongs = Join-Path $destinationRoot 'songs'
    $configPath = Join-Path $userDataRoot 'songs_root.txt'
    $placeholder = Join-Path $sourceSongs '.gdignore'
    $movedSm = Join-Path $destinationSongs '竞速\club\fixture\fixture.sm'

    if (-not (Test-Path -LiteralPath $movedSm -PathType Leaf)) {
        throw "Fixture song was not moved: $movedSm"
    }
    if (-not (Test-Path -LiteralPath $placeholder -PathType Leaf)) {
        throw "Project songs placeholder was not recreated: $placeholder"
    }
    if (Test-Path -LiteralPath $imported) {
        throw "Old imported cache was not removed: $imported"
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "songs_root.txt was not written: $configPath"
    }
    $configured = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
    if ($configured -ne $destinationSongs) {
        throw "Unexpected configured songs root: $configured"
    }

    Write-Output 'MIGRATION SANDBOX TEST PASSED'
}
finally {
    Remove-Item -LiteralPath $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $destinationRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $userDataRoot -Recurse -Force -ErrorAction SilentlyContinue
}
