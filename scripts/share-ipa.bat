@echo off
rem Shares the latest SpectraSigner build over a temporary Cloudflare tunnel, so you can
rem download the .ipa on your phone (e.g. Feather -> Import from URL).
rem
rem Requires gh (logged in), python and cloudflared on PATH.
rem Usage: share-ipa.bat [run-id]    (defaults to the newest successful build on main)
setlocal

set "REPO=yooblueyyy/SpectraSigner"
set "PORT=8765"
set "WORK=%TEMP%\SpectraSignerShare"
set "SERVE=%WORK%\files"
set "LOG=%WORK%\cloudflared.log"
set "PIDS=%TEMP%\SpectraSignerShare.pids"

for %%t in (gh python cloudflared) do (
	where %%t >nul 2>nul || (echo %%t was not found on PATH. & exit /b 1)
)

rem Stop anything left over from a previous run whose window was closed.
if exist "%PIDS%" (
	for /f %%p in (%PIDS%) do taskkill /pid %%p /t /f >nul 2>nul
	del "%PIDS%"
)

set "RUN=%~1"
if not defined RUN (
	for /f %%i in ('gh run list --repo %REPO% --workflow build.yml --branch main --status success --limit 1 --json databaseId -q ".[0].databaseId"') do set "RUN=%%i"
)
if not defined RUN (echo No successful build found. & exit /b 1)

if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%SERVE%"

echo Downloading build %RUN%...
gh run download %RUN% --repo %REPO% -n SpectraSigner -D "%SERVE%" || exit /b 1
if not exist "%SERVE%\SpectraSigner.ipa" (echo The build has no SpectraSigner.ipa. & exit /b 1)

rem Both run hidden in their own consoles: if they inherited this console's output handles,
rem the "for /f" lines below would wait for them to exit.
echo Starting local server on port %PORT%...
for /f %%p in ('powershell -NoProfile -Command "(Start-Process python -ArgumentList '-m','http.server','%PORT%','--bind','127.0.0.1' -WorkingDirectory '%SERVE%' -WindowStyle Hidden -PassThru).Id"') do set "SERVER_PID=%%p"
>>"%PIDS%" echo %SERVER_PID%

echo Opening Cloudflare tunnel...
for /f %%p in ('powershell -NoProfile -Command "(Start-Process cloudflared -ArgumentList 'tunnel','--no-autoupdate','--url','http://127.0.0.1:%PORT%','--logfile','%LOG%' -WindowStyle Hidden -PassThru).Id"') do set "TUNNEL_PID=%%p"
>>"%PIDS%" echo %TUNNEL_PID%

set "URL="
for /f %%u in ('powershell -NoProfile -Command "$end = (Get-Date).AddSeconds(60); while ((Get-Date) -lt $end) { $m = Select-String -Path '%LOG%' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($m) { $m.Matches[0].Value; break }; Start-Sleep 1 }"') do set "URL=%%u"
if not defined URL (
	echo The tunnel didn't come up. See %LOG%
	goto stop
)

set "LINK=%URL%/SpectraSigner.ipa"
echo %LINK%| clip

echo.
echo ================================================================
echo  Download link (copied to clipboard):
echo.
echo    %LINK%
echo.
echo  Feather: Library ^> + ^> Import from URL, then paste the link.
echo  It can take ~30 seconds before the link starts working.
echo ================================================================
echo.
echo Sharing build %RUN%.

if /i "%SHARE_IPA_WAIT%"=="tunnel" (
	powershell -NoProfile -Command "Wait-Process -Id %TUNNEL_PID%"
) else (
	echo Press any key to stop sharing.
	pause >nul
)

:stop
for %%p in (%TUNNEL_PID% %SERVER_PID%) do taskkill /pid %%p /t /f >nul 2>nul
if exist "%PIDS%" del "%PIDS%"
echo Stopped.
endlocal
