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
#
# Call cppcheck with used compiler flags and store output in the log directory.
# Continue compilation as usual.

#################### DO NOT MODIFY ##################

# by default, all supported tools have not been found.
NATIVE_GCC=/bin/false
NATIVE_GPP=/bin/false
NATIVE_CLANG=/bin/false
NATIVE_CLANGPP=/bin/false
TOOLPREFIX=
TOOLSUFFIX=
CPPCHECK_EXTRA_ARG="${CPPCHECK_EXTRA_ARG:-}"
CALL_DIR=


# options to be passed to cppcheck
CHECK_CONFIG="--error-exitcode=-1 --quiet --force --enable=warning"
# CHECK_CONFIG+=" --enable=style --enable=performance"
# CHECK_CONFIG+=" --enable=information --enable=portability --inconclusive"
# CHECK_CONFIG+=" --check-config"  # enable to see problems with setup
CHECK_CONFIG+=" $CPPCHECK_EXTRA_ARG"

# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=

# base file to check whether the current process has been called by the wrapper
WRAPPERPIDFILE=/tmp/cppcheck-wrapper-pid

# location of this script
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")
LOG="$SCRIPTDIR/cppcheck-preprocess.log"

# load the library
source $SCRIPTDIR/../ols-library.sh || exit 1

# forwarded options (options of the actual compiler call that should be
# forwarded to the define expansion call)
FORWARD_OPTIONS=( )

# preprocess all source files using the provided compiler $1
function preprocess
{
  local compiler="$1"
  local suffix="$2"
  local i=0
  local source_files=( )
  local skip_next=0
  local use_next=0

  shift 2

  NEWARGV=( )
  for a in "$@"
  do
    if [ $skip_next -eq 1 ]
    then
      skip_next=0
      continue
    fi
    # handle part of split options that have to be forwarded
    if [ $use_next -eq 1 ]
    then
      use_next=0
      NEWARGV+=( "$a" )
      continue
    fi

    # we are only interested in "-I" and "-D"
    case "$a" in
      -M|-MM) return 1 ;; # updates make rules only
      -E) return 0 ;; # invoked as preprocessor, we're not interested
      -MMD | -MP | -MD) true ;;
      -MT | -MF) skip_next=1 ;;
      -c) true ;;
      -S) true ;;
      -o) skip_next=1 ;;
      -o*) true ;;
      -Wp*) true ;;
      # collect -D* and -I* without space
      -D* | -I* ) NEWARGV+=( "$a" );;
      # handle split options that need to be forwarded
      -D | -I ) NEWARGV+=( "$a" ); use_next=1;;
      # options that do not need to be treated specially
      -*) true ;;
      # collect files
      *.c|*.cc|*.cpp|*.c++|*.C) source_files+=( "$a" ) ;;
      # we are not interested in object files
      *.o) true ;;
      *) NEWARGV+=( "$a" ) ;;
    esac
  done

  if [ ${#source_files[@]} -eq 0 ]
  then
    logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "no source files found, skip preprocessing"
    return 1
  fi
  
  # create parameters to be forwarded to cppcheck
  logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "set command: set -- ${NEWARGV[@]} -E -o /dev/stdout"
  set -- "${NEWARGV[@]}" $CHECK_CONFIG

  base=$(readlink -e $SCRIPTDIR/../../)
  for f in "${source_files[@]}"
  do
    # print cppcheck output to a unique file
    rf=$(readlink -e "$f")
    [ -z "$CALL_DIR" ] || rf=${rf#$CALL_DIR}
    rf=$SCRIPTDIR/results/${rf////_} #  ${rf##$base/}
    mkdir -p $(dirname $rf)
    logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "log cppcheck results: $f to $rf"
    logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "cppcheck $* --template='{file}:{line}: ({severity}:{id}) {message}' $f"
    # in case the source file is analyzed multiple times, collect all messages
    CPPC_STATUS=0
    cppcheck "$@" --template='{file}:{line}: ({severity}:{id}) {message}' "$f" &>> "$rf" || CPPC_STATUS=$?
    logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "cppcheck returned with $CPPC_STATUS"
  done
}

#
# start of the script
#
# redirect stdin to another file descriptor (here we picked 4), and close stdin afterwards
# use this to pass stdin to the actual compiler call, and not to tools used before
REDIRECT_STDIN=0
if [ -t 0 ]
then
  exec 4<&0
  exec 0<&-
  REDIRECT_STDIN=1
fi

# use the binary name
binary_name=$(basename $0)

NATIVE_TOOL=
case "$binary_name" in
  "$TOOLPREFIX""cc""$TOOLSUFFIX" | "$TOOLPREFIX""gcc""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GCC ;;
  "$TOOLPREFIX""c++""$TOOLSUFFIX" | "$TOOLPREFIX""g++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GPP ;;
  "$TOOLPREFIX""clang""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANG ;;
  "$TOOLPREFIX""clang++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANGPP ;;
  *)
    logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}"  "error: cppcheck wrapper has been called with an unknown tool name: $binary_name"
    exit 1
    ;;
esac

if [ $NATIVE_TOOL = "/bin/true" ]
then
  NATIVE_TOOL=$(next_in_path $binary_name cppcheck)
fi

# check whether some parent is the wrapper already
called_by_wrapper $$
parent_result=$?

logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "called $binary_name with $*, parent is cppcheck wrapper: $parent_result"

# if wrapper is not yet active in the calling tree
if [ "$parent_result" != "1" ]
then
  # free the lock and the parent pid file in case something gets wrong
  trap exit_handler EXIT

  # tell that we are using the wrapper now with the current PID
  touch "$WRAPPERPIDFILE$$"

  logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "preprocessing with $binary_name using $NATIVE_TOOL"
  # use the actual compiler binary
  case "$binary_name" in
    "$TOOLPREFIX""cc""$TOOLSUFFIX" | "$TOOLPREFIX""gcc""$TOOLSUFFIX" | \
      "$TOOLPREFIX""clang" )
      preprocess "$NATIVE_TOOL" "c" "$@"
      ;;
    "$TOOLPREFIX""c++""$TOOLSUFFIX" | "$TOOLPREFIX""g++""$TOOLSUFFIX" | "$TOOLPREFIX""clang++""$TOOLSUFFIX" )
      preprocess "$NATIVE_TOOL" "cpp" "$@"
      ;;
    *)
      logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}"  "error: cppcheck wrapper has been called with an unknown tool name: $binary_name"
      exit 1
      ;;
  esac
fi

logwrapper "${TOOLPREFIX}"CPPCHECK"${TOOLSUFFIX}" "call native $NATIVE_TOOL $@"
[ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
$NATIVE_TOOL "$@" $GCCEXTRAARGUMENTS
