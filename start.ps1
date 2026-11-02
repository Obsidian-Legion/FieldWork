param([int]$Port = 8787, [string]$DataDirectory = 'data', [switch]$Build)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
chcp.com 65001 | Out-Null
$ucmCommand = Get-Command ucm -ErrorAction Stop
New-Item -ItemType Directory -Path '.runtime' -Force | Out-Null
if (-not (Test-Path -LiteralPath '.unison/.unison/v2/unison.sqlite3')) {
    & $ucmCommand.Source -C '.unison' transcript.in-place 'scripts/setup.md'
    if ($LASTEXITCODE -ne 0) { throw 'Unison setup failed.' }
    $Build = $true
}
$artifact = '.runtime/fieldwork.uc'
if ($Build -or -not (Test-Path -LiteralPath $artifact) -or (Get-Item 'src/main.u').LastWriteTimeUtc -gt (Get-Item $artifact).LastWriteTimeUtc) {
    & $ucmCommand.Source -c '.unison' transcript.in-place 'scripts/build.md'
    if ($LASTEXITCODE -ne 0) { throw 'Unison build failed.' }
}
& $ucmCommand.Source run.compiled $artifact $DataDirectory $Port
