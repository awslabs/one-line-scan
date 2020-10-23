# Examples

This file demonstrates how one-line-scan can be used with its various backends.

## Getting Started

The tool prints usage information is executed without any parameters.

    one-line-scan

When using the default options on a project, the project will be compiled for
analysis with CBMC or other tools of the CPROVER tools suite, and a default
analysis will be executed:

    one-line-scan -- make

To disable analysis, which might be expensive in case of CPROVER, add the
--no-analysis flag:

    one-line-scan --no-analysis -- make

For using any other backend, make sure you disable the goto-cc backend with the
--no-gotocc parameter.

To store log files and results in another directory, the -o flag can be used:

    one-line-scan --no-analysis -o OLS -- make

Multiple runs can use the same output directory, and either keep its content, or
drop it. To keep them, add the flag --use-existing, otherwise --trunc-existing.
Example calls are as follows:

    one-line-scan --no-analysis -o OLS -- gcc 1.c -o 1.o
    one-line-scan --no-analysis -o OLS --use-existing -- gcc 2.c -o 2.o

# Example Calls for Available Backends

This section lists example calls for different backends.

## Plain Backend - Spot Failing Compiler Calls

A use case of the plain backend is to trace failing compiler calls on a project
that has many compiler calls and is typically compiled with several jobs. The
plain wrapper records failing compiler calls, that can be investigated
afterwards without rerunning sequential compilation again:

    one-line-scan --plain --no-gotocc -o PLAIN -- make -j $(nproc)

To display the failing calls, including the working directory where the call was
actually issued, have a look into the failed_calls.log file:

    cat PLAIN/plain/failed_calls.log

Another use case for the plain wrapper is to modify the compiler parameters, for
example enabling additional warnings while not making them fatal, as well as
adding sanitizers to an existing setup for testing. This can be achieved with
the following call:

     one-line-scan --plain --no-gotocc -o PLAIN \
         --extra-cflag-set "-Wno-error -Wextra -fsanitize=undefined" \
         -- make

## Fortify Backend

To analyze C/C++ projects with Fortify, the used compiler has to be gcc.
However, some projects use different compiler names instead. The fortify wrapper
takes care of the renaming, so that for example the compiler
x86_64-unknown-linux-gcc can be used, as well as other cross-compilers. To use
such a compiler, the --prefix parameter can be added.

    one-line-scan --fortify --no-gotocc --prefix x86_64-unknown-linux- -- make


## Infer Backend

The infer backend is enabled with the parameter "--infer". As Infer calls are
happening inside one-line-scan, it might be hard to add additional analysis
options to Infer. The below environment variable INFER_ANALYSIS_EXTRA_ARGS can
be used to forward analysis options.

Cmake allows to dump a compilation database, which is supported to be consumed
by Infer. In combination with non-gcc compilers, this setup is still
challenging. This case is supported by one-line-scan as follows, assuming the
additional compiler is called 'new-compiler' like below.

The following commands can be used to run Infer on a project with compiler
'new-compiler', and with extra analysis options '--bufferoverrun'.

    one-line-scan -o OLS --use-existing --no-gotocc --infer --no-analysis -- cmake
    INFER_ANALYSIS_EXTRA_ARGS="--bufferoverrun" \
        OLS_TARGET_COMPILER="my-compiler" \
        one-line-scan -o OLS --use-existing --no-gotocc --inter -- make

# Example Calls for One-Line-CR-Bot

This section demonstrates how defects for a commit series can be reported. To
see the full list of commands, see the command-line help output. This command
will also show the default values for all the parameters.

    one-line-cr-bot.sh -h

Parameters can be set either via the command line, or via environment variables.
Environment variables allow a more verbose setup, in that they represent the
configuration to be modified in a more human-readable way. For a project that
uses gcc as the compiler, and builds with "make", and uses "make clean" for
cleaning, the following line would present defects introduced since commit
origin/mainline:

    one-line-cr-bot.sh -B origin/mainline -b "make" -c "make clean"

To temporarily install Infer and CppCheck as well, as well as seeing the full
set of defects for the current commit, -I and -v can be added:

    one-line-cr-bot.sh -B origin/mainline -b "make" -c "make clean" -I -v

As defect matching is currently done based on file name and line number, this
call might still report too many defects as new defects, as it will also report
defects that just moved. To suppress this behavior, another filtering mechanism
can be used:

    one-line-cr-bot.sh -B origin/mainline -b "make" -c "make clean" -I -n -v

Using environment variables, the same call would look as follows:

    BASE_COMMIT="origin/mainline" \
      BUILD_COMMAND="make" \
      CLEAN_COMMAND="make clean" \
      REPORT_NEW_ONLY="true" \
      VERBOSE=1 \
      one-line-cr-bot.sh

In case you do not want to run Infer or CppCheck, tools can be disabled or
enabled separately. To disable Infer, the following command can be used:

    one-line-cr-bot.sh -B origin/mainline -b "make" -c "make clean" -D Infer

You can also forward parameters to one-line-scan and its backends as explained
above, by using the environment variables for the backends, as well as the
parameter -O:

    one-line-cr-bot.sh -B origin/mainline -b "make" -c "make clean" \
        -O "--suffix -10"