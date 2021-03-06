#!/usr/bin/env rdmd
/*******************************************************************************

    Standalone build script for DUB

    This script can be called from anywhere, as it deduces absolute paths
    based on the script's placement in the repository.

    Invoking it while making use of all the options would like like this:
    DMD=ldmd2 DFLAGS="-O -inline" ./build.d my-dub-version
    Using an environment variable for the version is also supported:
    DMD=dmd DFLAGS="-w -g" GITVER="1.2.3" ./build.d

    Copyright: D Language Foundation
    Authors: Mathias 'Geod24' Lang
    License: MIT

*******************************************************************************/
module build;

private:

import std.algorithm;
static import std.file;
import std.format;
import std.path;
import std.process;
import std.stdio;
import std.string;

/// Root of the `git` repository
immutable RootPath = __FILE_FULL_PATH__.dirName;
/// Path to the version file
immutable VersionFilePath = RootPath.buildPath("source", "dub", "version_.d");
/// Path to the file containing the files to be built
immutable SourceListPath = RootPath.buildPath("build-files.txt");
/// Path at which the newly built `dub` binary will be
immutable DubBinPath = RootPath.buildPath("bin", "dub");

// Flags for DMD
immutable OutputFlag = "-of" ~ DubBinPath;
immutable IncludeFlag = "-I" ~ RootPath.buildPath("source");


/// Entry point
int main(string[] args)
{
    // This does not have a 'proper' CLI interface, as it's only used in
    // special cases (e.g. package maintainers can use it for bootstrapping),
    // not for general / everyday usage by newcomer.
    // So the following is just an heuristic / best effort approach.
    if (args.length > 2 ||
        (args.length == 2 && (args[1].canFind("help", "?") || args[1] == "-h")))
    {
        writeln("USAGE: ", args[0], " [version]");
        writeln("  In order to build DUB, a version module must first be generated.");
        writeln("  If one is already existing, it won't be overriden. " ~
                "Otherwise this script will use the first argument, if any, " ~
                "or the GITVER environment variable.");
        writeln("  If both are empty, `git describe` will be called");
        writeln("  Build flags can be provided via the `DFLAGS` environment variable.");
        writeln("  LDC or GDC can be used by setting the `DMD` value to " ~
                "`ldmd2` and `gdmd` (or their path), respectively.");
        return 1;
    }

    immutable dubVersion = args.length > 1 ? args[1] : environment.get("GITVER", "");
    if (!writeVersionFile(dubVersion))
        return 1;

    immutable dmd = getCompiler();
    if (!dmd.length) return 1;
    immutable dflags = environment.get("DFLAGS", "-g -O -w").split();

    // Compiler says no to immutable (because it can't handle the appending)
    const command = [
        dmd,
        OutputFlag, IncludeFlag,
        "-version=DubUseCurl", "-version=DubApplication",
        ] ~ dflags ~ [ "@build-files.txt" ];

    writeln("Building dub using ", dmd, ", this may take a while...");
    auto proc = execute(command);
    if (proc.status != 0)
    {
        writeln("Command `", command, "` failed, output was:");
        writeln(proc.output);
        return 1;
    }

    // Check dub
    auto check = execute([DubBinPath, "--version"]);
    if (check.status != 0)
    {
        writeln("Running newly built `dub` failed: ", check.output);
        return 1;
    }

    writeln("DUB has been built as: ", DubBinPath);
    version (Posix)
        writeln("You may want to run `sudo ln -s ", DubBinPath, " /usr/local/bin` now");
    else version (Windows)
        writeln("You may want to add the following entry to your PATH " ~
                "environment variable: ", DubBinPath);
    return 0;
}

/**
   Generate the version file describing DUB's version / commit

   Params:
     dubVersion = User provided version file. Can be `null` / empty,
                  in which case the existing file (if any) takes precedence,
                  or the version is infered with `git describe`.
                  A non-empty parameter will always override the existing file.
 */
bool writeVersionFile(string dubVersion)
{
    if (!dubVersion.length)
    {
        if (std.file.exists(VersionFilePath))
        {
            writeln("Using pre-existing version file. To force a rebuild, " ~
                    "provide an explicit version (first argument) or remove: ",
                    VersionFilePath);
            return true;
        }

        auto pid = execute(["git", "describe"]);
        if (pid.status != 0)
        {
            writeln("Could not determine version with `git describe`. " ~
                    "Make sure 'git' is installed and this is a git repository. " ~
                    "Alternatively, you can provide a version explicitly via the " ~
                    "`GITVER environment variable or pass it as the first " ~
                    "argument to this script");
            return false;
        }
        dubVersion = pid.output.strip();
    }

    try
    {
        std.file.write(VersionFilePath, q{
/**
   DUB version file

   This file is auto-generated by 'build.d'. DO NOT EDIT MANUALLY!
 */
module dub.version_;

enum dubVersion = "%s";
}.format(dubVersion));
        writeln("Wrote version_.d` file with version: ", dubVersion);
        return true;
    }
    catch (Exception e)
    {
        writeln("Writing version file to '", VersionFilePath, "' failed: ", e.msg);
        return false;
    }
}

/**
   Detect which compiler is available

   Default to DMD, then LDC (ldmd2), then GDC (gdmd).
   If none is in the PATH, an error will be thrown.

   Note:
     It would be optimal if we could get the path of the compiler
     invoking this script, but AFAIK this isn't possible.
 */
string getCompiler ()
{
    auto env = environment.get("DMD", "");
    // If the user asked for a compiler explicitly, respect it
    if (env.length)
        return env;

    static immutable Compilers = [ "dmd", "ldmd2", "gdmd" ];
    foreach (bin; Compilers)
    {
        try
        {
            auto pid = execute([bin, "--version"]);
            if (pid.status == 0)
                return bin;
        }
        catch (Exception e)
            continue;
    }
    writeln("No compiler has been found in the PATH. Attempted values: ", Compilers);
    writeln("Make sure one of those is in the PATH, or set the `DMD` variable");
    return null;
}
