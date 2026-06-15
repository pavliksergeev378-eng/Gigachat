@echo off
REM ============================================================================
REM Start GigaChat local HTTP server (Caddy).
REM
REM Double-click:
REM   - Caddy listens on http://localhost:8765
REM   - Open the URL manually in any browser (HTTP-mode works with any
REM     version of Chrome, Yandex, Edge, Firefox, etc.)
REM
REM To stop: close this window (or Ctrl+C). No separate Stop.bat needed.
REM
REM ASCII-only (cmd cp866 in RU locale breaks Cyrillic in .bat).
REM ============================================================================

cd /d "%~dp0"
title GigaChat Server

REM --- Auto-update from GitHub before serving. Caddy serves the LOCAL copy,
REM     so without "git pull" the server keeps showing OLD versions after a
REM     push. Non-fatal: if git is missing / offline / conflict, we still
REM     launch Caddy with whatever is on disk.
where git >nul 2>&1
if %errorlevel%==0 if exist "%~dp0.git" (
    echo Updating from GitHub ^(git pull^)...
    git pull origin main
    echo.
)

if not exist "%~dp0caddy.exe" (
    echo.
    echo ERROR: caddy.exe not found in %~dp0
    echo Download fresh ZIP from GitHub - caddy.exe must be next to this .bat
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0Caddyfile" (
    echo.
    echo ERROR: Caddyfile not found in %~dp0
    echo.
    pause
    exit /b 1
)

echo ============================================
echo  GigaChat Server
echo  ----
echo  URL:  http://localhost:8765/
echo  ----
echo  Open this URL in your browser manually.
echo  Close this window to stop the server.
echo ============================================
echo.

REM Run Caddy with explicit full paths. Logs stream to this window.
"%~dp0caddy.exe" run --config "%~dp0Caddyfile"

echo.
echo Caddy stopped.
pause
