#!/bin/bash
# check whether we can binaries that can be fuzzed with AFL, and which actually
# trigger crashes that are found by the fuzzer

# if one of the commands fail without the test case being prepared, it should be
# a failure
set -e

if ! which afl-fuzz
then
  echo "cannot find afl-fuzz - abort with success as this is not the fault of the test"
  exit 0
fi

# start from scratch, as some commands do not work when the output directory
# already exists
D=fuzzing
rm -rf $D
mkdir -p $D

# make sure we are actually resulting in the same binary/assembly
afl-gcc read-stdin.c -g -o $D/number-afl.o -c -ffunction-sections
objdump -lSd fuzzing/number-afl.o | wc
AFL_OBJECT_SIZE=$(objdump -lSd fuzzing/number-afl.o | wc | awk '{print $1,$2}')

# compile the same object file with one-line-scan
../../../one-line-scan --afl --no-gotocc -o $D/AFLO --no-analysis -- gcc read-stdin.c -g -o $D/number-afl.o -c -ffunction-sections
objdump -lSd fuzzing/number-afl.o | wc
SP_OBJECT_SIZE=$(objdump -lSd fuzzing/number-afl.o | wc | awk '{print $1,$2}')

if [ $AFL_OBJECT_SIZE -ne $SP_OBJECT_SIZE ]
then
  echo "size of binaries with and without afl do not match - abort"
  exit 1
fi

# compile with gcc, to check that we need instrumentation to use afl
gcc read-stdin.c -g -o $D/number-gcc

# compile with one-line-scan --afl
../../../one-line-scan --afl --no-gotocc -o $D/AFL --no-analysis -- gcc read-stdin.c -o $D/number-afl

if [ ! -x $D/number-afl ]
then
  echo "error: could not find compiled target binary - abort!"
  exit 1
fi

# create test cases
mkdir -p $D/in
echo "123" > $D/in/123
echo "ABC" > $D/in/abc
echo "12A34" > $D/in/12A34

# run afl on usual gcc binary should result in an error
AFL_STATUS=0
AFL_SKIP_CPUFREQ=1 timeout 10 afl-fuzz -i $D/in -o $D/AFL-OUT-gcc $D/number-gcc > /dev/null 2> /dev/null || AFL_STATUS=$?

if [ $AFL_STATUS -eq 0 ]
then
  echo "error: binary created with gcc can fuzzed with AFL - abort"
  exit 1
fi

# afl should easily find at least 2 problems in out example within the first 10
# seconds of its run time (there are at least five that can be found)
AFL_SKIP_CPUFREQ=1 timeout 10 afl-fuzz -i $D/in -o $D/AFL-OUT $D/number-afl || AFL_STATUS=$?

if [ $AFL_STATUS -ne 124 ]
then
  echo "error: the fuzzer terminated before it's 10 second timeout - abort"
  exit 1
fi

# there should be at least 2 problems
CRASHES=$(awk '/^unique_crashes/ {print $3}' $D/AFL-OUT/fuzzer_stats)
if [ $CRASHES -lt 2 ]
then
  echo "error: less than 2 crashes have been reported in 10 seconds ($CRASHES) - abort"
  exit 1
fi
# there are no more test we do here
exit 0
