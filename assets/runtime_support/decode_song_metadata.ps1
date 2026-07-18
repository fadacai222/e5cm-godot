param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function New-StrictEncoding([int]$CodePage) {
    return [System.Text.Encoding]::GetEncoding(
        $CodePage,
        [System.Text.EncoderFallback]::ExceptionFallback,
        [System.Text.DecoderFallback]::ExceptionFallback
    )
}

function Get-SmTag([string]$Text, [string]$Tag) {
    $pattern = '(?im)^\s*#' + [Regex]::Escape($Tag) + '\s*:\s*([^;]*)'
    $match = [Regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return ''
    }
    return ($match.Groups[1].Value -replace '\r?\n', '').Trim()
}

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$encodings = @(
    @{ Name = 'utf-8'; Encoding = $utf8Strict },
    @{ Name = 'gb18030'; Encoding = (New-StrictEncoding 54936) },
    @{ Name = 'gbk'; Encoding = (New-StrictEncoding 936) },
    @{ Name = 'big5'; Encoding = (New-StrictEncoding 950) },
    @{ Name = 'shift-jis'; Encoding = (New-StrictEncoding 932) }
)

$inputJson = [System.IO.File]::ReadAllText($InputPath, [System.Text.Encoding]::UTF8)
$items = @($inputJson | ConvertFrom-Json)
$results = @()

foreach ($item in $items) {
    $path = [string]$item.path
    $result = [ordered]@{
        id       = [string]$item.id
        path     = $path
        title    = ''
        subtitle = ''
        artist   = ''
        encoding = ''
        error    = ''
    }

    try {
        if (-not [System.IO.File]::Exists($path)) {
            throw "File not found"
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $decoded = $null
        foreach ($candidate in $encodings) {
            try {
                $text = $candidate.Encoding.GetString($bytes)
                if ($text.IndexOf('#TITLE:', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    continue
                }
                $decoded = $text
                $result.encoding = [string]$candidate.Name
                break
            }
            catch [System.Text.DecoderFallbackException] {
                continue
            }
        }
        if ($null -eq $decoded) {
            throw "No supported text encoding could decode this chart"
        }
        $result.title = Get-SmTag $decoded 'TITLE'
        $result.subtitle = Get-SmTag $decoded 'SUBTITLE'
        $result.artist = Get-SmTag $decoded 'ARTIST'
    }
    catch {
        $result.error = $_.Exception.Message
    }
    $results += [pscustomobject]$result
}

$outputJson = ConvertTo-Json -InputObject @($results) -Depth 5 -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $outputJson, $utf8NoBom)
