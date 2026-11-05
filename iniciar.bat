@echo off
rem Duplo clique para preparar o ambiente e rodar o pipeline do projeto TSE no Windows.
rem Opcional, pelo terminal: iniciar.bat --pular-extracao  (ou --sem-tsql, --forcar)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\iniciar.ps1" %*
set CODIGO=%ERRORLEVEL%
echo.
pause
exit /b %CODIGO%
