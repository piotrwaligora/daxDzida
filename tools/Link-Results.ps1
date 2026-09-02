<#
.SYNOPSIS
    Makes MT5 research output readable from inside the repository.

.DESCRIPTION
    The EA writes its CSVs to the shared terminal folder
    %APPDATA%\MetaQuotes\Terminal\Common\Files, which every tester agent can
    reach. That folder is outside the repository, so each result would otherwise
    have to be copied by hand before it can be reviewed.

    This creates a junction:

        <repo>\results   ->   %APPDATA%\MetaQuotes\Terminal\Common\Files

    Nothing is copied and nothing is written to that folder by this script; it is
    a read path only. `results/` is git-ignored, so no MT5 output can be
    committed by accident.

    Optional convenience. Run it once. Remove it any time with:

        (Get-Item <repo>\results).Delete()

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Link-Results.ps1
#>
[CmdletBinding()]
param([string] $CommonFiles)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Link = Join-Path $RepoRoot 'results'

if (-not $CommonFiles) {
    $CommonFiles = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
}

if (-not (Test-Path -LiteralPath $CommonFiles)) {
    Write-Host "Common\Files not found at '$CommonFiles'." -ForegroundColor Yellow
    Write-Host 'It is created the first time an EA writes there. Run a test first,' -ForegroundColor Yellow
    Write-Host 'or pass -CommonFiles "<path>".' -ForegroundColor Yellow
    exit 1
}
$CommonFiles = (Resolve-Path -LiteralPath $CommonFiles).Path

if (Test-Path -LiteralPath $Link) {
    $item = Get-Item -LiteralPath $Link -Force
    $linkType = $null
    if ($item.PSObject.Properties.Name -contains 'LinkType') { $linkType = $item.LinkType }

    if ($linkType -eq 'Junction' -or $linkType -eq 'SymbolicLink') {
        $actual = $null
        if ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
            $actual = @($item.Target)[0]
        }
        if ($actual -and $actual.TrimEnd('\') -ieq $CommonFiles.TrimEnd('\')) {
            Write-Host "already linked: $Link  ->  $CommonFiles" -ForegroundColor Green
            exit 0
        }
        Write-Host "'$Link' already points at '$actual'." -ForegroundColor Red
        Write-Host 'Remove it and re-run.' -ForegroundColor Red
        exit 1
    }

    Write-Host "'$Link' exists as a real directory - not touching it." -ForegroundColor Red
    Write-Host 'Move or delete it and re-run.' -ForegroundColor Red
    exit 1
}

New-Item -ItemType Junction -Path $Link -Target $CommonFiles | Out-Null
Write-Host "created: $Link  ->  $CommonFiles" -ForegroundColor Green
Write-Host 'MT5 research CSVs are now readable from inside the repository.'
exit 0
