param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Version = $env:E5CM_RELEASE_VERSION
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Version)) {
    $ProjectConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot 'project.godot') -Raw -Encoding UTF8
    $Match = [regex]::Match($ProjectConfig, '(?m)^config/version="([^"]+)"$')
    if (-not $Match.Success) {
        throw 'project.godot 缺少 application/config/version，无法确定安装包版本。'
    }
    $Version = $Match.Groups[1].Value
}
if ($Version -notmatch '^godot-\d+\.\d+\.\d+$') {
    throw "无效安装包版本：$Version"
}
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
    $ReleaseIndexPath = Join-Path $InstallDir 'release-song-index.json'
    $CompatibilityLauncher = Join-Path $InstallDir 'E5CM-Compatibility.bat'
    if (-not (Test-Path -LiteralPath $Exe)) { throw 'Installed E5CM.exe is missing' }
    if (-not (Test-Path -LiteralPath $Pck)) { throw 'Installed E5CM.pck is missing' }
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw 'Installed release manifest is missing' }
    if (-not (Test-Path -LiteralPath $ReleaseIndexPath)) { throw 'Installed release song index is missing' }
    if (-not (Test-Path -LiteralPath $CompatibilityLauncher)) { throw 'Installed compatibility launcher is missing' }
    if (-not (Test-Path -LiteralPath $Shortcut)) { throw 'Desktop shortcut was not created' }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ReleaseIndex = Get-Content -LiteralPath $ReleaseIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($ReleaseIndex.releaseVersion -ne $Version -or [int]$ReleaseIndex.songVariantCount -gt 44) {
        throw 'Installed release song index metadata is invalid'
    }
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

    # 烟雾测试必须使用临时 APPDATA，禁止读取或污染开发者/真实玩家的 E5CM 数据。
    $PreviousProbe = [Environment]::GetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', 'Process')
    $PreviousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
    $PreviousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
    $SmokeUserRoot = Join-Path $env:TEMP ("E5CM-Installer-Smoke-User-" + [Guid]::NewGuid().ToString('N'))
    $SmokeRoaming = Join-Path $SmokeUserRoot 'Roaming'
    $SmokeLocal = Join-Path $SmokeUserRoot 'Local'
    New-Item -ItemType Directory -Path $SmokeRoaming, $SmokeLocal -Force | Out-Null
    [Environment]::SetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', '1', 'Process')
    [Environment]::SetEnvironmentVariable('APPDATA', $SmokeRoaming, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $SmokeLocal, 'Process')
    try {
        $game = Start-Process -FilePath $Exe -ArgumentList @('--headless') -WorkingDirectory $InstallDir -Wait -PassThru
        if ($game.ExitCode -ne 0) {
            throw "Installed game asset probe exited with code $($game.ExitCode)"
        }

        $compatGame = Start-Process -FilePath $Exe -ArgumentList @(
            '--headless', '--rendering-method', 'gl_compatibility') -WorkingDirectory $InstallDir -Wait -PassThru
        if ($compatGame.ExitCode -ne 0) {
            throw "Installed compatibility renderer probe exited with code $($compatGame.ExitCode)"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('E5CM_RELEASE_ASSET_PROBE', $PreviousProbe, 'Process')
        [Environment]::SetEnvironmentVariable('APPDATA', $PreviousAppData, 'Process')
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $PreviousLocalAppData, 'Process')
        Remove-Item -LiteralPath $SmokeUserRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $Uninstaller = Join-Path $InstallDir 'unins000.exe'
    if (-not (Test-Path -LiteralPath $Uninstaller)) { throw 'Uninstaller is missing' }
    $uninstall = Start-Process -FilePath $Uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) {
        throw "Uninstaller exited with code $($uninstall.ExitCode)"
    }

    $MarkerDirectory = Split-Path -Parent $Marker
    if (-not (Test-Path -LiteralPath $MarkerDirectory)) {
        New-Item -ItemType Directory -Path $MarkerDirectory -Force | Out-Null
    }
    "installer=$Installer`ninstalled_game_exit=0`ncompatibility_renderer_exit=0`nshortcut_created=true`nuninstall_exit=0`n" |
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
