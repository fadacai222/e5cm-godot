[CmdletBinding()]
param()

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
$Installer = Join-Path $ReleaseRoot 'E5CM-Setup-0.9.1.exe'
$ReleaseTool = Join-Path $ProjectRoot 'tools\release\build_release.py'
$SmokeTool = Join-Path $ProjectRoot 'tools\release\smoke_installer.ps1'
$IndexBackup = Join-Path $ProjectRoot '.release-backup\original-song_index.json'
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

function Get-SongFolderCount([string]$Root) {
    $Count = 0
    foreach ($Top in Get-ChildItem -LiteralPath $Root -Directory -Force) {
        foreach ($Sub in Get-ChildItem -LiteralPath $Top.FullName -Directory -Force) {
            $Count += @(Get-ChildItem -LiteralPath $Sub.FullName -Directory -Force).Count
        }
    }
    return $Count
}

Set-Location -LiteralPath $ProjectRoot

$PythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $PythonCommand) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $PythonCommand) {
    throw '未找到 Python。'
}
$Python = $PythonCommand.Source

$Godot = Resolve-ExistingFile @(
    $env:E5CM_GODOT_CONSOLE,
    (Join-Path (Split-Path -Parent $ProjectRoot) 'Godot_v4.6.2-stable_win64_console.exe'),
    'C:\Godot\Godot_v4.6.2-stable_win64_console.exe'
) 'Godot 4.6.2 控制台程序'

$InnoSetup = Resolve-ExistingFile @(
    $env:E5CM_ISCC,
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) 'Inno Setup 6 编译器 ISCC.exe'

$MagickCommand = Get-Command magick.exe -ErrorAction SilentlyContinue
if (-not $MagickCommand) {
    $MagickCommand = Get-Command magick -ErrorAction SilentlyContinue
}
if (-not $MagickCommand) {
    throw '未找到 ImageMagick magick.exe。'
}

if (-not (Test-Path -LiteralPath $SongsRoot -PathType Container)) {
    throw "完整曲库不存在：$SongsRoot"
}
$BeforeSongFolderCount = Get-SongFolderCount $SongsRoot
if ($BeforeSongFolderCount -le 100) {
    throw "完整曲库数量异常，拒绝打包：song_folder_count=$BeforeSongFolderCount"
}

$IndexNeedsRestore = $false
try {
    Write-Step '预检发行配置和重复资源策略'
    & $Python $ReleaseTool audit-assets
    Assert-LastExitCode '发行资源预检'

    Write-Step '创建独立打包专用 songs（每个可玩模式最多随机 4 首）'
    & $Python $ReleaseTool prepare
    Assert-LastExitCode '准备发行曲库'
    $IndexNeedsRestore = Test-Path -LiteralPath $IndexBackup -PathType Leaf

    Write-Step '导出 Windows EXE/PCK'
    & $Godot --headless --path $ProjectRoot --export-release 'Windows Desktop' (Join-Path $PortableRoot 'E5CM.exe')
    Assert-LastExitCode 'Godot Windows 导出'

    Write-Step '恢复开发用完整歌曲索引'
    & $Python $ReleaseTool restore-index
    Assert-LastExitCode '恢复完整歌曲索引'
    $IndexNeedsRestore = $false

    Write-Step '验证便携版文件和每模式歌曲数量'
    & $Python $ReleaseTool verify
    Assert-LastExitCode '便携版校验'

    Write-Step '运行便携版发行资产探针'
    $PreviousProbe = $env:E5CM_RELEASE_ASSET_PROBE
    $env:E5CM_RELEASE_ASSET_PROBE = '1'
    try {
        & (Join-Path $PortableRoot 'E5CM.exe') --headless
        Assert-LastExitCode '便携版发行资产探针'
    }
    finally {
        $env:E5CM_RELEASE_ASSET_PROBE = $PreviousProbe
    }

    Write-Step '编译 Inno Setup 安装包'
    & $InnoSetup (Join-Path $ProjectRoot 'packaging\E5CM.iss')
    Assert-LastExitCode 'Inno Setup 编译'
    if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
        throw "安装包未生成：$Installer"
    }

    Write-Step '执行静默安装、运行和卸载烟雾测试'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $SmokeTool -ProjectRoot $ProjectRoot
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
    Write-Host "`n打包成功。" -ForegroundColor Green
    Write-Host "便携版：$PortableRoot"
    Write-Host "EXE：$PortableExe"
    Write-Host "PCK：$PortablePck"
    Write-Host "安装包：$Installer"
    Write-Host "完整曲库目录数保持不变：$AfterSongFolderCount"
}
finally {
    if ($IndexNeedsRestore -and (Test-Path -LiteralPath $IndexBackup -PathType Leaf)) {
        Write-Warning '检测到构建中断，正在恢复开发用完整歌曲索引。'
        & $Python $ReleaseTool restore-index
        if ($LASTEXITCODE -ne 0) {
            Write-Error '自动恢复完整歌曲索引失败，请不要继续开发或提交 song_index.json。'
        }
    }
}
