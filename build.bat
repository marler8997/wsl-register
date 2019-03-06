@if "%2" == "" (
    echo Usage: build ^<distro-name^> ^<rootfs-filename^>
    goto EXIT
)
@if NOT "%3" == "" (
    echo Error: too many command-line arguments
    goto EXIT
)

echo module register_settings; > %~dp0register_settings.d
echo enum DistroNameW = "%1"w; >> %~dp0register_settings.d
echo enum RootfsFileA = "%2"; >> %~dp0register_settings.d
echo enum RootfsFileW = "%2"w; >> %~dp0register_settings.d

@if not defined DCOMPILER set "DCOMPILER=dmd"

@REM TODO: optimize the executable for size (i.e. remove unused symbols)
%DCOMPILER% -m64 -g -debug %~dp0register.d %~dp0register_settings.d %~dp0wsl.d %~dp0windows.d

:EXIT
