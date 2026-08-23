@echo off
rem Build the TAChart packages from the command line.
rem   build            -> Win32 runtime + design time
rem   build Win64      -> Win64 runtime + design time
rem Close the IDE first (or uninstall the TAChart packages) - a loaded BPL is
rem locked and the build fails with F2039.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
set PLAT=%1
if "%PLAT%"=="" set PLAT=Win32
msbuild TAChartRT.dproj /t:Build /p:Config=Release /p:Platform=%PLAT% /nologo /v:minimal
if errorlevel 1 exit /b 1
msbuild TAChartDT.dproj /t:Build /p:Config=Release /p:Platform=%PLAT% /nologo /v:minimal
