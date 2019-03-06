#!/usr/bin/env rund
//!debug
//!debugSymbols
//!importPath .

/**
This tool lists the distributions on your system.
I couldn't find a microsoft tool that does this.
*/
import std.array : appender;
import std.string : lineSplitter;
import std.stdio : writeln, writefln;
import std.process : execute, environment;

import windows;
import wsl;

// TODO: use a mixin template for this
__gshared WslGetDistributionConfiguration_FuncPtr WslGetDistributionConfiguration;
auto wslApiFunctions = [
    WslApiFunction("WslGetDistributionConfiguration", cast(void**)&WslGetDistributionConfiguration),
];

int main(string[] args)
{
    if (!loadWslApi!writefln(wslApiFunctions))
        return 1; // fail

    const distros = tryGetDistros();
    foreach (distro; distros)
    {
        writeln("--------------------------------------------------------");
        writefln("Distro '%s'", distro.name);
        writefln("BasePath '%s'", distro.basePath);
        uint distroVersion;
        uint defaultUid;
        WslDistroFlags flags;
        char** defaultEnvVars;
        uint defaultEnvVarCount;
        {
            const result = WslGetDistributionConfiguration(distro.name.ptr, &distroVersion,
                &defaultUid, &flags, &defaultEnvVars, &defaultEnvVarCount);
            if (result)
            {
                writefln("Error: WslGetDistributionConfiguration failed: %s", formatHresultError(result));
                continue;
            }
        }
        writefln("Version %s", distroVersion);
        writefln("DefaultUid %s", defaultUid);
    }

    return 0;
}

/+
// I've seen these tools print in 16-bit wide characters, this will convert that output to ascii
auto fixEncoding(char[] str)
{
    if (str.length < 2)
        return str;

    ubyte meatOffset;
    if (str[0] == '\0')
        meatOffset = 1;
    else if (str[1] == '\0')
        meatOffset = 0;
    else
        return str;

    for (size_t i = 0; i < str.length / 2; i++)
    {
        str[i] = cast(char)str[ (i<<1) + meatOffset];
    }
    return str[0 .. $/2];
}
+/
