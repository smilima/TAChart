@echo off
setlocal enabledelayedexpansion
rem ---------------------------------------------------------------------------
rem  Register the TAChart design-time package with the IDE, and check that the
rem  library path is set.  Run once per machine, after build.bat.
rem
rem  Building puts the BPLs where the IDE looks (see build.bat).  Two more
rem  things are per-machine and are what this script is for:
rem
rem    1. The design-time package must be listed in Known Packages, or the
rem       components never reach the Tool Palette.  This script writes that.
rem
rem    2. The compiler must be told where the units live, or a project that
rem       uses the components fails with "F2613 Unit 'TAGraph' not found"
rem       even though they drop onto a form fine.  This script only CHECKS
rem       that - see the note at the bottom for why it does not write it.
rem
rem  Close the IDE first: it rewrites these settings when it exits and would
rem  overwrite anything written while it is running.
rem ---------------------------------------------------------------------------

rem --- Run from the script's own directory, whatever the caller's cwd ---
cd /d "%~dp0"

set "HERE=%~dp0"
for %%I in ("%HERE%..\src") do set "SRCDIR=%%~fI"
for %%I in ("%HERE%..\compat") do set "COMPATDIR=%%~fI"

rem --- Locate the installation (same discovery as build.bat) ------------------
set "RSVARS="
if defined TACHART_RSVARS if exist "%TACHART_RSVARS%" set "RSVARS=%TACHART_RSVARS%"
if not defined RSVARS if defined BDS if exist "%BDS%\bin\rsvars.bat" set "RSVARS=%BDS%\bin\rsvars.bat"
if not defined RSVARS (
  for %%H in (HKCU HKLM) do (
    for /f "delims=" %%K in ('reg query "%%H\Software\Embarcadero\BDS" 2^>nul') do (
      for /f "tokens=2,*" %%A in ('reg query "%%K" /v RootDir 2^>nul ^| findstr /i /c:"RootDir"') do (
        if exist "%%B\bin\rsvars.bat" (
          set "RSVARS=%%B\bin\rsvars.bat"
          for %%V in ("%%K") do set "BDSVER=%%~nxV"
        )
      )
    )
  )
)
if defined RSVARS set "RSVARS=%RSVARS:\binsvars.bat=insvars.bat%"

if not defined RSVARS (
  echo ERROR: no Embarcadero BDS installation found.  See build.bat.
  exit /b 1
)
call "%RSVARS%" >nul

rem  Version key, e.g. 37.0, taken from BDSCOMMONDIR's last segment when the
rem  registry walk did not supply it.
if not defined BDSVER for %%V in ("%BDSCOMMONDIR%") do set "BDSVER=%%~nxV"
rem  LIBSUFFIX AUTO turns 37.0 into 370.
set "SUFFIX=%BDSVER:.=%"

set "DTBPL=%BDSCOMMONDIR%\Bpl\TAChartDT%SUFFIX%.bpl"
echo Studio version : %BDSVER%
echo Design package : %DTBPL%

if not exist "%DTBPL%" (
  echo.
  echo ERROR: the design-time package is not built yet.
  echo        Run build.bat first.
  exit /b 1
)

tasklist /fi "imagename eq bds.exe" 2>nul | find /i "bds.exe" >nul
if not errorlevel 1 (
  echo.
  echo ERROR: the RAD Studio IDE is running.  It rewrites these settings on
  echo        exit and would discard what this script writes.  Close it first.
  exit /b 1
)

rem --- 0. Is what is installed built from the current source? ---------------
echo.
echo Freshness check:
set "STALE="
for /f "delims=" %%L in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0checkstale.ps1" -CommonDir "%BDSCOMMONDIR%" -Suffix "%SUFFIX%" -SourceRoot "%HERE%.." 2^>nul') do (
  echo %%L
  echo %%L | find /i "BEHIND" >nul && set "STALE=1"
  echo %%L | find /i "NEWER THAN" >nul && set "STALE=1"
  echo %%L | find /i "not built" >nul && set "STALE=1"
)

rem --- 1. Register the design-time package ------------------------------------
set "KP=HKCU\Software\Embarcadero\BDS\%BDSVER%\Known Packages"
reg add "%KP%" /v "%DTBPL%" /t REG_SZ /d "TAChart for Delphi and C++Builder - design time" /f >nul
if errorlevel 1 (
  echo ERROR: could not register the package.
  exit /b 1
)
echo.
echo Registered on the Tool Palette.

rem --- 2. Check the library path, per platform --------------------------------
echo.
echo Library path check:
set "MISSING="
for %%P in (Win32 Win64 Win64x) do (
  set "FOUND="
  reg query "HKCU\Software\Embarcadero\BDS\%BDSVER%\Library\%%P" /v "Search Path" 2>nul | findstr /i /c:"%SRCDIR%" >nul
  if not errorlevel 1 set "FOUND=1"
  if defined FOUND (
    echo    %%P  ok
  ) else (
    echo    %%P  MISSING
    set "MISSING=1"
  )
)

if not defined MISSING (
  if defined STALE (
    echo.
    echo Registered and the library path is set, but see the freshness check
    echo above - rebuild before using the components.
    exit /b 3
  )
  echo.
  echo All set.  Start the IDE.
  exit /b 0
)

echo.
echo ---------------------------------------------------------------------------
echo  The library path is not set for every platform above.  Projects that use
echo  the components will fail to compile there with:
echo      F2613 Unit 'TAGraph' not found
echo.
echo  Set it in the IDE - Tools ^> Options ^> Language ^> Delphi ^> Library -
echo  selecting each platform in turn and appending:
echo.
echo      %SRCDIR%
echo      %COMPATDIR%
echo.
echo  This script deliberately does not write it for you.  The setting lives in
echo  two places - the registry and EnvOptions.proj, which command-line msbuild
echo  reads - and writing only the registry leaves them disagreeing, which is a
echo  harder problem to spot than the missing path.  The Options dialog keeps
echo  both in step.
echo ---------------------------------------------------------------------------
exit /b 2
