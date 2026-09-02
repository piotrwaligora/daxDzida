<#
.SYNOPSIS
    Tests for the MetaEditor log decoder/parser.

.DESCRIPTION
    A wrong parser here would report "0 errors" on a broken build, which is the
    worst possible failure mode for this repository. Run with:

        pwsh -NoProfile -File tools\Test-MetaEditorLog.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MetaEditorLog.psm1') -Force

$script:Checks = 0
$script:Fails = 0

function Check([string] $Name, [bool] $Condition) {
    $script:Checks++
    if ($Condition) { Write-Host "  ok   $Name" }
    else { $script:Fails++; Write-Host "  FAIL $Name" -ForegroundColor Red }
}

$clean = @(
    'MetaEditor 5 build 4885 started',
    "Compiling 'DaxDzida_Phase1.mq5'",
    'Result: 0 errors, 0 warnings, 812 msec elapsed'
) -join "`r`n"

$withErrors = @(
    'MetaEditor 5 build 4885 started',
    "Compiling 'DaxDzida_Phase1.mq5'",
    'C:\x\DaxDzida_Phase1.mq5(123,45) : error 236: ' + "'foo' - undeclared identifier",
    'C:\x\DaxDzida_Phase1.mq5(140,3) : error 100: semicolon expected',
    'C:\x\DaxDzida_Phase1.mq5(200,10) : warning 43: possible loss of data due to type conversion',
    'Result: 2 errors, 1 warnings, 903 msec elapsed'
) -join "`r`n"

$warnOnly = @(
    "Compiling 'DaxDzida_Phase1.mq5'",
    'C:\x\DaxDzida_Phase1.mq5(200,10) : warning 43: possible loss of data due to type conversion',
    'Result: 0 errors, 1 warnings, 700 msec elapsed'
) -join "`r`n"

Write-Host 'MetaEditor log parser tests'
Write-Host '==========================='

$r = Get-MetaEditorCompileResult -LogText $clean
Check 'clean log reports 0 errors' ($r.ErrorCount -eq 0)
Check 'clean log reports 0 warnings' ($r.WarningCount -eq 0)

$r = Get-MetaEditorCompileResult -LogText $withErrors
Check 'error log reports 2 errors' ($r.ErrorCount -eq 2)
Check 'error log reports 1 warning' ($r.WarningCount -eq 1)
Check 'error lines captured' ($r.ErrorLines.Count -eq 2)
Check 'warning lines captured' ($r.WarningLines.Count -eq 1)
Check 'a diagnostic line is not mistaken for the summary' ($r.SummaryLine -like 'Result:*')

$r = Get-MetaEditorCompileResult -LogText $warnOnly
Check 'warning-only log reports 0 errors' ($r.ErrorCount -eq 0)
Check 'warning-only log reports 1 warning' ($r.WarningCount -eq 1)

# Counting must still work if MetaEditor omits the summary line entirely.
$noSummary = 'C:\x\a.mq5(1,1) : error 1: boom'
$r = Get-MetaEditorCompileResult -LogText $noSummary
Check 'errors counted without a summary line' ($r.ErrorCount -eq 1)

$r = Get-MetaEditorCompileResult -LogText ''
Check 'empty log reports 0 errors' ($r.ErrorCount -eq 0)

# --- encodings -------------------------------------------------------------
$u16bom = [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($withErrors)
$r = Get-MetaEditorCompileResult -LogText (ConvertFrom-MetaEditorLogBytes -Bytes $u16bom)
Check 'UTF-16LE with BOM decodes and parses' ($r.ErrorCount -eq 2)

$u16nobom = [System.Text.Encoding]::Unicode.GetBytes($withErrors)
$r = Get-MetaEditorCompileResult -LogText (ConvertFrom-MetaEditorLogBytes -Bytes $u16nobom)
Check 'UTF-16LE without BOM is not mistaken for UTF-8' ($r.ErrorCount -eq 2)

$u8bom = [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($withErrors)
$r = Get-MetaEditorCompileResult -LogText (ConvertFrom-MetaEditorLogBytes -Bytes $u8bom)
Check 'UTF-8 with BOM decodes and parses' ($r.ErrorCount -eq 2)

$u8 = [System.Text.Encoding]::UTF8.GetBytes($withErrors)
$r = Get-MetaEditorCompileResult -LogText (ConvertFrom-MetaEditorLogBytes -Bytes $u8)
Check 'plain UTF-8 decodes and parses' ($r.ErrorCount -eq 2)

Check 'empty byte array decodes to empty string' ((ConvertFrom-MetaEditorLogBytes -Bytes ([byte[]]@())) -eq '')

Write-Host '==========================='
Write-Host "checks: $script:Checks   failures: $script:Fails"
if ($script:Fails -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
