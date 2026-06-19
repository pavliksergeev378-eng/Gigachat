@echo off
chcp 65001 >nul
cd /d "%~dp0"

if exist "n8n-proxy-auth.local.cmd" (
    echo Loading n8n proxy auth settings from n8n-proxy-auth.local.cmd
    call "n8n-proxy-auth.local.cmd"
    echo.
)

echo Starting n8n proxy on http://localhost:8777
echo n8n upstream: http://130.100.92.170:5678
echo.

where py >nul 2>nul
if %errorlevel%==0 (
    echo Using Python launcher: py -3
    py -3 n8n-proxy-8777.py
    goto END
)

where python >nul 2>nul
if %errorlevel%==0 (
    echo Using Python: python
    python n8n-proxy-8777.py
    goto END
)

where node >nul 2>nul
if %errorlevel%==0 (
    echo Python not found. Using Node.js fallback.
    node n8n-proxy-8777.js
    goto END
)

echo ERROR: Neither Python nor Node.js was found.
echo Install Python or Node.js, then run this file again.

:END
echo.
echo Proxy stopped.
echo If it stopped immediately, read the error above.
pause
