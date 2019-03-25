@if "%1" == "" (
    echo Usage: build ^<distro-name^> [^<rootfs-filename^>]
    goto EXIT
)
@if "%2" == "" (
    set ROOTFS_FILENAME=rootfs.tar.gz
) else (
    set ROOTFS_FILENAME=%2
)
@if NOT "%3" == "" (
    echo Error: too many command-line arguments
    goto EXIT
)


echo module register_settings; > %~dp0register_settings.d
echo enum DistroNameW = "%1"w; >> %~dp0register_settings.d
echo enum RootfsFileA = "%ROOTFS_FILENAME%"; >> %~dp0register_settings.d
echo enum RootfsFileW = "%ROOTFS_FILENAME%"w; >> %~dp0register_settings.d

@if not defined DCOMPILER set "DCOMPILER=dmd"

@REM TODO: optimize the executable for size (i.e. remove unused symbols)
%DCOMPILER% -m64 -g -debug -of=%~dp0register-%1.exe %~dp0register.d %~dp0register_settings.d %~dp0wsl.d %~dp0windows.d

:EXIT
