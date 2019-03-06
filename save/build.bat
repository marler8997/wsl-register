@if not defined DCOMPILER set "DCOMPILER=dmd"
%DCOMPILER% -m64 -g -debug -I=%~dp0.. %~dp0launcher.d %~dp0..\wsl.d %~dp0..\windows.d
