@echo off

rem Compile using $DMD if it exists, otherwise use dmd
if "%DMD%" == "" set DMD=dmd

echo DMD=%DMD%
%DMD% -ofrun_tests_bin run_tests.d && run_tests_bin %*
