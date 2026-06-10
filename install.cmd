@echo off
REM Fabi installer for Windows CMD.
REM
REM Usage (from cmd.exe):
REM   curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.cmd -o install.cmd && install.cmd && del install.cmd
REM
REM This is a thin wrapper: it just runs the PowerShell installer (install.ps1),
REM which does the real work (native Windows install by default: downloads the
REM windows-x64-cuda runtime, no WSL). All the FABI_* environment variables
REM documented in install.ps1 are honored.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.ps1 | iex"
endlocal
