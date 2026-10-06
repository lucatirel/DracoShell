@echo off
setlocal
cd /d "%~dp0"

echo.
echo === DRACO EMERGENCY CLEAN RESET ===
echo This runs PowerShell with -NoProfile so a broken DRACO profile cannot interfere.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"

echo.
echo If CLEAN RESET COMPLETE is shown above, open a NEW Windows PowerShell tab.
echo.
pause

