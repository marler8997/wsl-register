module wsl;

version (Win32)
    static assert(0, "The WSL API isn't known to support 32-bit.  Compile in 64-bit mode with -m64.");

version (Win64) { } else
    static assert(0, "The WSL API is only known to support the Win64 platform.");

import std.stdio : stderr;
import core.sys.windows.windows : BOOL, HRESULT, HKEY;
import windows;

enum LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x00001000;

struct WslApiFunction
{
    string name;
    void** addressOfFuncPtr;
}

private void stderrWritefln(Char, A...)(in Char[] fmt, A args)
{
    stderr.writefln(fmt, args);
}

/**
Returns: false on error
*/
bool loadWslApi(alias ErrorFormatter = stderrWritefln)(WslApiFunction[] funcs)
{
    import core.sys.windows.windows : GetLastError, IsWow64Process,
        GetCurrentProcess, LoadLibraryExW, GetProcAddress;

    enum wslApiDll = "wslapi.dll"w;
    auto wslModule = LoadLibraryExW(wslApiDll.ptr, null, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (wslModule is null)
    {
        ErrorFormatter("Error: LoadLibraryExW failed to load '%s': %s", wslApiDll, formatSysError);
        BOOL isWow64 = false;
        if (IsWow64Process(GetCurrentProcess(), &isWow64))
        {
            if (isWow64)
                ErrorFormatter("    wslapi.dll is only known to suppor 64-bit executables, but this executable is not.");
        }
        if (!isWow64)
        {
            ErrorFormatter("       Are you on windows 10 and have you enabled wsl?");
            ErrorFormatter("       TODO: see if I can check whether or not it is enabled");
        }
        return false; // fail
    }

    uint failCount = 0;
    foreach (func; funcs)
    {
        *(func.addressOfFuncPtr) = GetProcAddress(wslModule, func.name.ptr);
        if (!*(func.addressOfFuncPtr))
        {
            ErrorFormatter("Error: GetProcAddress of '%s' failed (e=%s)", func.name, GetLastError());
            failCount++;
        }
    }
    if (failCount > 0)
    {
        ErrorFormatter("Error: failed to load %s out of %s functions from '%s'", failCount, funcs.length, wslApiDll);
        return false; // fail
    }
    return true; // sucess
}

enum WSL_DISTRIBUTION_FLAGS : uint
{
    WSL_DISTRIBUTION_FLAGS_NONE                  = 0,
    WSL_DISTRIBUTION_FLAGS_ENABLE_INTEROP        = 0x1,
    WSL_DISTRIBUTION_FLAGS_APPEND_NT_PATH        = 0x2,
    WSL_DISTRIBUTION_FLAGS_ENABLE_DRIVE_MOUNTING = 0x4,
    none                                         = WSL_DISTRIBUTION_FLAGS_NONE,
    enableInterop                                = WSL_DISTRIBUTION_FLAGS_ENABLE_INTEROP,
    appendNtPath                                 = WSL_DISTRIBUTION_FLAGS_APPEND_NT_PATH,
    enableDriveMounting                          = WSL_DISTRIBUTION_FLAGS_ENABLE_DRIVE_MOUNTING,
}
alias WslDistroFlags = WSL_DISTRIBUTION_FLAGS;

alias WslIsDistributionRegistered_FuncPtr     = extern(Windows) BOOL    function(
                                                    const(wchar)*  distroName);
alias WslRegisterDistribution_FuncPtr         = extern(Windows) HRESULT function(
                                                    const(wchar)*  distroName,
                                                    const(wchar)*  distroName);
alias WslUnregisterDistribution_FuncPtr       = extern(Windows) HRESULT function(
                                                    const(wchar)*  distroName);
alias WslConfigureDistribution_FuncPtr        = extern(Windows) HRESULT function(
                                                    const(wchar)*  distroName,
                                                    uint           defaultUid,
                                                    WslDistroFlags flags);
alias WslGetDistributionConfiguration_FuncPtr = extern(Windows) HRESULT function(
                                                    const(wchar)*  distroName,
                                                    uint*          distroVersion,
                                                    uint*          defaultUid,
                                                    WslDistroFlags*flags,
                                                    char***        defaultEnvVars,
                                                    uint*          defaultEnvVarCount);
alias WslLaunchInteractive_FuncPtr            = extern(Windows) HRESULT function(
                                                    const(wchar)*  distroName,
                                                    const(wchar)*  command,
                                                    BOOL           useCurrentWorkingDirectory,
                                                    uint*          exitCode);

struct DistroInfo
{
    wstring name;
    wstring basePath;
}

// returns: true on success, logs it's own errors
bool tryRegOpenKey(const(wchar)[] parentPath, const(wchar)[] subPath, HKEY* outKey)
{
    //import core.stdc.stdlib : alloca;
    import core.sys.windows.windows :
        ERROR_SUCCESS, HKEY_CURRENT_USER, KEY_READ,
        RegOpenKeyExW, RegCloseKey, RegEnumKeyExW, RegQueryValueExW;
    const(wchar)[] fullPath;
    {
        const fullPathCharCount = parentPath.length + 1 + subPath.length;
        //auto fullPathBuffer = cast(wchar*)alloca(wchar.sizeof * (fullPathCharCount + 1));
        auto fullPathBuffer = new wchar[fullPathCharCount + 1].ptr;
        assert(fullPathBuffer, "alloca returned null");
        fullPathBuffer[0 .. parentPath.length] = parentPath[];
        fullPathBuffer[parentPath.length] = '\\';
        auto offset = parentPath.length + 1;
        fullPathBuffer[offset .. offset + subPath.length] = subPath[];
        offset += subPath.length;
        assert(offset == fullPathCharCount, "code bug");
        fullPathBuffer[offset] = '\0';
        fullPath = fullPathBuffer[0 .. offset];
    }
    HKEY key;
    const result = RegOpenKeyExW(HKEY_CURRENT_USER, fullPath.ptr, 0, KEY_READ, outKey);
    if (result != ERROR_SUCCESS)
    {
        stderr.writefln("Error: RegOpenKeyEx(HKEY_CURRENT_USER, \"%s\"...) failed: %s", fullPath, formatSysError(result));
        return false; // fail
    }
    return true; // success
}

auto tryReadRegString(HKEY key, const(wchar)[] valueName, wstring* outString)
{
    import core.stdc.stdlib : exit;
    import std.exception : assumeUnique;
    import core.sys.windows.windows :
        REG_SZ,
        ERROR_SUCCESS, ERROR_MORE_DATA,
        RegQueryValueExW;

    uint valueType;
    uint dataByteSize = 0;
    {
        const result = RegQueryValueExW(key, valueName.ptr, null, &valueType, null, &dataByteSize);
        if (result != ERROR_SUCCESS)
            return result;
    }
    if (valueType != REG_SZ)
    {
        stderr.writefln("value '%s' was expected to be a string (%s) but is %s", valueName, REG_SZ, valueType);
        exit(1);
    }
    assert(dataByteSize >= 2, "string from registry does not contain at least 2 bytes for the null-terminator");
    auto charCount = dataByteSize / wchar.sizeof;
    auto valueBuffer = new wchar[charCount];
    {
        const result = RegQueryValueExW(key, valueName.ptr, null, &valueType, valueBuffer.ptr, &dataByteSize);
        if (result == ERROR_SUCCESS)
            *outString = valueBuffer[0 .. $ - 1].assumeUnique;
        return result;
    }
}

DistroInfo[] tryGetDistros()
{
    import std.array : appender;
    import core.stdc.stdlib : exit;
    import core.sys.windows.windows :
        ERROR_SUCCESS, ERROR_NO_MORE_ITEMS, HKEY_CURRENT_USER, KEY_READ,
        RegOpenKeyExW, RegCloseKey, RegEnumKeyExW, RegQueryValueExW;

    const linuxRegpath = r"Software\Microsoft\Windows\CurrentVersion\Lxss"w;
    HKEY linuxRegkey;
    {
        const result = RegOpenKeyExW(HKEY_CURRENT_USER, linuxRegpath.ptr, 0, KEY_READ, &linuxRegkey);
        if (result != ERROR_SUCCESS)
        {
            stderr.writefln("Error: RegOpenKeyEx(HKEY_CURRENT_USER, \"%s\"...) failed: %s", linuxRegpath, formatSysError(result));
            return null;
        }
    }
    scope (exit) RegCloseKey(linuxRegkey);
    auto distros = appender!(DistroInfo[])();
    for (uint i = 0;; i++)
    {
        wchar[200] nameBuffer;
        uint nameSize = nameBuffer.length;

        {
            const result = RegEnumKeyExW(linuxRegkey, i, nameBuffer.ptr, &nameSize, null, null, null, null);
            if (result != ERROR_SUCCESS)
            {
                if (result != ERROR_NO_MORE_ITEMS)
                {
                    stderr.writefln("Error: RegEnumKeyExW failed: %s", formatSysError(result));
                    exit(1);
                }
                break;
            }
        }
        assert(nameBuffer[nameSize] == '\0', "code bug");
        const keyName = nameBuffer[0 .. nameSize];

        //auto value = tryReadRegValue(linuxRegpath, name);
        {
            HKEY distroRegkey;
            if (!tryRegOpenKey(linuxRegpath, keyName, &distroRegkey))
            {
                // error already logged
                exit(1);
            }
            scope (exit) RegCloseKey(distroRegkey);

            DistroInfo distroInfo;
            {
                const result = tryReadRegString(distroRegkey, "DistributionName"w, &distroInfo.name);
                if (result != ERROR_SUCCESS)
                {
                    stderr.writefln("Error: RegQueryValueExW failed: %s", formatSysError(result));
                    exit(1);
                }
            }
            {
                const result = tryReadRegString(distroRegkey, "BasePath"w, &distroInfo.basePath);
                if (result != ERROR_SUCCESS)
                {
                    stderr.writefln("Error: RegQueryValueExW failed: %s", formatSysError(result));
                    exit(1);
                }
            }
            distros.put(distroInfo);
        }
    }
    return distros.data;
}
