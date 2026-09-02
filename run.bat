@echo off
rem SPDX-License-Identifier: MIT
rem
rem   run.bat            format, build, then start the REPL
rem   run.bat --build    format and build only
rem   run.bat --check    fail if any source is unformatted (for CI)
rem   run.bat --clean    remove build\
rem
rem Needs NASM plus one of: lld-link (LLVM), link.exe (MSVC), gcc (mingw-w64),
rem GoLink. The first three also need kernel32.lib from the Windows SDK.
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "CORE=%ROOT%src\core"
set "OUT=%ROOT%build"
set "BIN=%OUT%\tsafoshi.exe"

set "PY="
for %%P in (python.exe py.exe python3.exe) do (
    if not defined PY if not "%%~$PATH:P"=="" set "PY=%%~$PATH:P"
)

if /i "%~1"=="--clean" (
    if exist "%OUT%" rmdir /s /q "%OUT%"
    echo cleaned
    exit /b 0
)

if /i "%~1"=="--check" (
    if not defined PY echo run.bat: --check needs python & exit /b 127
    "!PY!" "%ROOT%tools\prettier.py" --check "%ROOT%src"
    exit /b !errorlevel!
)

where nasm >nul 2>&1
if errorlevel 1 (
    echo run.bat: nasm not found on PATH ^(winget install NASM.NASM^)
    exit /b 127
)

if defined PY "!PY!" "%ROOT%tools\prettier.py" -q "%ROOT%src"

if not exist "%OUT%" mkdir "%OUT%"

set "OBJS="
for %%F in ("%ROOT%src\main.asm" "%CORE%\*.asm" "%ROOT%src\windows\input.asm") do (
    nasm -f win64 -g -I"%CORE%" "%%~fF" -o "%OUT%\%%~nF.obj"
    if errorlevel 1 exit /b 1
    set "OBJS=!OBJS! "%OUT%\%%~nF.obj""
)

rem newest installed SDK wins: the loop enumerates in version order
set "K32="
for /d %%D in ("%ProgramFiles(x86)%\Windows Kits\10\Lib\*") do (
    if exist "%%D\um\x64\kernel32.Lib" set "K32=%%D\um\x64\kernel32.Lib"
)

where lld-link >nul 2>&1
if not errorlevel 1 if defined K32 (
    echo linking with lld-link
    lld-link /nologo /subsystem:console /entry:_start /nodefaultlib !OBJS! "!K32!" /out:"%BIN%"
    if errorlevel 1 exit /b 1
    goto :linked
)

where link.exe >nul 2>&1
if not errorlevel 1 if defined K32 (
    echo linking with link.exe
    link /nologo /subsystem:console /entry:_start /nodefaultlib !OBJS! "!K32!" /out:"%BIN%"
    if errorlevel 1 exit /b 1
    goto :linked
)

where gcc >nul 2>&1
if not errorlevel 1 (
    echo linking with gcc
    gcc -nostdlib -Wl,-e,_start -o "%BIN%" !OBJS! -lkernel32
    if errorlevel 1 exit /b 1
    goto :linked
)

where golink >nul 2>&1
if not errorlevel 1 (
    echo linking with GoLink
    golink /console /entry _start !OBJS! kernel32.dll
    if errorlevel 1 exit /b 1
    move /y tsafoshi.exe "%BIN%" >nul
    goto :linked
)

echo run.bat: no usable linker found.
echo   LLVM ^(lld-link^), Visual Studio Build Tools ^(link.exe^),
echo   MSYS2 / w64devkit ^(gcc^), or GoLink.
exit /b 127

:linked
echo built %BIN%
if /i "%~1"=="--build" exit /b 0
"%BIN%"
exit /b %errorlevel%
