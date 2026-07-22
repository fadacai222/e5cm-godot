[CmdletBinding()]
param(
    [string]$Version,
    [switch]$PreflightOnly,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $Utf8NoBom
[Console]::OutputEncoding = $Utf8NoBom
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseRoot = Join-Path $ProjectRoot 'release'
$PortableRoot = Join-Path $ReleaseRoot 'E5CM'
$ReleaseTool = Join-Path $ProjectRoot 'tools\release\build_release.py'
$VersionTool = Join-Path $ProjectRoot 'tools\release\version_manager.py'
$SmokeTool = Join-Path $ProjectRoot 'tools\release\smoke_installer.ps1'
$SongsRoot = Join-Path $ProjectRoot 'songs'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-LastExitCode([string]$Action) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Action 失败，退出码：$LASTEXITCODE"
    }
}

function Resolve-ExistingFile([string[]]$Candidates, [string]$ToolName) {
    foreach ($Candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
        $Expanded = [Environment]::ExpandEnvironmentVariables($Candidate)
        if (Test-Path -LiteralPath $Expanded -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Expanded).Path
        }
    }
    throw "未找到 $ToolName。已检查：$($Candidates -join '; ')"
}

function Get-FirstCommandPath([string[]]$Names) {
    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command -and -not [string]::IsNullOrWhiteSpace($Command.Source)) {
            return $Command.Source
        }
    }
    return $null
}

function Get-SongFolderCount([string]$Root) {
    $Count = 0
    foreach ($Top in Get-ChildItem -LiteralPath $Root -Directory -Force) {
        foreach ($Sub in Get-ChildItem -LiteralPath $Top.FullName -Directory -Force) {
            $Count += @(Get-ChildItem -LiteralPath $Sub.FullName -Directory -Force).Count
        }
    }
    return $Count
}

function Remove-WindowsReservedArtifacts([string]$Root) {
    $ReservedNames = @('CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    foreach ($Item in Get-ChildItem -LiteralPath $Root -Force -File -ErrorAction SilentlyContinue) {
        if ($ReservedNames -notcontains $Item.BaseName.ToUpperInvariant()) { continue }
        $ExtendedPath = '\\?\' + $Item.FullName
        [System.IO.File]::Delete($ExtendedPath)
        if ([System.IO.File]::Exists($ExtendedPath)) {
            throw "无法删除 Windows 保留名文件：$($Item.FullName)"
        }
        Write-Warning "已清理 Windows 保留名垃圾文件：$($Item.Name)"
    }
}

function Invoke-VersionJson([string[]]$Arguments, [string]$Action) {
    $Output = & $Python $VersionTool @Arguments
    Assert-LastExitCode $Action
    try {
        return (($Output -join "`n") | ConvertFrom-Json)
    }
    catch {
        throw "$Action 返回了无法解析的结果：$($Output -join ' ')"
    }
}

Set-Location -LiteralPath $ProjectRoot
Remove-WindowsReservedArtifacts $ProjectRoot

$Python = Get-FirstCommandPath @('python.exe', 'python')
if (-not $Python) {
    throw '未找到 Python。请安装 Python 3.10+ 并加入 PATH。'
}
if (-not (Test-Path -LiteralPath $VersionTool -PathType Leaf)) {
    throw "版本管理工具不存在：$VersionTool"
}

$CurrentVersionInfo = Invoke-VersionJson @('show') '读取当前版本'
$CurrentVersion = [string]$CurrentVersionInfo.version
$CurrentFileVersion = [string]$CurrentVersionInfo.fileVersion

if ($PreflightOnly) {
    Write-Host "当前发行版本：$CurrentVersion（Windows 文件版本 $CurrentFileVersion）" -ForegroundColor Yellow
    Invoke-VersionJson @('verify', '--version', $CurrentVersion) '校验版本元数据' | Out-Null
    Write-Step '校验发行资源、测试资料排除规则与正式玩家目录隔离'
    & $Python $ReleaseTool audit-assets
    Assert-LastExitCode '发行安全预检'
    Write-Host '发行预检通过：版本元数据一致，正式包不会复用开发测试档案。' -ForegroundColor Green
    return
}

