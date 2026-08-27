@echo off
setlocal enabledelayedexpansion
rem ---------------------------------------------------------------------------
rem  Build the TAChart packages from the command line.
rem
rem    build                -> Win32 runtime + design time
rem    build Win64          -> Win64
rem    build all            -> Win32, Win64 and Win64x
rem
rem  The BPLs and DCPs are not copied anywhere afterwards: the projects already
rem  output to $(BDSCOMMONDIR)\Bpl and \Dcp, which is where the IDE looks for
rem  them.  rsvars.bat sets BDSCOMMONDIR from the local installation, so that
rem  path resolves correctly on any machine and for any Studio version - which
rem  is why this script finds rsvars.bat rather than hardcoding it.
rem
rem  Close the IDE first.  A loaded BPL is locked and the build fails with
rem  F2039; that error names the output file and not the cause.
rem ---------------------------------------------------------------------------

rem --- Run from the script's own directory, whatever the caller's cwd ---
cd /d "%~dp0"

rem --- Locate rsvars.bat ------------------------------------------------------
rem  Order: an explicit override, an already-configured environment, then the
rem  registry.  Never a hardcoded path - that is what breaks on another machine.
set "RSVARS="

if defined TACHART_RSVARS (
  if exist "%TACHART_RSVARS%" set "RSVARS=%TACHART_RSVARS%"
)

if not defined RSVARS if defined BDS (
  if exist "%BDS%\bin\rsvars.bat" set "RSVARS=%BDS%\bin\rsvars.bat"
)

rem  Registry: enumerate the installed BDS versions and take the newest whose
rem  RootDir actually exists.  reg query lists subkeys in ascending order, so
rem  the last match wins.
if not defined RSVARS (
  for %%H in (HKCU HKLM) do (
    for /f "delims=" %%K in ('reg query "%%H\Software\Embarcadero\BDS" 2^>nul') do (
      for /f "tokens=2,*" %%A in ('reg query "%%K" /v RootDir 2^>nul ^| findstr /i /c:"RootDir"') do (
        if exist "%%B\bin\rsvars.bat" set "RSVARS=%%B\bin\rsvars.bat"
      )
    )
  )
)

if defined RSVARS set "RSVARS=%RSVARS:\binsvars.bat=insvars.bat%"

if not defined RSVARS (
  echo.
  echo ERROR: could not find rsvars.bat.
  echo   No Embarcadero BDS installation was found in the registry, and neither
  echo   BDS nor TACHART_RSVARS points at one.
  echo   Set TACHART_RSVARS to the full path of rsvars.bat and run again, e.g.
  echo     set TACHART_RSVARS=C:\Program Files ^(x86^)\Embarcadero\Studio\23.0\bin\rsvars.bat
  exit /b 1
)

echo Using !RSVARS!
call "!RSVARS!"
if errorlevel 1 (
  echo ERROR: rsvars.bat failed.
  exit /b 1
)

rem --- Warn about the locked-BPL case before wasting a compile ---------------
tasklist /fi "imagename eq bds.exe" 2>nul | find /i "bds.exe" >nul
if not errorlevel 1 (
  echo.
  echo WARNING: the RAD Studio IDE is running.  A loaded design-time BPL is
  echo          locked, so the build will fail with F2039 on the Win32 output.
  echo          Close the IDE, or uninstall the TAChart packages, and retry.
  echo.
)

rem --- Platforms --------------------------------------------------------------
set "PLATFORMS=%~1"
if "%PLATFORMS%"=="" set "PLATFORMS=Win32"
if /i "%PLATFORMS%"=="all" set "PLATFORMS=Win32 Win64 Win64x"

for %%P in (%PLATFORMS%) do (
  for %%J in (TAChartRT TAChartDT) do (
    echo.
    echo === %%J : %%P ===
    msbuild %%J.dproj /t:Build /p:Config=Release /p:Platform=%%P /nologo /v:minimal
    if errorlevel 1 (
      echo.
      echo BUILD FAILED: %%J for %%P
      exit /b 1
    )
  )
)

echo.
echo Built %PLATFORMS%.
echo   BPLs -^> %BDSCOMMONDIR%\Bpl
echo   DCPs -^> %BDSCOMMONDIR%\Dcp
rem  A build can report success per project and still leave something behind -
rem  most often because the IDE held a BPL and only the .lib was written.  Say
rem  so here rather than let it surface later as a missing entry point.
for %%V in ("%BDSCOMMONDIR%") do set "BDSVER=%%~nxV"
set "SUFFIX=!BDSVER:.=!"
echo.
echo Freshness check:
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0checkstale.ps1" -CommonDir "%BDSCOMMONDIR%" -Suffix "!SUFFIX!" -SourceRoot "%~dp0.." 2>nul
if errorlevel 1 (
  echo.
  echo BUILD INCOMPLETE - see above.
  exit /b 1
)

echo.
echo To use the components in the IDE, the design-time package must also be
echo registered and the library path set - run install.bat once per machine.
exit /b 0
