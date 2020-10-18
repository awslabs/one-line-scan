## One Line Scan

With this tool, projects can be compiled easily for fuzzing with AFL or for
static code analysis with tools like CBMC. One-line-scan hooks into the
compilation process and wraps calls to the compiler with other compilers.
Besides the compilation wrappers, one-line-scan ships with basic analysis jobs,
that allow to analyze a project right after compilation with the following
tools: AFL, cppcheck, CBMC, Fortify, Infer.

## Usage

### Install

As One Line Scan is a scripted tool, the project can be checked out of the
repository, and used from there. However, it is recommended to make it available
on the PATH for simpler consumption.

To get the code, use the following command

 git clone https://github.com/awslabs/one-line-scan.git

### Getting Started

One Line Scan has several back ends. The default backend is the goto-cc wrapper,
which compiles a project for tools of the CPROVER suite. The simplest one is the
plain backend, which only tracks calls to the compiler, but does not act upon
them. An example invocation for the plain backend and a project whose build
command is "make" would be:

  one-line-scan --plain --no-gotocc -- make

The available parameters of the tool can be seen when using the --help flag:

  one-line-scan --help

More invocations of one-line-scan are presented in the file doc/EXAMPLES.md

By default, the wrapper for CBMC is enabled. Furthermore, analysis is enabled by
default. To disable CBMC, use --no-gotocc, and to disable analysis, use the
parameter --no-analysis.

## How It Works

The tool one-line-scan places wrappers for common compilers like gcc, clang, as
well as g++ and clang++ in a new directory. If the parameter --suffix $SUFFIX
or --prefix $PREFIX is used, the wrapper is also created for binaries of the
name ${PREFIX}compiler and compiler${SUFFIX}. This allows to also track compiler
like gcc-9, or x86_64-unknown-linux-gnu-gcc.

After all wrappers have been placed in the directory, the environment variable
PATH is prepended with this directory. Hence, any attempt to spot the compiler
via the PATH variable will result in picking up the wrapper, instead of the
actual compiler. This allow us the take action on compiler invocations.

To check which compiler would be visible inside the build command, run the
following command that uses the plain wrapper:

  one-line-scan --plain --no-gotocc -o OLS --trunc-existing -- which gcc

With this mechanism, compiler calls based on their absolute path cannot be
intercepted. Consequently, analysis will not detect these calls. To still be
able to get these calls, one-line-scan should be used during the configuration
with "./configure" or "cmake", and next should re-use the created directory for
the actual compilation. This way, the wrapper will be used during configuration.
See call examples in configuration/doc/EXAMPLES.md or more details below.

## How to Use For

### Different Build Systems

This section explains the usage of one-line scan for the build systems using
plain compilation, make, configure and make, as well as cmake, and give a brief
example on what should be done.

All example invocations will use a different analysis backend, to cover a few
potential use cases. For each call, analysis will be enabled.

#### Direct Compilation

For a simple compiler invocation, specify the following line:

  one-line-scan -o OLS --trunc-existing -- gcc test.c -o test

#### Make

Make typically uses compilers directly, without an absolute path -- depending on
the actually used Makefile. Hence, the following command should be able to get
the used compiler calls:

  one-line-scan -o OLS --trunc-existing --no-gotocc --plain -- make

#### Configure and Make

Make typically uses compilers directly, without an absolute path. However, a
preceeding configure call might set the absolute path based on the tools that
have been detected. Hence, configuration and compilation should be run with the
same one-line-scan directory. This directory should be re-used.

  one-line-scan -o OLS --use-existing --no-gotocc --fortify --no-analysis -- ./configure
  one-line-scan -o OLS --use-existing --no-gotocc --fortify -- make

#### CMake

Make typically uses compilers directly, without an absolute path. However, cmake
typically spots used tools, and converts that into compiler names. To be able to
intercept the compiler call, configuration and compilation should be run with
the same one-line-scan directory. This directory should be re-used.

  one-line-scan -o OLS --use-existing --no-gotocc --infer --no-analysis -- cmake
  one-line-scan -o OLS --use-existing --no-gotocc --inter -- make

In case cmake created a separate directory dir, use "make -C dir" to enter the
directory "dir" for compilation.

### Non-Standard Compiler Names

There are compilers beyond gcc and clang++, e.g. clang++-9 or
x86_64-unknown-linux-gnu-gcc. Wrapper for these compilers can be setup as well,
by using the --prefix and --sufix parameter. The parameters can be combined.
For the above compilers, example calls would be

To wrap clang++-9, run:

  one-line-scan -o OLS --suffix -9 -- make

To wrap x86_64-unknown-linux-gnu-gcc, run:

  one-line-scan -o OLS --prefix x86_64-unknown-linux-gnu- -- make

To wrap x86_64-unknown-linux-gnu-gcc-8, run:

    one-line-scan -o OLS --prefix x86_64-unknown-linux-gnu- --suffix -9 -- make

The list of base compilers to be wrapped can be extended via the environment
variable OLS_TARGET_COMPILER. If multiple should be added, separate them by a
space.

### Analysis Customization

Different backends currently support different mechanisms for customization.
While CBMC and Fortify have CLI parameters for customization, Infer uses the
environment variable INFER_ANALYSIS_EXTRA_ARGS to pass cli parameter to the
Infer analysis call. For CppCheck, the environment variable CPPCHECK_EXTRA_ARG
allows to add more CLI parameters to the tool.

## License

This tool is licensed under the Apache 2.0 License.
