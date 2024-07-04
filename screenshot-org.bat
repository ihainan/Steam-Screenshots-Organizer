@echo off
setlocal
echo Running "%~dp0screenshot-org.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0screenshot-org.ps1" 

pause
endlocal