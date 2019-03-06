# wsl-register

Every linux distro needs an executable to register with WSL (Windows Subsystem for Linux).  This is because when a distro is registered, the `BasePath` where the distro is extracted and stored on the windows filesystem is inferred from the path of the executable that is calling the function to register the distro.  So if your registration executable is in `C:\my_distro\register_my_distro.exe`, when you execute it, WSL will extract the rootfs to `C:\my_distro`.

Some distros will also use this executable to implement other functionality as well, such types of executables are referred to as "WSL Distro Launchers", i.e.

* https://github.com/Microsoft/WSL-DistroLauncher
* https://github.com/yuk7/wsldl

The executable built from this repo takes a different approach.  It only implements the "register" functionality with the idea that other functionality can be done in other tools that can be shared between distros such as `wsl` or `wslconfig`. Here's how you build it:

```
build <distro-name> <rootfs-file>
```

This will generate `register.exe`.  Copy this into your distro folder.  Double-clicking it will launch a console and register your distro with WSL.  It finds the rootfs archive based on the filename given to the `build-register` script.

> NOTE: if your `<rootfs-file>` is a relative path then `register.exe` will search for it relative to where it is stored (not relative to where it was compiled)

# WSL Commands

This is a good article to read from Microsoft: https://docs.microsoft.com/en-us/windows/wsl/wsl-config

Once your distro is registered, you can start a shell in it with:
```batch
wsl -d <distro>
```

> NOTE: if wsl is not found, try `%windir%\sysnative\wsl`.  It may not be found it you are in a 32-bit command promptt.

To unregister your distro, you can run `wsl -u <distro>`.  If that doesn't work, then you're probably on an older version of Windows and should be able to run `wslconfig /u <distro>` instead.

# How WSL Works

WSL requires the distro to be installed to a folder somewhere on your filesystem.  It determines this folder when the distro is registered with `WslRegisterDistribution` by getting the path of the executable that calls that function.  It's a bit odd but that's how it works.  This register function also takes an absolute path to a gzipped tar archive of the distro's rootfs.  Note that rootfs archive can be anywhere on the filesystem, it doesn't have to be in the distro folder.  It is extracted to the distro folder when it is registered.  So you end up with something like this:

```
<DistroFolder>\register.exe (this executable just registers the distro by calling WslRegisterDistribution)
<AnywhereOnFilesystem>\my-distro-rootfs.tar.gz
```

Once you run `register.exe`, WSL will add some entries for your distro in the registry at `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss` and have extracted the contents of `<SomePath>\my-distro-rootfs.tar.gz` into the distro folder.  So you'll have this:

```
<DistroFolder>\rootfs\<ExtractedRootfsArchive>
```

If the distro contains a `/etc/passwd` file, WSL will read the user information from there.  Note that this information will contain the default shell for each user which WSL will use.

> Bug Warning: earlier versions of WSL require that the distro contain the file `/etc/passwd`.  If this file does not exist, WSL will fail to launch any command in the distro and will not print an error message (see https://github.com/Microsoft/WSL/issues/3903).  Later versions fixed this by defaulting to the "root" user when this file is missing.

> Bug Warning: earlier versions of WSL will fail with `The specified network name is no longer available.` if the distro does not contain a `/bin` or `/sbin` folder (see https://github.com/Microsoft/WSL/issues/3584).
