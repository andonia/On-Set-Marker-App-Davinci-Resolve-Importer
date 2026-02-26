@echo off
:: DaVinci Resolve Marker Importer — Windows installer

set "SCRIPT=marker_importer.lua"
set "DEST=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility"

if not exist "%SCRIPT%" (
    echo Error: %SCRIPT% not found.
    echo Run this script from the same folder as %SCRIPT%.
    pause
    exit /b 1
)

if not exist "%DEST%" mkdir "%DEST%"

copy /Y "%SCRIPT%" "%DEST%\%SCRIPT%" >nul

echo Installed: %DEST%\%SCRIPT%
echo.
echo In DaVinci Resolve, run via:
echo   Workspace ^> Scripts ^> Utility ^> marker_importer
echo.
pause
