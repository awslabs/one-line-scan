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
# Call smatch with used compiler flags and store output in the log directory.
# Continue compilation as usual.

#################### DO NOT MODIFY ##################

# by default, all supported tools have not been found.
NATIVE_GCC=/bin/false
NATIVE_GPP=/bin/false
NATIVE_CLANG=/bin/false
NATIVE_CLANGPP=/bin/false
TOOLPREFIX=
TOOLSUFFIX=
# SMATCH_EXTRA_ARG= # use from environment, if specified at all
CALL_DIR=

# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=

# base file to check whether the current process has been called by the wrapper
WRAPPERPIDFILE=/tmp/smatch-wrapper-pid

# location of this script
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")
LOG="$SCRIPTDIR/smatch-preprocess.log"

# load the library
source "$SCRIPTDIR"/../ols-library.sh || exit 1

# run smatch against provided call
function run_smatch
{
  local source_files=( )
  local header_files=( )
  local skip_next=0
  local forward_next=0
  local mode=c

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
    if [ $forward_next -eq 1 ]
    then
      forward_next=0
      NEWARGV+=( "$a" )
      continue
    fi
    case "$a" in
      -M|-MM) return 1 ;; # updates make rules only
      -E) return 1 ;; # invoked as preprocessor only
      -MMD | -MP | -MD) true ;;
      -MT | -MF) skip_next=1 ;;
      -c) true ;;
      -include) true ;;  # treat .h as source file, and drop the -include parameter
      -S) mode=S ;;
      -o) skip_next=1 ;;
      -o*) true ;;
      -Wp*) true ;;
      -iwithprefix) skip_next=1 ;; # will skip over -iwithprefix include
      # memorize options for call to fortify
      -std*|-specs=*|-f*|-W*|-m*|-O*) NEWARGV+=( "$a" );;
      # handle split options that need to be forwarded
      -specs) NEWARGV+=( "$a" ); forward_next=1;;
      # options that do not need to be treated specially
      -*) NEWARGV+=( "$a" ) ;;
      # collect files
      *.c|*.cc|*.cpp|*.c++|*.C) source_files+=( "$a" ) ;;
      *.h) header_files+=( "$a" ) ;;
      *) NEWARGV+=( "$a" ) ;;
    esac
  done

  if [ ${#source_files[@]} -eq 0 ]
  then
    logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "no source files found, skip preprocessing"
    return 1
  fi

  logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "set command: set -- ${NEWARGV[@]} -E -o /dev/stdout"
  set -- "${NEWARGV[@]}"

  # use the first source file as representative
  f="${source_files[0]}"

  # print smatch output to a unique file
  rf=$(readlink -e "$f")
  [ -z "$CALL_DIR" ] || rf=${rf#$CALL_DIR}
  rf=$SCRIPTDIR/results/${rf////_}
  mkdir -p "$(dirname "$rf")"
  logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "log smatch results: $f to $rf"
  logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "smatch $SMATCH_EXTRA_ARG $@"
  # in case the source file is analyzed multiple times, collect all messages
  SMATCH_STATUS=0

  # do detour via cgcc, which applies smatch specific command line massaging
  export CHECK="smatch $SMATCH_EXTRA_ARG "
  cgcc -no-compile "$@" "${source_files[@]}" "${header_files[@]}" >> "$rf" 2>> "$rf".err || SMATCH_STATUS=$?
  unset CHECK

  logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "run smatch via cgcc [cgcc -no-compile $@ ${source_files[@]} ${header_files[@]}] in [$(pwd)] with [CHECK=$CHECK]"
  logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "smatch returned with $SMATCH_STATUS"
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
binary_name=$(basename "$0")

NATIVE_TOOL=
case "$binary_name" in
  "$TOOLPREFIX""cc""$TOOLSUFFIX" | "$TOOLPREFIX""gcc""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GCC ;;
  "$TOOLPREFIX""c++""$TOOLSUFFIX" | "$TOOLPREFIX""g++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GPP ;;
  "$TOOLPREFIX""clang""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANG ;;
  "$TOOLPREFIX""clang++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANGPP ;;
  *)
    logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}"  "error: smatch wrapper has been called with an unknown tool name: $binary_name"
    exit 1
    ;;
esac

if [ $NATIVE_TOOL = "/bin/true" ]
then
  NATIVE_TOOL=$(next_in_path "$binary_name" smatch)
fi

# check whether some parent is the wrapper already
called_by_wrapper $$
parent_result=$?

logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "called $binary_name with $*, parent is smatch wrapper: $parent_result"

logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "call native $NATIVE_TOOL $@"
[ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
NATIVE_STATUS=0
$NATIVE_TOOL "$@" $GCCEXTRAARGUMENTS || NATIVE_STATUS=$?

# free the lock and the parent pid file in case something gets wrong
trap exit_handler EXIT

# tell that we are using the wrapper now with the current PID
touch "$WRAPPERPIDFILE$$"

# run smatch
logwrapper "${TOOLPREFIX}"SMATCH"${TOOLSUFFIX}" "running smatch with $binary_name"
run_smatch "$@" || true

# return with the exit code of the native tool
exit $NATIVE_STATUS
