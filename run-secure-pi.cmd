@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "IMAGE=%PI_SECURE_IMAGE%"
if not defined IMAGE set "IMAGE=secure-pi:latest"

set "PI_VERSION=%PI_VERSION%"
if not defined PI_VERSION set "PI_VERSION=latest"

set "PI_AUTH_FILE=%PI_AUTH_FILE%"
if not defined PI_AUTH_FILE set "PI_AUTH_FILE=%USERPROFILE%\.secure-pi\auth.json"

if /I "%~1"=="-h" goto :help
if /I "%~1"=="--help" goto :help
if /I "%~1"=="/?" goto :help

if "%~1"=="" (
  set "REPO_PATH=%CD%"
) else (
  set "REPO_PATH=%~1"
  shift
)

if not exist "%REPO_PATH%\" (
  echo Repository path does not exist: %REPO_PATH%
  exit /b 1
)

for %%I in ("%REPO_PATH%") do set "REPO_PATH=%%~fI"

for %%I in ("%PI_AUTH_FILE%") do (
  set "PI_AUTH_FILE=%%~fI"
  set "PI_AUTH_DIR=%%~dpI"
)
if not exist "%PI_AUTH_DIR%" mkdir "%PI_AUTH_DIR%"
if not exist "%PI_AUTH_FILE%" (
  >"%PI_AUTH_FILE%" echo {}
)

set "PI_ARGS="
:collect_args
if "%~1"=="" goto :args_done
set "PI_ARGS=!PI_ARGS! %1"
shift
goto :collect_args
:args_done

set "NEED_BUILD=0"
if /I "%PI_REBUILD%"=="1" set "NEED_BUILD=1"

if "%NEED_BUILD%"=="0" (
  docker image inspect "%IMAGE%" >nul 2>nul
  if errorlevel 1 set "NEED_BUILD=1"
)

if "%NEED_BUILD%"=="1" (
  echo [secure-pi] Building image %IMAGE% ^(PI_VERSION=%PI_VERSION%^) 
  docker build --build-arg PI_VERSION=%PI_VERSION% -t "%IMAGE%" "%SCRIPT_DIR%"
  if errorlevel 1 exit /b 1
)

if not defined PI_PIDS_LIMIT set "PI_PIDS_LIMIT=512"
if not defined PI_MEMORY_LIMIT set "PI_MEMORY_LIMIT=4g"
if not defined PI_CPU_LIMIT set "PI_CPU_LIMIT=2"
if not defined PI_ALLOW_CONTEXT_FILES set "PI_ALLOW_CONTEXT_FILES=1"
if not defined PI_DISABLE_BASH_TOOL set "PI_DISABLE_BASH_TOOL=0"

set "NETWORK_ARGS="
if /I "%PI_DOCKER_NETWORK_NONE%"=="1" set "NETWORK_ARGS=--network none"

docker run --rm -it ^
  --workdir /workspace ^
  --user 10001:10001 ^
  --mount "type=bind,src=%REPO_PATH%,dst=/workspace" ^
  --mount "type=bind,src=%PI_AUTH_FILE%,dst=/opt/pi-secure/auth.json" ^
  --read-only ^
  --tmpfs /tmp:rw,noexec,nosuid,size=256m ^
  --tmpfs /home/pi/.pi:rw,nosuid,uid=10001,gid=10001,mode=0700,size=256m ^
  --cap-drop ALL ^
  --security-opt no-new-privileges:true ^
  --pids-limit %PI_PIDS_LIMIT% ^
  --memory %PI_MEMORY_LIMIT% ^
  --cpus %PI_CPU_LIMIT% ^
  -e PI_OFFLINE=1 ^
  -e PI_SKIP_VERSION_CHECK=1 ^
  -e PI_TELEMETRY=0 ^
  -e PI_ALLOW_CONTEXT_FILES=%PI_ALLOW_CONTEXT_FILES% ^
  -e PI_DISABLE_BASH_TOOL=%PI_DISABLE_BASH_TOOL% ^
  %NETWORK_ARGS% ^
  "%IMAGE%" %PI_ARGS%

exit /b %ERRORLEVEL%

:help
echo Usage:
echo   run-secure-pi.cmd [repo-path] [pi-args...]
echo.
echo Examples:
echo   run-secure-pi.cmd C:\workspace\namespace\repo-name
echo   run-secure-pi.cmd C:\workspace\namespace\repo-name -p "summarize this repo"
echo.
echo Env toggles:
echo   PI_REBUILD=1              Rebuild image before run
echo   PI_VERSION=0.42.0         Pin pi version at build time
echo   PI_DOCKER_NETWORK_NONE=1  Disable network completely
echo   PI_DISABLE_BASH_TOOL=1    Disable bash tool in pi
echo   PI_ALLOW_CONTEXT_FILES=0  Disable AGENTS.md / CLAUDE.md loading
exit /b 0
