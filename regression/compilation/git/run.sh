#!/bin/bash

# check whether environment is setup to actually test
if ! command -v sourceanalyzer &> /dev/null;
then
        echo "warning: did not find sourceanalyzer, skip test"
        exit 0
fi

# setup a dummy git repository
  git init .
  trap 'rm -rf .git' EXIT
  git add test.c 
  git commit -am "first test file"
  git status
  cp test.c a.c
  git add a.c 
  git commit -am "2nd file"
  git log --decorate --pretty=oneline
  echo ""

# analyze
  rm -rf SP
  ../../../one-line-scan --debug --fortify --no-gotocc --display-upstream HEAD~1 -o SP -- gcc test.c 
  echo $?
  cat SP/log/fortify-summary-filtered.txt 
  echo ""

# analyze
  rm -rf SP
  ../../../one-line-scan --debug --fortify --no-gotocc --display-upstream HEAD~1 -o SP -- gcc a.c 
  echo $?
  echo "filtered:"
  cat SP/log/fortify-summary-filtered.txt 
  echo "full"
  cat SP/log/fortify-summary.txt
  echo ""

# test for result
  echo "test whether the defect is displayed"
  if grep -f SP/log/fortify-summary.txt SP/log/fortify-summary-filtered.txt
  then
    echo "success"
    rm -rf SP
    exit 0
  else
    echo "git match test failed"
    exit 1
  fi
