@echo off
:: this script retrieves the cygwin installation path from the registry
:: and invokes the bash.exe from the /bin/ directory, forwarding all 
:: parameters passed to the script to bash.
set CHERE_INVOKING=1
for /f "skip=2 tokens=3" %%v in ('reg query hklm\software\cygwin\setup /v rootdir') do set PATH="%%v\bin";%PATH%
bash %*
