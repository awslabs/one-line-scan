#!/bin/bash
# check whether the analysis reveals bugs that can be spotted by one-line-cr-bot

# fail early
set -e -x

if [ ! command -v infer &> /dev/null ] && [ ! command -v cppcheck &> /dev/null ]
then
        echo "warning: did not find infer not cppcheck, skip this test"
        exit 0
fi

rm -rf src/.git

make clean -C src

pushd src

declare -i STATUS=0

git init .
git add src.c subsrc/sub.c 
git commit src.c subsrc/sub.c -m "test: initial commit" src.c subsrc/sub.c 
sed -i 's:int a = 0;:int a;:g' subsrc/sub.c 
git commit -m "bug: remove initializer" subsrc/sub.c 
../../../../one-line-cr-bot.sh -f -b "make" -B "$(git rev-parse --short HEAD^)" &> output.log || STATUS=$?


if [ "$STATUS" -eq 0 ]
then
	echo "error: error in code not signaled via exit code, abort"
	exit 1
fi

# check whether code problems are found
if ! grep "^subsrc/sub.c:4: " output.log
then
	echo "error: did not spot uninitialized variable error, abort"
	exit 1
fi

make clean
popd

exit 0
