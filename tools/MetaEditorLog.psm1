<#
.SYNOPSIS
    Decoding and parsing of MetaEditor command-line compiler logs.

.DESCRIPTION
    Kept in its own module because this logic decides whether a compile is
    reported as passing. tools\Test-MetaEditorLog.ps1 exercises it against
    synthetic logs in every encoding MetaEditor is known to emit.
#>

Set-StrictMode -Version Latest

function ConvertFrom-MetaEditorLogBytes {
    <#
    .SYNOPSIS
        Decodes a MetaEditor log. MetaEditor normally writes UTF-16LE with a
        BOM, but a BOM-less UTF-16LE log must not be mistaken for UTF-8 - that
        would silently yield an unparseable string and a false "no errors".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)

    if ($Bytes.Length -eq 0) { return '' }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    # No BOM: look for the NUL-in-every-odd-byte signature of UTF-16LE ASCII text.
    $probe = [Math]::Min($Bytes.Length, 512)
    $oddNul = 0
    $oddTotal = 0
    for ($i = 1; $i -lt $probe; $i += 2) {
        $oddTotal++
        if ($Bytes[$i] -eq 0) { $oddNul++ }
    }
    if ($oddTotal -gt 0 -and ($oddNul / [double]$oddTotal) -gt 0.7) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    return [System.Text.Encoding]::UTF8.GetString($Bytes)
}

function Get-MetaEditorCompileResult {
    <#
    .SYNOPSIS
        Extracts error and warning counts from a decoded MetaEditor log.

    .DESCRIPTION
        The log is trusted over MetaEditor's exit code, because some builds
        return 0 regardless. The trailing "Result: N errors, M warnings" line
        wins when present; otherwise the diagnostic lines are counted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $LogText)

    $lines = @($LogText -split "`r?`n" | Where-Object { $_.Trim() -ne '' })

    $errorLines = @($lines | Where-Object { $_ -match ':\s*error\b' })
    $warnLines = @($lines | Where-Object { $_ -match ':\s*warning\b' })

    # "Result: 1 errors, 2 warnings, 1234 msec elapsed" - digits BEFORE the word,
    # which is what distinguishes it from a diagnostic line like "error 236:".
    $summary = @($lines | Where-Object { $_ -match '\d+\s+error' }) | Select-Object -Last 1

    $errCount = $errorLines.Count
    $warnCount = $warnLines.Count
    if ($summary) {
        if ($summary -match '(\d+)\s+error') { $errCount = [int]$Matches[1] }
        if ($summary -match '(\d+)\s+warning') { $warnCount = [int]$Matches[1] }
    }

    return [pscustomobject]@{
        Lines        = $lines
        ErrorLines   = $errorLines
        WarningLines = $warnLines
        SummaryLine  = $summary
        ErrorCount   = $errCount
        WarningCount = $warnCount
    }
}

Export-ModuleMember -Function ConvertFrom-MetaEditorLogBytes, Get-MetaEditorCompileResult
