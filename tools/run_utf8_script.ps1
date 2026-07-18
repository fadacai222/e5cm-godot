[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

$content = Get-Content -Raw -Encoding UTF8 -LiteralPath $ScriptPath
& ([ScriptBlock]::Create($content))
exit $LASTEXITCODE
