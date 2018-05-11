## One Line Scan

With this tool, projects can be compiled easily for fuzzing with AFL or for
static code analysis with tools like CBMC. One-line-scan hooks into the
compilation process and wraps calls to the compiler with other compilers.
Besides the compilation wrappers, one-line-scan ships with basic analysis jobs,
that allow to analyze a project right after compilation with the following
tools: AFL, cppcheck, CBMC, Fortify.

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

More invocations of one-line-scan are presented in the file
configuration/doc/EXAMPLES.md

## License

This library is licensed under the Apache 2.0 License.
