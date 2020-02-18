#!/bin/bash
#
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
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

#ECHOCOMMAND="echo"
ECHOCOMMAND="true" # use a command that simply consumes all arguments
# if log file is not empty, store logging in wrapper-log.txt in the wrapper installation directory
LOG=log

#################### DO NOT MODIFY ##################
# directory name used to lock concurrent access
LOCKDIR=XX/tmp/cflags-wrapper-lockXX
WRAPPERPIDFILE=/tmp/cflags-wrapper-pid
TRAPDIR=

# load the library
SCRIPT=$(readlink -e "$0")
source $(dirname $SCRIPT)/ols-library.sh || exit 1

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

# the directory, in which the lock directory should be created, has to exist
# otherwise the wrapper is broken (and the locking mkdir would block forever)
LOCK_PARENT_DIR="$(dirname $LOCKDIR)"
if [ ! -d "$LOCK_PARENT_DIR" ]
then
  echo "error: cflags wrapper is broken" >&2
  exit 1
fi

# set actual logfile
if [ -z "$LOG" ]
then
  LOG="/dev/null"
else
  LOG="$LOCK_PARENT_DIR/wrapper-log.txt"
fi

binary_name=$(basename $0)

# check whether some parent is the wrapper already
parent_result=0
called_by_wrapper $$ || parent_result=$?

# logging
logwrapper CFLAGS "called $binary_name as $$ with $0 $@"
logwrapper CFLAGS "parent is wrapper: $parent_result"

# if wrapper is already active somewhere in the calling tree, call original program
if [ "$parent_result" == "1" ]
then
  NATIVE_CFLAGS=$(next_in_path $binary_name)
  logwrapper CFLAGS "call native $NATIVE_CFLAGS $@"
  [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
  $NATIVE_CFLAGS "$@"
  exit $?
fi

# free the lock and the parent pid file in case something gets wrong
trap exit_handler EXIT

# tell that we are using the wrapper now with the current PID
touch "$WRAPPERPIDFILE$$"

# locate gcc and g++ wrappers
logwrapper CFLAGS "PATH: $PATH"
NATIVE_CFLAGS=$(next_in_path $binary_name)
logwrapper CFLAGS "NATIVE_CFLAGS: $NATIVE_CFLAGS"
NATIVE_CC=$($NATIVE_CFLAGS CC)
logwrapper CFLAGS "NATIVE_CC: $NATIVE_CC"
basename_native_cc=$(basename $NATIVE_CC)
OUR_CC=$(next_in_path $basename_native_cc)
logwrapper CFLAGS "OUR_CC: $OUR_CC"
NATIVE_CXX=$($NATIVE_CFLAGS CXX)
logwrapper CFLAGS "NATIVE_CXX: $NATIVE_CXX"
basename_native_cxx=$(basename $NATIVE_CXX)
OUR_CXX=$(next_in_path $basename_native_cxx)
logwrapper CFLAGS "OUR_CXX: $OUR_CXX"

# adjust the wrappers if they 1) genuinely are ours and 2) they haven't been
# touched yet and 3) the native CC/CXX is provided as full path by cflags
if echo $NATIVE_CC | grep -q "^/"
then
  if [ "$(file -b "$OUR_CC")" = "Bourne-Again shell script, ASCII text executable" ]
  then
    if grep -q "^NATIVE_COMPILER=/bin/true$" "$OUR_CC"
    then
      perl -p -i -e "s:NATIVE_COMPILER=/bin/true:NATIVE_COMPILER=$NATIVE_CC:" "$OUR_CC"
    fi
    if grep -q "^NATIVE_GCC=/bin/true$" "$OUR_CC"
    then
      perl -p -i -e "s:NATIVE_GCC=/bin/true:NATIVE_GCC=$NATIVE_CC:" "$OUR_CC"
    fi
  fi
fi

if echo $NATIVE_CXX | grep -q "^/"
then
  if [ "$(file -b "$OUR_CXX")" = "Bourne-Again shell script, ASCII text executable" ]
  then
    wrapped_cxx=$(grep -q "^NATIVE_COMPILER_GPP=.\+$" "$OUR_CXX" | cut -f2 -d"=")
    if [ -n "$wrapped_cxx" ] && [ "$wrapped_cxx" != "$NATIVE_CXX" ]
    then
      perl -p -i -e "s:NATIVE_COMPILER_GPP=.*:NATIVE_COMPILER_GPP=$NATIVE_CXX:" "$OUR_CXX"
    fi
    wrapped_cxx=$(grep -q "^NATIVE_GPP=.\+$" "$OUR_CXX" | cut -f2 -d"=")
    if [ -n "$wrapped_cxx" ] && [ "$wrapped_cxx" != "$NATIVE_CXX" ]
    then
      perl -p -i -e "s:NATIVE_GPP=.*:NATIVE_GPP=$NATIVE_CXX:" "$OUR_CXX"
    fi
  fi
fi

# parse the options and see whether we need to handle this call
FORMAT=make
format_is_next=0
skip_next=0
VARIABLE=

for arg in "$@"
do
  case "$arg" in
    -flavor) skip_next=0 ;;
    -format) format_is_next=1 ;;
    *)
      if [ $format_is_next -eq 1 ]
      then
        FORMAT=$arg
        format_is_next=0
      elif [ $skip_next -eq 1 ]
      then
        skip_next=0
      else
        VARIABLE=$arg
      fi
      ;;
  esac
done

if [ "$FORMAT" = "sh" ]
then
  OUR_CC="'$OUR_CC'"
  OUR_CXX="'$OUR_CXX'"
fi

if [ -z "$VARIABLE" ]
then
  [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
  logwrapper CFLAGS "subst CC->$OUR_CC/CXX->$OUR_CXX native $NATIVE_CFLAGS $@"
  $NATIVE_CFLAGS "$@" | \
    sed "s#CC=.*#CC=$OUR_CC#" | \
    sed "s#CXX=.*#CXX=$OUR_CXX#"
  exit ${PIPESTATUS[0]}
fi

if [ "$VARIABLE" = "CC" ]
then
  echo -n $OUR_CC
elif [ "$VARIABLE" = "CXX" ]
then
  echo -n $OUR_CXX
else
  [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
  logwrapper CFLAGS "call native $NATIVE_CFLAGS $@"
  $NATIVE_CFLAGS "$@"
fi

if [ "$FORMAT" = "sh" ]
then
  echo
fi

[ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
