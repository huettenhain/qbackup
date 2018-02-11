@echo off
setlocal enabledelayedexpansion
set qr=%~dp0
call :cygpath borgve venv\bin\activate
goto :bash
:cygpath
 set drive=%~d0
 set qpath=%~p0%2
 set qpath=/cygdrive/!drive:~0,1!!qpath:\=/!
 set %1=!qpath!
 goto :eof
:bash
 echo %QPREFIX%borg %*
 2>&1 "!qr!cygbash.bat" --noprofile --norc --login -c "source \"!borgve!\" && borg %*"