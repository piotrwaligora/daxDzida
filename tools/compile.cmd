@echo off
REM One-command compile for the daxDzida Phase 1 EA.
REM Usage:  tools\compile.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compile-DaxDzida.ps1" %*
