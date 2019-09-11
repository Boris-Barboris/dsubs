import std.file;
import std.getopt;
import std.process;
import std.file;
import std.process;
import std.stdio;
import std.string;

// Commandline args
bool useUnitThreaded;
bool coreTestsOnly;
enum Mode { phobos, vibe, combined };
Mode mode;
string[] unitThreadedArgs;

// Exit code to be returned
int exitCode=0;

// Utils ///////////////////////////////////////////////

string flagUseUnitThreaded(bool on)
{
	return on? " --ut" : "";
}

string flagCoreTestsOnly(bool on)
{
	return on? " --core" : "";
}

string flagMode(Mode mode)
{
	final switch(mode)
	{
	case Mode.phobos:   return " --mode=phobos";
	case Mode.vibe:     return " --mode=vibe";
	case Mode.combined: return " --mode=combined";
	}
	return coreTestsOnly? " --core" : "";
}

string fixSlashes(string path)
{
	version(Windows)    return path.replace(`/`, `\`);
	else version(Posix) return path.replace(`\`, `/`);
	else static assert(0);
}

void tryMkdir(string dir)
{
	if(!exists(dir))
		mkdir(dir);
}

int runFromCurrentDir(string command)
{
	version(Windows) return run(command);
	else             return run("./"~command);
}

int run(string command)
{
	writeln(command);
	return spawnShell(command).wait;
}

int run(string[] command)
{
	writeln(command);
	return spawnProcess(command).wait;
}

bool canRun(string command)
{
	return executeShell(command).status == 0;
}

string findRdmd()
{
	// LDC/GDC don't always include rdmd, so allow user to specify path to it in $RDMD.
	// Otherwise, use "rdmd".
	//
	// For travis, if "rdmd" doesn't work (ie, LDC/GDC is being tested), then use
	// the copy of rdmd that was downloaded by the 'ci_setup.d' script.
	auto rdmd = environment.get("RDMD");
	if(rdmd is null)
	{
		rdmd = "rdmd";
		if(!canRun("rdmd --help"))
		{
			auto travisOsName = environment.get("TRAVIS_OS_NAME");
			if(travisOsName == "osx")
				rdmd = "local-dmd/dmd2/"~travisOsName~"/bin/rdmd";
			else
				rdmd = "local-dmd/dmd2/"~travisOsName~"/bin64/rdmd";
		}
	}

	return rdmd;
}

// Main (Process command line) ///////////////////////////////////////////////

int main(string[] args)
{
	try
	{
		auto argsHelp = getopt(args,
			"ut",     "Use unit-threaded (Always includes ut's --trace)", &useUnitThreaded,
			"core",   "Only run basic core tests (Can only be used with --mode=phobos)", &coreTestsOnly,
			std.getopt.config.required,
			"m|mode", "'-m=phobos': Run Phobos tests | '-m=vibe': Run Vibe.d tests | '-m=combined': Run core-only Phobos tests and all Vibe.d tests", &mode,
		);

		if(argsHelp.helpWanted)
		{
			defaultGetoptPrinter(
				"Runs the mysql-native test suite with Phobos sockets, Vibe.d sockets, or combined.\n"~
				"\n"~
				"Usage:\n"~
				"  run_tests --mode=(phobos|vibe|all) [OPTIONS] [-- [UNIT-THREADED OPTIONS]]\n"~
				"\n"~
				"Examples:\n"~
				"  run_tests --mode=combined\n"~
				"  run_tests --ut --mode=vibe -- --help\n"~
				"  run_tests --ut --mode=vibe -- --single --random\n"~
				"\n"~
				"Options:",
				argsHelp.options
			);

			return 0;
		}
	}
	catch(Exception e)
	{
		stderr.writeln(e.msg);
		stderr.writeln("For help: run_tests --help");
		stderr.writeln("Recommended: run_tests -m=combined");
		return 1;
	}

	if(coreTestsOnly && mode==Mode.combined)
	{
		stderr.writeln("Cannot use --core and --mode=combined together.");
		//stderr.writeln("Instead, use:");
		//stderr.writeln("  run_tests --core --mode=phobos && run_tests --core --mode=vibe");
		stderr.writeln("For help: run_tests --help");
		return 1;
	}

	if(coreTestsOnly && mode==Mode.vibe)
	{
		stderr.writeln("Cannot use --core and --mode=vibe together.");
		stderr.writeln("For help: run_tests --help");
		return 1;
	}

	unitThreadedArgs = args[1..$];
	runTests();
	return exitCode;
}

// Run Tests ///////////////////////////////////////////////

void runTests()
{
	//writeln("unitThreadedArgs: ", unitThreadedArgs);

	// GDC doesn't autocreate the dir (and git doesn't beleive in empty dirs)
	tryMkdir("bin");

	final switch(mode)
	{
	case Mode.phobos:   runPhobosTests();   break;
	case Mode.vibe:     runVibeTests();     break;
	case Mode.combined: runCombinedTests(); break;
	}
}

void runPhobosTests()
{
	// Setup compilers
	auto rdmd = findRdmd();
	auto dmd = environment.get("DMD", "dmd");

	writeln("Using:");
	writeln("  RDMD=", rdmd);
	writeln("  DMD=", dmd);
	stdout.flush();
	
	// Setup --core
	auto debugTestsId = coreTestsOnly? "MYSQLN_CORE_TESTS" : "MYSQLN_TESTS";
	auto msgSuffix    = coreTestsOnly? " (core tests only)" : "";

	// Setup unit-threaded
	string dFile;
	string utSuffix;
	string utArgs;
	if(useUnitThreaded)
	{
		msgSuffix = msgSuffix~" (unit-threaded)";
		auto utVer="0.7.45";
		utSuffix="-ut";
		utArgs="-version=MYSQLN_TESTS_NO_MAIN -version=Have_unit_threaded -Iunit-threaded-"~utVer~"/unit-threaded/source/ --extra-file=unit-threaded-"~utVer~"/unit-threaded/libunit-threaded.a --exclude=unit_threaded";
		dFile = "bin/ut.d";

		// Setup local unit-threaded
		run("dub fetch unit-threaded --version="~utVer~" --cache=local");
		chdir(("unit-threaded-"~utVer~"/unit-threaded").fixSlashes);
		run("dub build -c gen_ut_main");
		run("dub build -c library");
		chdir(("../..").fixSlashes);
		run(("unit-threaded-"~utVer~"/unit-threaded/gen_ut_main -f bin/ut.d").fixSlashes);
	}
	else
	{
		dFile = "source/mysql/package.d";
	}

	// Compile tests
	writeln("Compiling Phobos-socket tests", msgSuffix, "...");
	auto status = run(rdmd~" --compiler="~dmd~" --build-only -g -unittest "~utArgs~" -debug="~debugTestsId~" -ofbin/mysqln-tests-phobos"~utSuffix~" -Isource "~dFile);
	//$RDMD --compiler=$DMD --build-only -g -unittest $UT_ARGS -debug=$DEBUG_TESTS_ID -ofbin/mysqln-tests-phobos${UT_SUFFIX} -Isource $D_FILE
	if(status != 0)
	{
		exitCode = status;
		return;
	}

	writeln("Running Phobos-socket tests", msgSuffix, "...");
	status = run(["bin/mysqln-tests-phobos"~utSuffix, "-t"] ~ unitThreadedArgs);
	// bin/mysqln-tests-phobos${UT_SUFFIX} -t "$@"
	if(status != 0)
	{
		exitCode = status;
		return;
	}
}

void runVibeTests()
{
	auto coreMsg = coreTestsOnly? " (core tests only)" : "";
	writeln("Doing Vibe-socket tests", coreMsg, "...");

	if(useUnitThreaded)
		exitCode = run(["dub", "run", "-c", "unittest-vibe-ut", "--", "-t"] ~ unitThreadedArgs);
	else
		exitCode = run("dub test -c unittest-vibe");
}

void runCombinedTests()
{
	auto phobosStatus = runFromCurrentDir(
		"run_tests"~
		flagMode(Mode.phobos)~
		flagCoreTestsOnly(true)~
		flagUseUnitThreaded(useUnitThreaded)
	);
	if(phobosStatus != 0)
	{
		exitCode = phobosStatus;
		return;
	}

	auto vibeStatus = runFromCurrentDir(
		"run_tests"~
		flagMode(Mode.vibe)~
		flagCoreTestsOnly(false)~
		flagUseUnitThreaded(useUnitThreaded)
	);
	exitCode = vibeStatus;
}
