[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
if ($PreflightOnly) {
    & $resolvedScript -PreflightOnly
} else {
    & $resolvedScript
}
exit $LASTEXITCODE
