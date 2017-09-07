@echo off

set RDA=f:\UplayLibrary\Anno 2205\maindata
set LUA=e:\devel\lua_x64\lua.exe

if not exist tmp mkdir tmp

for /r "%RDA%" %%i in (*.rda) do (
    echo %%~ni
    "%LUA%" rda.lua "%%i" > tmp\%%~ni.txt
)

:eof
pause
