#!/bin/bash
# check whether the analysis reveals bugs that can be spotted by cppcheck

# fail early
set -e -x

make clean -C src
rm -rf src/T


pushd src
STATUS=0
../../../../one-line-scan --cppcheck -o T --no-gotocc -- make &> output.log || STATUS=$?

if [ "$STATUS" -eq 0 ]
then
	echo "error: error in code not signaled via exit code, abort"
	exit 1
fi

# check whether code problems are found
if ! grep "1 (style:unassignedVariable)" output.log
then
	echo "error: did not spot unassigned variable error, abort"
	exit 1
fi

if ! grep "1 (error:uninitvar)" output.log
then
	echo "error: did not spot unassigned variable error, abort"
	exit 1
fi

make clean
popd

exit 0
