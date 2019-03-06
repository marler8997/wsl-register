/**
A small program to register a distro.

The DistroName and RootfsFile are passed in at compile time via the "register_settings.d"
file which is generated in build-register.bat.

This program is meant to be copied to the "distro folder" and double-clicked to register
the distro with WSL.  Double-clicking the executable will open a terminal and print the
results of registration.
*/

import std.functional : memoize;
import std.array : Appender;
import std.path : dirName, baseName, isAbsolute, absolutePath, buildNormalizedPath;
import std.file : thisExePath, exists;
import std.stdio : stdout, stderr, stdin;

import windows;
import wsl;
import register_settings;

// TODO: use a mixin template for this
__gshared WslIsDistributionRegistered_FuncPtr WslIsDistributionRegistered;
__gshared WslRegisterDistribution_FuncPtr WslRegisterDistribution;
auto wslApiFunctions = [
    WslApiFunction("WslIsDistributionRegistered", cast(void**)&WslIsDistributionRegistered),
    WslApiFunction("WslRegisterDistribution", cast(void**)&WslRegisterDistribution),
];

struct Generators
{
    static auto exeFilename() { return thisExePath(); }
    static auto exeDir() { return getExeFilename.dirName; }
}

alias getExeFilename = memoize!(Generators.exeFilename);
alias getExeDir = memoize!(Generators.exeDir);

T[] stripSuffix(T,U)(T[] str, const(U)[] suffix)
{
    import std.algorithm : endsWith;
    return str.endsWith(suffix) ? str[0 .. $ - suffix.length] : str;
}

void main()
{
    try
    {
        main2();
    }
    catch (Throwable e)
    {
        stdout.writefln("%s", e);
    }
    stdout.writeln("Press enter to quit...");
    stdout.flush();
    stdin.readln();
}

void main2()
{
    if (!loadWslApi(wslApiFunctions))
        return;

    const rootfsFileAbsoluteAscii = isAbsolute(RootfsFileA) ? RootfsFileA :
        absolutePath(buildNormalizedPath(getExeDir, RootfsFileA));

    const roofsFile = rootfsFileAbsoluteAscii.toWcharCStr();
	// TODO: also print the distro path
    stdout.writefln("Registering Distro '%s' with rootfs '%s'...", DistroNameW, roofsFile);
    const result = WslRegisterDistribution(DistroNameW.ptr, roofsFile.ptr);
    if (result == 0)
    {
        stdout.writefln("Success");
        return;
    }

    // Try to see what went wrong
    if (WslIsDistributionRegistered(DistroNameW.ptr))
    {
        stderr.writefln("Error: distro '%s' is already registered", DistroNameW);
        return;
    }
    stderr.writefln("Error: WslRegisterDistribution failed: %s", formatHresultError(result));
    if (!exists(RootfsFileA))
    {
        stderr.writefln("       The rootfs file '%s' doesn't exist", RootfsFileA);
    }
    else if (!exists(rootfsFileAbsoluteAscii))
    {
        stderr.writefln("       The rootfs file you gave '%s' exists, but after converting it to an absolute path it doesn't '%s'",
            RootfsFileA, rootfsFileAbsoluteAscii);
    }
    else
    {
        stderr.writefln("       Is '%s' a valid rootfs in the 'tar gz' format?", rootfsFileAbsoluteAscii);
    }
}
