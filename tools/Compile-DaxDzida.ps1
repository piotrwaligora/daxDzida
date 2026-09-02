<#
.SYNOPSIS
    Compiles the daxDzida Phase 1 Expert Advisor with MetaEditor, from the
    command line, without duplicating any source file.

.DESCRIPTION
    1. Locates the MT5 data folder belonging to the given MetaEditor install.
    2. Ensures the three junctions described in docs/MT5_SETUP.md exist, so the
       terminal compiles THE REPOSITORY'S files rather than a copy.
    3. Runs MetaEditor in command-line mode and captures its compiler log into
       build\metaeditor-compile.log.
    4. Reports errors and warnings separately and exits non-zero on any error.
    5. Optionally runs the deterministic regression suite if a C++ compiler and
       Python are available on this machine.

    It never edits source to make compilation pass. That is a human decision.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compile-DaxDzida.ps1

.EXAMPLE
    .\tools\Compile-DaxDzida.ps1 -SkipTests -Verbose
#>
[CmdletBinding()]
param(
    [string] $MetaEditor = 'C:\Program Files\Tickmill Europe MT5 Terminal\MetaEditor64.exe',
    [string] $DataFolder,
    [switch] $SkipTests,
    [switch] $NoLink
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MetaEditorLog.psm1') -Force

$RepoRoot = Split-Path -Parent $PSScriptRoot
$EaRelative = 'Experts\daxDzida\DaxDzida_Phase1.mq5'
$BuildDir = Join-Path $RepoRoot 'build'
$LogPath = Join-Path $BuildDir 'metaeditor-compile.log'

function Write-Section([string] $Text) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * 68) -ForegroundColor DarkGray
}

function Fail([string] $Message) {
    Write-Host ''
    Write-Host "FAILED: $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 1. tools --
Write-Section 'daxDzida - MQL5 command-line compile'

if (-not (Test-Path -LiteralPath $MetaEditor)) {
    Fail "MetaEditor not found at '$MetaEditor'. Pass -MetaEditor <path>."
}
$MetaEditor = (Resolve-Path -LiteralPath $MetaEditor).Path
$TerminalDir = Split-Path -Parent $MetaEditor
Write-Host "MetaEditor : $MetaEditor"
Write-Host "Repository : $RepoRoot"

# ---------------------------------------------------- 2. find data folder --
function Find-DataFolder([string] $InstallDir) {
    # Portable mode keeps MQL5 next to the executable.
    $portable = Join-Path $InstallDir 'MQL5'
    if (Test-Path -LiteralPath $portable) { return $InstallDir }

    $root = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
    if (-not (Test-Path -LiteralPath $root)) { return $null }

    $matches = @()
    foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
        $origin = Join-Path $dir.FullName 'origin.txt'
        if (-not (Test-Path -LiteralPath $origin)) { continue }
        # origin.txt is written by the terminal and holds its install path.
        $content = (Get-Content -LiteralPath $origin -Raw -ErrorAction SilentlyContinue)
        if ($null -eq $content) { continue }
        $content = ($content -replace "`0", '').Trim()
        if ($content -and $InstallDir -and
            $content.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) {
            $matches += $dir.FullName
        }
    }
    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) {
        Write-Host 'Multiple data folders claim this install:' -ForegroundColor Yellow
        $matches | ForEach-Object { Write-Host "  $_" }
    }
    return $null
}

if (-not $DataFolder) { $DataFolder = Find-DataFolder $TerminalDir }

if (-not $DataFolder -or -not (Test-Path -LiteralPath (Join-Path $DataFolder 'MQL5'))) {
    Write-Host ''
    Write-Host 'Could not identify the MT5 data folder for this terminal.' -ForegroundColor Yellow
    Write-Host 'Candidates found under %APPDATA%\MetaQuotes\Terminal:' -ForegroundColor Yellow
    $root = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
    if (Test-Path -LiteralPath $root) {
        Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
            $o = Join-Path $_.FullName 'origin.txt'
            $t = if (Test-Path -LiteralPath $o) { (Get-Content -LiteralPath $o -Raw) -replace "`0", '' } else { '(no origin.txt)' }
            Write-Host ("  {0}   <- {1}" -f $_.FullName, $t.Trim())
        }
    }
    Fail 'Open MT5 -> File -> Open Data Folder and re-run with -DataFolder "<that path>".'
}

$Mql5Dir = Join-Path $DataFolder 'MQL5'
Write-Host "Data folder: $DataFolder"

# -------------------------------------------------------- 3. the junctions --
$Links = @(
    @{ Link = Join-Path $Mql5Dir 'Experts\daxDzida'; Target = Join-Path $RepoRoot 'MQL5\Experts\daxDzida' },
    @{ Link = Join-Path $Mql5Dir 'Include\daxDzida'; Target = Join-Path $RepoRoot 'MQL5\Include\daxDzida' },
    @{ Link = Join-Path $Mql5Dir 'Presets\daxDzida'; Target = Join-Path $RepoRoot 'MQL5\Presets' }
)

if (-not $NoLink) {
    Write-Section 'Junctions (repository files, not copies)'
    foreach ($l in $Links) {
        $link = $l.Link
        $target = (Resolve-Path -LiteralPath $l.Target).Path

        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            $linkType = $null
            if ($item.PSObject.Properties.Name -contains 'LinkType') { $linkType = $item.LinkType }

            if ($linkType -eq 'Junction' -or $linkType -eq 'SymbolicLink') {
                $actual = $null
                if ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
                    $actual = @($item.Target)[0]
                }
                if ($actual -and $actual.TrimEnd('\') -ine $target.TrimEnd('\')) {
                    Fail "'$link' is a junction to '$actual' but should point at '$target'. Remove it and re-run."
                }
                Write-Host "  ok    $link"
            }
            else {
                Fail ("'$link' is a REAL directory, which means MT5 holds a COPY of the sources. " +
                      'Delete it and re-run so the repository is compiled directly.')
            }
        }
        else {
            $parent = Split-Path -Parent $link
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
            Write-Host "  created  $link  ->  $target" -ForegroundColor Green
        }
    }
}
else {
    Write-Host 'Junction setup skipped (-NoLink).'
}

