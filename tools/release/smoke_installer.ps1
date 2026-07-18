param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
$Version = '0.9.1'
$Installer = Join-Path $ProjectRoot "release\E5CM-Setup-$Version.exe"
$InstallDir = Join-Path $env:TEMP 'E5CM-Installer-Smoke'
$Desktop = [Environment]::GetFolderPath('Desktop')
$Shortcut = Join-Path $Desktop 'E5CM.lnk'
$ShortcutBackup = Join-Path $env:TEMP 'E5CM-shortcut-before-smoke.lnk'
$Marker = Join-Path $ProjectRoot '.release-staging\installer-smoke-passed.txt'
$HadShortcut = Test-Path -LiteralPath $Shortcut

if (-not (Test-Path -LiteralPath $Installer)) {
    throw "Installer not found: $Installer"
}

if ($HadShortcut) {
    Copy-Item -LiteralPath $Shortcut -Destination $ShortcutBackup -Force
}

try {
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }
    $arguments = @(
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        "/DIR=$InstallDir"
    )
    $install = Start-Process -FilePath $Installer -ArgumentList $arguments -Wait -PassThru
    if ($install.ExitCode -ne 0) {
        throw "Installer exited with code $($install.ExitCode)"
    }

    $Exe = Join-Path $InstallDir 'E5CM.exe'
    $Pck = Join-Path $InstallDir 'E5CM.pck'
    $ManifestPath = Join-Path $InstallDir 'release-song-selection.json'
    if (-not (Test-Path -LiteralPath $Exe)) { throw 'Installed E5CM.exe is missing' }
    if (-not (Test-Path -LiteralPath $Pck)) { throw 'Installed E5CM.pck is missing' }
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw 'Installed release manifest is missing' }
    if (-not (Test-Path -LiteralPath $Shortcut)) { throw 'Desktop shortcut was not created' }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($Property in $Manifest.modes.PSObject.Properties) {
        $ModeName = $Property.Name
        $Mode = $Property.Value
        $Expected = @($Mode.selected | ForEach-Object { $_.folder } | Sort-Object)
        $Leaf = Join-Path (Join-Path $InstallDir 'songs') ($ModeName -replace '/', '\')
        $Actual = @()
        if (Test-Path -LiteralPath $Leaf) {
            $Actual = @(Get-ChildItem -LiteralPath $Leaf -Directory | Select-Object -ExpandProperty Name | Sort-Object)
        }
        if ($Actual.Count -gt 4) {
            throw "Mode contains more than 4 songs: $ModeName = $($Actual.Count)"
        }
        if (($Expected -join '|') -ne ($Actual -join '|')) {
            throw "Installed songs mismatch for $ModeName"
        }
    }

    $PreviousProbe = [Environment]::GetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', 'Process')
    [Environment]::SetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', '1', 'Process')
    try {
        $game = Start-Process -FilePath $Exe -ArgumentList @('--headless') -WorkingDirectory $InstallDir -Wait -PassThru
    }
    finally {
        [Environment]::SetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', $PreviousProbe, 'Process')
    }
    if ($game.ExitCode -ne 0) {
        throw "Installed game asset probe exited with code $($game.ExitCode)"
    }

    $Uninstaller = Join-Path $InstallDir 'unins000.exe'
    if (-not (Test-Path -LiteralPath $Uninstaller)) { throw 'Uninstaller is missing' }
    $uninstall = Start-Process -FilePath $Uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) {
        throw "Uninstaller exited with code $($uninstall.ExitCode)"
    }

    "installer=$Installer`ninstalled_game_exit=0`nshortcut_created=true`nuninstall_exit=0`n" |
        Set-Content -LiteralPath $Marker -Encoding UTF8
    Write-Output 'INSTALLER SMOKE TEST PASSED'
}
finally {
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($HadShortcut -and (Test-Path -LiteralPath $ShortcutBackup)) {
        Copy-Item -LiteralPath $ShortcutBackup -Destination $Shortcut -Force
        Remove-Item -LiteralPath $ShortcutBackup -Force -ErrorAction SilentlyContinue
    }
    elseif (-not $HadShortcut -and (Test-Path -LiteralPath $Shortcut)) {
        Remove-Item -LiteralPath $Shortcut -Force -ErrorAction SilentlyContinue
    }
}
