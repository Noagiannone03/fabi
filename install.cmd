@echo off
REM Fabi installer for Windows CMD.
REM
REM Usage (from cmd.exe):
REM   curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.cmd -o install.cmd && install.cmd && del install.cmd
REM
REM This is a thin wrapper: it just runs the PowerShell installer (install.ps1),
REM which does the real work (WSL detection + Linux runtime install). All the
REM FABI_* environment variables documented in install.ps1 are honored.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.ps1 | iex"
endlocal
