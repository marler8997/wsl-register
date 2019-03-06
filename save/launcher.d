/**
TODO: maybe support a default rootfs.tar.gz
*/
import std.exception : assumeUnique;
import std.functional : memoize;
import std.path : baseName, absolutePath, dirName, buildPath;
import std.file : exists, thisExePath;
import std.stdio : stdout, stderr;

import core.stdc.stdlib : exit;
import core.sys.windows.windows :
    // defines
    ERROR_INSUFFICIENT_BUFFER,
    // types
    BOOL, DWORD, HRESULT,
    // functions
    GetLastError
    ;

import windows;
import wsl;

// TODO: use a mixin template for this
__gshared WslIsDistributionRegistered_FuncPtr WslIsDistributionRegistered;
__gshared WslRegisterDistribution_FuncPtr WslRegisterDistribution;
__gshared WslUnregisterDistribution_FuncPtr WslUnregisterDistribution;
__gshared WslLaunchInteractive_FuncPtr WslLaunchInteractive;
auto wslApiFunctions = [
    WslApiFunction("WslIsDistributionRegistered", cast(void**)&WslIsDistributionRegistered),
    WslApiFunction("WslRegisterDistribution", cast(void**)&WslRegisterDistribution),
    WslApiFunction("WslUnregisterDistribution", cast(void**)&WslUnregisterDistribution),
    WslApiFunction("WslLaunchInteractive", cast(void**)&WslLaunchInteractive),
];

struct Generators
{
    static auto exeFilename() { return thisExePath(); }
    static auto exeDir() { return getExeFilename.dirName; }
    static auto distroName() { return getExeFilename.baseName.stripSuffix(".exe"); }
    static auto distroNameW() { return getDistroName.toWcharCStr; }
    //static auto rootfsFile() { return buildPath(getExeDir, "..\\roofs_tar_gz_dir\\rootfs.tar.gz"); }
}

alias getExeFilename = memoize!(Generators.exeFilename);
alias getExeDir = memoize!(Generators.exeDir);
alias getDistroName =  memoize!(Generators.distroName);
alias getDistroNameW =  memoize!(Generators.distroNameW);
//alias getRootfsFile =  memoize!(Generators.rootfsFile);

__gshared bool failIfAlreadyDone = false;

T[] stripSuffix(T,U)(T[] str, const(U)[] suffix)
{
    import std.algorithm : endsWith;
    return str.endsWith(suffix) ? str[0 .. $ - suffix.length] : str;
}


void usage()
{
    stdout.writefln("Usage: %s [-options] <command>", getDistroName);
    stdout.writeln("Commands:");
    stdout.writeln("  register <rootfs.tar.gz>");
    stdout.writeln("  unregister");
    stdout.writeln("  run");
    stdout.writeln("Options:");
    stdout.writeln("  --name        The name of the distribution to install (default's to the name of the rootfs file)");
    stdout.writeln("  --fail-if-already-done  "); // TODO: should it be --fail-noop instead? Or maybe --fail-no-op?
    stdout.writeln("                Causes the operation to fail if it was detected to already be done");
}

int main(string[] args)
{
    if (!loadWslApi(wslApiFunctions))
        return 1; // fail

    args = args[1..$];
    {
        size_t newArgsLength = 0;
        scope(exit) args = args[0..newArgsLength];
        for (size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if (arg.length > 0 && arg[0] != '-')
            {
                args[newArgsLength++] = arg;
            }
            else if (arg == "--name")
            {
                stderr.writeln("Error: --name not implemented");
                return 1;
            }
            else if (arg == "--fail-if-already-done")
            {
                failIfAlreadyDone = true;
            }
            else
            {
                stderr.writefln("Error: unknown option '%s'", arg);
                return 1;
            }
        }
    }

    if (args.length == 0)
    {
        usage();
        return 1;
    }
    const command = args[0];
    args = args[1 .. $];
    if (command == "register")
        return register(args);
    if (command == "unregister")
        return unregister(args);
    if (command == "run")
        return run(args);

    stderr.writefln("Error: unknown command '%s'", command);
    return 1;
}

void enforceArgCount(string[] args, string command, uint expectedCount)
{
    if (args.length != expectedCount)
    {
        stderr.writefln("Error: the '%s' command requires %s arguments but got %s", command, expectedCount, args.length);
        exit(1);
    }
}

enum TarGzExtension = ".tar.gz";

int register(string[] args)
{
    enforceArgCount(args, "register", 1);
    //const rootfsFile = getRootfsFile;
    const rootfsFile = args[0];

    const distroNameW = getDistroNameW;
    const rootfsFileAbsolute = absolutePath(rootfsFile);
    stdout.writefln("Registering Distro '%s' with rootfs '%s'...", getDistroName, rootfsFileAbsolute);
    const rootfsFileAbsoluteW = rootfsFileAbsolute.toWcharCStr();
    const result = WslRegisterDistribution(distroNameW.ptr, rootfsFileAbsoluteW.ptr);
    if (result)
    {
        if (WslIsDistributionRegistered(distroNameW.ptr))
        {
            if (failIfAlreadyDone)
            {
                stderr.writefln("Error: distro '%s' is already registered", getDistroName);
                return 1; // fail
            }
            stdout.writefln("distro '%s' is already registered", getDistroName);
            return 0; // success
        }
        stderr.writefln("Error: WslRegisterDistribution failed: %s", formatHresultError(result));
        if (!exists(rootfsFile))
        {
            stderr.writefln("       The rootfs file '%s' doesn't exist", rootfsFile);
        }
        else if (!exists(rootfsFileAbsolute))
        {
            stderr.writefln("       The rootfs file you gave '%s' exists, but after converting it to an absolute path it doesn't '%s'",
                rootfsFile, rootfsFileAbsolute);
        }
        else
        {
            stderr.writefln("       Is '%s' a valid rootfs in the 'tar gz' format?", rootfsFile);
        }
        return 1; // fail
    }
    stdout.writeln("Success");
    return 0; // success
}

int unregister(string[] args)
{
    enforceArgCount(args, "unregister", 0);

    const distroNameW = getDistroNameW;
    stdout.writefln("Unregistering Distro '%s'...", getDistroName);
    const result = WslUnregisterDistribution(distroNameW.ptr);
    if (result)
    {
        // TODO: add an option to say --must-unregister
        if (!WslIsDistributionRegistered(distroNameW.ptr))
        {
            if (failIfAlreadyDone)
            {
                stderr.writefln("Error: distro '%s' was not registered", getDistroName);
                return 1; // fail
            }
            stdout.writefln("distro '%s' was not registered", getDistroName);
            return 0;
        }
        stderr.writefln("Error: WslUnregisterDistribution failed: %s", formatHresultError(result));
        return 1;
    }
    stdout.writeln("Success");
    return 0;
}

int run(string[] args)
{
    if (args.length > 0)
        assert(0, "run with multiple args not implemented");
    const distroNameW = getDistroNameW;
    uint exitCode = 12345678;
    const result = WslLaunchInteractive(distroNameW.ptr, ""w.ptr, false, &exitCode);
    if (result)
    {
        if (!WslIsDistributionRegistered(distroNameW.ptr))
        {
            stderr.writefln("Error: distro '%s' is not registered", getDistroName);
            return 1; // fail
        }
        stderr.writefln("Error: WslLaunchInteractive of distro '%s' failed: %s", distroNameW, formatHresultError(result));
        return 1;
    }
    stdout.writefln("distro command exited with code %s (0x%x)", exitCode, exitCode);
    return exitCode;
}