$RequestedVersion = $Version
if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
    $RequestedVersion = Read-Host "当前版本为 $CurrentVersion。输入新版本（例如 2.0.2），直接回车保持当前版本"
    if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
        $RequestedVersion = $CurrentVersion
    }
}

$PlannedVersionInfo = Invoke-VersionJson @('normalize', '--version', $RequestedVersion) '解析版本号'
$ReleaseVersion = [string]$PlannedVersionInfo.version
$FileVersion = [string]$PlannedVersionInfo.fileVersion

Write-Host "`n本次发行版本：$ReleaseVersion" -ForegroundColor Yellow
Write-Host "Windows 文件版本：$FileVersion" -ForegroundColor Yellow
Write-Host '将同步：游戏内版本、全部场景中的旧版本字面量、EXE 属性、安装器、发行索引和回归测试。'
if (-not $Yes) {
    $Confirmation = Read-Host '确认继续请输入 Y'
    if ($Confirmation -notmatch '^(?i:y|yes)$') {
        throw '用户取消打包，项目文件未修改。'
    }
}

Write-Step '同步全项目发行版本'
$SyncResult = Invoke-VersionJson @('sync', '--version', $ReleaseVersion) '同步发行版本'
$ChangedFiles = @($SyncResult.changed)
if ($ChangedFiles.Count -gt 0) {
    Write-Host "已同步 $($ChangedFiles.Count) 个版本位置。" -ForegroundColor Green
}
else {
    Write-Host '当前项目已经是该版本，无需改写版本文件。' -ForegroundColor DarkGray
}
Invoke-VersionJson @('verify', '--version', $ReleaseVersion) '复核发行版本' | Out-Null

$Installer = Join-Path $ReleaseRoot "E5CM-Setup-$ReleaseVersion.exe"
$GodotFromPath = Get-FirstCommandPath @(
    'Godot_v4.6.2-stable_win64_console.exe',
    'godot4_console.exe',
    'godot_console.exe',
    'godot4.exe',
    'godot.exe'
)
$Godot = Resolve-ExistingFile @(
    $env:E5CM_GODOT_CONSOLE,
    $GodotFromPath,
    (Join-Path (Split-Path -Parent $ProjectRoot) 'Godot_v4.6.2-stable_win64_console.exe'),
    'C:\Godot\Godot_v4.6.2-stable_win64_console.exe'
) 'Godot 控制台程序'

$InnoSetup = Resolve-ExistingFile @(
    $env:E5CM_ISCC,
    (Get-FirstCommandPath @('ISCC.exe', 'ISCC')),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) 'Inno Setup 6 编译器 ISCC.exe'

$BrandIconPng = Join-Path $ProjectRoot 'assets\branding\e5cm_icon.png'
$BrandIconIco = Join-Path $ProjectRoot 'assets\branding\e5cm.ico'
if (-not (Test-Path -LiteralPath $BrandIconPng -PathType Leaf) -or
        -not (Test-Path -LiteralPath $BrandIconIco -PathType Leaf)) {
    $Magick = Get-FirstCommandPath @('magick.exe', 'magick')
    if (-not $Magick) {
        throw '游戏图标缺失，且未找到 ImageMagick magick.exe，无法自动生成图标。'
    }
}

if (-not (Test-Path -LiteralPath $SongsRoot -PathType Container)) {
    throw "完整曲库不存在：$SongsRoot"
}
$BeforeSongFolderCount = Get-SongFolderCount $SongsRoot
if ($BeforeSongFolderCount -le 100) {
    throw "完整曲库数量异常，拒绝打包：song_folder_count=$BeforeSongFolderCount"
}

$PreviousGodotConsole = $env:E5CM_GODOT_CONSOLE
$PreviousReleaseVersion = $env:E5CM_RELEASE_VERSION
$PreviousFileVersion = $env:E5CM_FILE_VERSION
$env:E5CM_GODOT_CONSOLE = $Godot
$env:E5CM_RELEASE_VERSION = $ReleaseVersion
$env:E5CM_FILE_VERSION = $FileVersion

