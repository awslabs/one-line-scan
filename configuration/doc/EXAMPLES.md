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

To add another run to the same output directory, depending on whether you want
to keep the files from the previous run or not. To keep them, add the flag
--use-existing, otherwise --trunc-existing. Example calls are as follows:

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

## Fortify Backend

To analyze C/C++ projects with Fortify, the used compiler has to be gcc.
However, some projects use different compiler names instead. The fortify wrapper
takes care of the renaming, so that for example the compiler
x86_64-unknown-linux-gcc can be used, as well as other cross-compilers. To use
such a compiler, the --prefix parameter can be added.

 one-line-scan --fortify --no-gotocc --prefix x86_64-unknown-linux- -- make
