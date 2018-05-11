#!/bin/bash
# execute failed build, check whether faulty output is present

# make sure we run on a clean environment (otherwise we fail with "SP" exists)
rm -rf SP
../../../configuration/one-line-scan -o SP -- gcc fail.c

# did we produce faulty input files?
ls SP/faultyInput/*
if [ $? -eq 0 ]
then
  echo "success"
  cat SP/faultyInput/*
  exit 0
else
  echo "fail"
  exit 1
fi