# ------------------------------------------------------------- 4. compile --
Write-Section 'Compiling'

$EaPath = Join-Path $Mql5Dir $EaRelative
if (-not (Test-Path -LiteralPath $EaPath)) { Fail "EA source not visible at '$EaPath'." }

$Ex5Path = [System.IO.Path]::ChangeExtension($EaPath, '.ex5')
if (Test-Path -LiteralPath $Ex5Path) { Remove-Item -LiteralPath $Ex5Path -Force }
if (-not (Test-Path -LiteralPath $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null }
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

$compileArgs = @(
    "/compile:`"$EaPath`"",
    "/inc:`"$Mql5Dir`"",
    "/log:`"$LogPath`""
)
Write-Host ('Command: "{0}" {1}' -f $MetaEditor, ($compileArgs -join ' '))

$proc = Start-Process -FilePath $MetaEditor -ArgumentList $compileArgs `
                      -Wait -PassThru -NoNewWindow
$exitCode = $proc.ExitCode

Start-Sleep -Milliseconds 300
$logText = ''
if (Test-Path -LiteralPath $LogPath) {
    $logText = ConvertFrom-MetaEditorLogBytes -Bytes ([System.IO.File]::ReadAllBytes($LogPath))
}

if (-not $logText.Trim()) {
    Write-Host "MetaEditor exit code: $exitCode" -ForegroundColor Yellow
    Fail "MetaEditor produced no log at '$LogPath'. It may not have run."
}

$parsed = Get-MetaEditorCompileResult -LogText $logText

Write-Section 'Compiler log'
$parsed.Lines | ForEach-Object { Write-Host "  $_" }

Write-Section 'Result'
Write-Host "MetaEditor exit code : $exitCode"
Write-Host "Log file             : $LogPath"
if ($parsed.SummaryLine) { Write-Host "Summary line         : $($parsed.SummaryLine.Trim())" }

# Trust the log, not the exit code: some MetaEditor builds always return 0.
$errCount = $parsed.ErrorCount
$warnCount = $parsed.WarningCount

Write-Host "Errors               : $errCount"
Write-Host "Warnings             : $warnCount"

if ($warnCount -gt 0) {
    Write-Host ''
    Write-Host 'WARNINGS (reported separately, not fatal):' -ForegroundColor Yellow
    if ($parsed.WarningLines.Count -gt 0) {
        $parsed.WarningLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    }
}

if ($errCount -gt 0) {
    Write-Host ''
    Write-Host 'ERRORS:' -ForegroundColor Red
    if ($parsed.ErrorLines.Count -gt 0) {
        $parsed.ErrorLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    Fail "$errCount compilation error(s). The .ex5 was not produced."
}

if (-not (Test-Path -LiteralPath $Ex5Path)) {
    Fail "Log reported no errors but '$Ex5Path' was not produced."
}
Write-Host "Compiled binary      : $Ex5Path" -ForegroundColor Green

# --------------------------------------------------------------- 5. tests --
if (-not $SkipTests) {
    Write-Section 'Deterministic regression suite'

    $gpp = Get-Command g++ -ErrorAction SilentlyContinue
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }

    $ranSomething = $false

    if ($gpp) {
        $testsDir = Join-Path $RepoRoot 'tests'
        $outDir = Join-Path $testsDir 'build'
        if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $exe = Join-Path $outDir 'test_dz.exe'
        & $gpp.Source '-std=c++11' '-O1' '-Wall' '-Wextra' '-Wno-unused-parameter' `
            '-o' $exe (Join-Path $testsDir 'test_dz.cpp')
        if ($LASTEXITCODE -ne 0) { Fail 'Regression tests did not compile.' }
        & $exe
        if ($LASTEXITCODE -ne 0) { Fail 'Deterministic regression tests FAILED.' }
        $ranSomething = $true
    }
    else {
        Write-Host 'g++ not found on this machine - behavioural tests not run here.' -ForegroundColor Yellow
        Write-Host 'They are run in the Linux workspace via ./tests/run_tests.sh.' -ForegroundColor Yellow
    }

    if ($py) {
        & $py.Source (Join-Path $RepoRoot 'tests\check_csv_columns.py')
        if ($LASTEXITCODE -ne 0) { Fail 'Research CSV schema check FAILED.' }
        & $py.Source (Join-Path $RepoRoot 'MQL5\Presets\generate_presets.py') '--check'
        if ($LASTEXITCODE -ne 0) { Fail 'Pre-registered presets no longer match the generator.' }
        $ranSomething = $true
    }
    else {
        Write-Host 'Python not found on this machine - schema/preset checks not run here.' -ForegroundColor Yellow
    }

    # This one needs nothing but PowerShell itself, so it always runs.
    & (Join-Path $PSScriptRoot 'Test-MetaEditorLog.ps1')
    if ($LASTEXITCODE -ne 0) { Fail 'MetaEditor log parser tests FAILED.' }
    $ranSomething = $true

    if (-not $ranSomething) {
        Write-Host 'No test tooling available on Windows; rely on the Linux workspace suite.' -ForegroundColor Yellow
    }
}
else {
    Write-Host ''
    Write-Host 'Tests skipped (-SkipTests).'
}

Write-Section 'DONE - 0 errors'
exit 0
