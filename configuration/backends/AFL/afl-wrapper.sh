#!/bin/bash
#
#  Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  
#  Licensed under the Apache License, Version 2.0 (the "License").
#  You may not use this file except in compliance with the License.
#  A copy of the License is located at
#  
#      http://www.apache.org/licenses/LICENSE-2.0
#  
#  or in the "license" file accompanying this file. This file is distributed 
#  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
#  express or implied. See the License for the specific language governing 
#  permissions and limitations under the License.
#
# control whether gcc has been called by afl, or some other tool

#################### DO NOT MODIFY ##################

# by default, all supported tools have not been found.
NATIVE_GCC=/bin/false
NATIVE_GPP=/bin/false
NATIVE_CLANG=/bin/false
NATIVE_CLANGPP=/bin/false
NATIVE_AS=/bin/false

# path to the actual AFL binaries
NATIVE_AFL_PATH=

# load the library
SCRIPT=$(readlink -e "$0")
source $(dirname $SCRIPT)/../ols-library.sh || exit 1

# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=

# base file to check whether the current process has been called by the wrapper
WRAPPERPIDFILE=/tmp/AFL-wrapper-pid

# if log file is not empty, store logging
LOG=log

#
# start of the script
#
# redirect stdin to another file descriptor (here we picked 4), and close stdin afterwards
# use this to pass stdin to the actual compiler call, and not to tools used before
REDIRECT_STDIN=0
if [ -t 0 ]
then
  REDIRECT_STDIN=1
  exec 4<&0
  exec 0<&-
fi

# use the binary name
binary_name=$(basename $0)

# check whether some parent is the wrapper already
parent_result=0
called_by_wrapper $$ || parent_result=$?

logwrapper AFL-GCC "called $binary_name, parent is AFL wrapper: $parent_result"

# if wrapper is already active somewhere in the calling tree, call original program
if [ "$parent_result" == "1" ]
then
  case "$binary_name" in
    "gcc"|"afl-gcc")
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      if [ "$NATIVE_GCC" = "/bin/true" ]
      then
        $(next_in_path gcc AFL) "$@"
        exit $?
      else
        "$NATIVE_GCC" "$@" $GCCEXTRAARGUMENTS
        exit $?
      fi
      ;;
    "g++"|"afl-g++")
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      if [ "$NATIVE_GPP" = "/bin/true" ]
      then
        $(next_in_path g++ AFL) "$@"
        exit $?
      else
        "$NATIVE_GPP" "$@" $GCCEXTRAARGUMENTS
        exit $?
      fi
      ;;
    "clang"|"afl-clang")
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      if [ "$NATIVE_CLANG" = "/bin/true" ]
      then
        $(next_in_path clang AFL) "$@"
        exit $?
      else
        "$NATIVE_CLANG" "$@" $GCCEXTRAARGUMENTS
        exit $?
      fi
      ;;
    "clang++"|"afl-clang++")
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      if [ "$NATIVE_CLANGPP" = "/bin/true" ]
      then
        $(next_in_path clang++ AFL) "$@"
        exit $?
      else
        "$NATIVE_CLANGPP" "$@" $GCCEXTRAARGUMENTS
        exit $?
      fi
      ;;
    "as"|"afl-as")
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      if [ "$NATIVE_AS" = "/bin/true" ]
      then
        $(next_in_path as AFL) "$@"
        exit $?
      else
        "$NATIVE_AS" "$@" $GCCEXTRAARGUMENTS
        exit $?
      fi
      ;;
    *)
      echo "error: AFL wrapper has been called with an unknown tool name: $binary_name" 2>&1
      exit 1
      ;;
  esac
fi

# free the lock and the parent pid file in case something gets wrong
trap exit_handler EXIT

# tell that we are using the wrapper now with the current PID
touch "$WRAPPERPIDFILE$$"

# use the actual AFL binary
case "$binary_name" in
  "gcc" | "g++" | "clang" | "clang++" | "as" )
    logwrapper AFL-GCC "call actual tool:$NATIVE_AFL_PATH/afl-$binary_name $@ $GCCEXTRAARGUMENTS"
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    "$NATIVE_AFL_PATH"/afl-"$binary_name" "$@" $GCCEXTRAARGUMENTS
    exit $?
    ;;
  "afl-gcc" | "afl-g++" | "afl-clang" | "afl-clang++" | "afl-as" )
    logwrapper AFL-GCC "call actual tool:$NATIVE_AFL_PATH/$binary_name $@ $GCCEXTRAARGUMENTS"
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    "$NATIVE_AFL_PATH"/"$binary_name" "$@" $GCCEXTRAARGUMENTS
    exit $?
    ;;
  *)
    echo "error: AFL wrapper has been called with an unknown tool name: $binary_name" 2>&1
    exit 1
    ;;
esac

# make sure we do not enter the goto-gcc path again
# cleanup is performed by exit handler
echo "warning: unknown tool binary name $0 with basename $binary_name" >&2
exit 1