try {
    Write-Step '预检发行配置、版本一致性、测试资料排除规则和重复资源策略'
    Invoke-VersionJson @('verify', '--version', $ReleaseVersion) '发行前版本校验' | Out-Null
    & $Python $ReleaseTool audit-assets
    Assert-LastExitCode '发行资源预检'

    Write-Step '创建独立打包专用 songs（每个可玩模式最多随机 4 首）'
    & $Python $ReleaseTool prepare
    Assert-LastExitCode '准备发行曲库'

    Write-Step '导出 Windows EXE/PCK'
    & $Godot --headless --path $ProjectRoot --export-release 'Windows Desktop' (Join-Path $PortableRoot 'E5CM.exe')
    Assert-LastExitCode 'Godot Windows 导出'

    Write-Step '验证便携版为空白玩家包、文件白名单和每模式歌曲数量'
    & $Python $ReleaseTool verify
    Assert-LastExitCode '便携版校验'

    Write-Step '在隔离的临时玩家目录运行便携版发行资产探针'
    $PreviousProbe = $env:E5CM_RELEASE_ASSET_PROBE
    $PreviousAppData = $env:APPDATA
    $PreviousLocalAppData = $env:LOCALAPPDATA
    $ProbeUserRoot = Join-Path $env:TEMP ("E5CM-Release-Probe-" + [Guid]::NewGuid().ToString('N'))
    $ProbeRoaming = Join-Path $ProbeUserRoot 'Roaming'
    $ProbeLocal = Join-Path $ProbeUserRoot 'Local'
    New-Item -ItemType Directory -Path $ProbeRoaming, $ProbeLocal -Force | Out-Null
    $env:E5CM_RELEASE_ASSET_PROBE = '1'
    $env:APPDATA = $ProbeRoaming
    $env:LOCALAPPDATA = $ProbeLocal
    try {
        & (Join-Path $PortableRoot 'E5CM.exe') --headless
        Assert-LastExitCode '便携版发行资产探针'
    }
    finally {
        $env:E5CM_RELEASE_ASSET_PROBE = $PreviousProbe
        $env:APPDATA = $PreviousAppData
        $env:LOCALAPPDATA = $PreviousLocalAppData
        Remove-Item -LiteralPath $ProbeUserRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Step '编译 Inno Setup 安装包'
    & $InnoSetup (Join-Path $ProjectRoot 'packaging\E5CM.iss')
    Assert-LastExitCode 'Inno Setup 编译'
    if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
        throw "安装包未生成：$Installer"
    }

    Write-Step '执行静默安装、运行和卸载烟雾测试'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $SmokeTool `
        -ProjectRoot $ProjectRoot -Version $ReleaseVersion
    Assert-LastExitCode '安装包烟雾测试'

    Write-Step '完成发行清理（保留完整 songs 和 release 产物）'
    & $Python $ReleaseTool finalize
    Assert-LastExitCode '发行清理'

    $AfterSongFolderCount = Get-SongFolderCount $SongsRoot
    if ($AfterSongFolderCount -ne $BeforeSongFolderCount) {
        throw "完整 songs 目录数量发生变化：before=$BeforeSongFolderCount after=$AfterSongFolderCount"
    }

    $PortableExe = Join-Path $PortableRoot 'E5CM.exe'
    $PortablePck = Join-Path $PortableRoot 'E5CM.pck'
    Write-Host "`n打包成功：$ReleaseVersion" -ForegroundColor Green
    Write-Host "便携版：$PortableRoot"
    Write-Host "EXE：$PortableExe"
    Write-Host "PCK：$PortablePck"
    Write-Host "安装包：$Installer"
    Write-Host "完整曲库目录数保持不变：$AfterSongFolderCount"
}
finally {
    $env:E5CM_GODOT_CONSOLE = $PreviousGodotConsole
    $env:E5CM_RELEASE_VERSION = $PreviousReleaseVersion
    $env:E5CM_FILE_VERSION = $PreviousFileVersion
    # 精选索引只写入 release 目录，开发用完整索引不会被替换。
}
