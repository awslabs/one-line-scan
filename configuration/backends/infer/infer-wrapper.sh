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
# Wrap all compiler calls so that we can
#  * log the call with its options and directory
#  * extend the call by further arguments that are added at the end of the call

#################### DO NOT MODIFY ##################

# by default, all supported tools have not been found.
NATIVE_AS=/bin/false
NATIVE_GCC=/bin/false
NATIVE_GPP=/bin/false
NATIVE_CLANG=/bin/false
NATIVE_CLANGPP=/bin/false
NATIVE_LD=/bin/false

TOOLPREFIX=
TOOLSUFFIX=

# directory name used to lock concurrent access
LOCKDIR=XX/tmp/infer-wrapper-lockXX
TRAPDIR=

# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=

# directory from which the tool has been called for build
CALL_DIR=

# base file to check whether the current process has been called by the wrapper
WRAPPERPIDFILE=/tmp/infer-wrapper-pid

# location of this script (after being installed for the specific build call)
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")
LOG="$SCRIPTDIR/infer-preprocess.log"
CALLLOG="$SCRIPTDIR/calls.json"
REPLAYLOG="$SCRIPTDIR/replay.log"
FAILLOG="$SCRIPTDIR/failed_calls.log"

OUTPUT_DIR_BASE="$SCRIPTDIR" # Directory to store infer output to

# load the library
source $SCRIPTDIR/../ols-library.sh || exit 1

# forwarded options (options of the actual compiler call that should be
# forwarded to the define expansion call)
FORWARD_OPTIONS=()

# this function returns if it has been able to create "$LOCKDIR"
function lock_infer() {
  # grep lock and write json log entry
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    # busy waiting, not putting too much load on the file system, but not waiting too long
    sleep 0.05
  done

  # tell trap about the directory only after we actually hold the lock
  TRAPDIR="$LOCKDIR"
}

function unlock_infer() {
  # free the lock again
  rm -rf "$TRAPDIR"
  TRAPDIR=
}

# log calls to non-compiler tools
function log_tool_call() {
  local tool="$1"
  shift 1

  # lock, and create the file entries
  lock_infer
  printf "cd %s; %s %s\n" "$(pwd)" "$tool" "$@" >>"$REPLAYLOG"
  unlock_infer
}

# process compiler call with compiler $1 and suffix $2
function log_compiler_call() {
  local compiler="$1"
  local suffix="$2"

  local -a SOURCE_FILES=( )
  local -i skip_next=0
  local -i output_next=0
  local -i use_next_include=0
  local -i use_next_macro=0
  local OUTPUT="-"

  shift 2

  local -a NEWARGV=( )
  local -a INCLUDES=( )
  local -a MACROS=( )

  # collect the relevant pieces of the CLI, essentially source files and output
  for a in "$@"
  do
    if [ "$output_next" -eq 1 ]
    then
      OUTPUT="$a"
      output_next=0
    fi
    if [ $skip_next -eq 1 ]
    then
      skip_next=0
      continue
    fi
    # handle part of split options that have to be forwarded
    if [ $use_next_include -eq 1 ]
    then
      use_next_include=0
      INCLUDES+=( "$a" )
      continue
    fi
    if [ $use_next_macro -eq 1 ]
    then
      use_next_macro=0
      MACROS+=( "$a" )
      continue
    fi

    # we are interested in "-o" and source files
    case "$a" in
      -M|-MM) return 1 ;; # updates make rules only
      -MMD | -MP | -MD) true ;;
      -MT | -MF) skip_next=1 ;;
      -c) true ;;
      -S) true ;;
      -o) skip_next=1; output_next=1 ;;
      -o*) true ;;
      -Wp*) true ;;
      # collect -D*, -U* and -I* without space
      -D* | -U* ) MACROS+=( "$a" );;
      -I* ) INCLUDES+=( "$a" );;
      # handle split options that need to be forwarded
      -D | -U ) MACROS+=( "$a" ); use_next_macro=1;;
      -I ) INCLUDES+=( "$a" ); use_next_include=1;;
      # options that do not need to be treated specially
      -*) true ;;
      # collect files
      *.c|*.cc|*.cpp|*.c++|*.C) SOURCE_FILES+=( "$a" ) ;;
      # we are not interested in object files
      *.o) true ;;
      *) NEWARGV+=( "$a" ) ;;
    esac
  done

  # create the JSON blob to log for each source file
  local -a COMMAND_ARRAY=("$compiler")
  COMMAND_ARRAY+=("$@")
  local JSON_COMMAND
  JSON_COMMAND="$(printf '%s\n' "${COMMAND_ARRAY[@]}" | jq -R . | jq -sc .)"

  mkdir -p "$OUTPUT_DIR_BASE"/deps_output

  # write an ouput for each file
  for OUTPUT_FILE in "${SOURCE_FILES[@]}"
  do
    # make sure the output name is unique
    OUTPUT_DEPS_FILE="$(echo "${PWD}$@${OUTPUT_FILE}" | tr -d " /" | md5sum | awk '{print $1}')"
    OUTPUT_DEPS_FILE="$(date +%s%N)_$OUTPUT_DEPS_FILE" # make sure we can sort by precise timestamp
    OUTPUT_DEPS_FILE="$OUTPUT_DIR_BASE"/deps_output/"$OUTPUT_DEPS_FILE"

    echo "$PWD: ${COMMAND_ARRAY[@]}" >> "$OUTPUT_DEPS_FILE".log
    echo "{ \"directory\": \"$PWD\", \"file\": \"$OUTPUT_FILE\", \"output\": \"$OUTPUT\", \"arguments\": $JSON_COMMAND }," >> "$OUTPUT_DEPS_FILE".json
  done
}

#
# start of the script
#
# redirect stdin to another file descriptor (here we picked 4), and close stdin afterwards
# use this to pass stdin to the actual compiler call, and not to tools used before
REDIRECT_STDIN=0
if [ -t 0 ]; then
  exec 4<&0
  exec 0<&-
  REDIRECT_STDIN=1
fi

# the directory, in which the lock directory should be created, has to exist
# otherwise the wrapper is broken (and the locking mkdir would block forever)
LOCK_PARENT_DIR="$(dirname $LOCKDIR)"
if [ ! -d "$LOCK_PARENT_DIR" ]; then
  echo "error: goto-gcc wrapper is broken" >&2
  exit 1
fi

# use the binary name
binary_name=$(basename $0)

NATIVE_TOOL=
case "$binary_name" in
"${TOOLPREFIX}as${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_AS ;;
"$TOOLPREFIX""cc""$TOOLSUFFIX" | "$TOOLPREFIX""gcc""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GCC ;;
"$TOOLPREFIX""c++""$TOOLSUFFIX" | "$TOOLPREFIX""g++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_GPP ;;
"$TOOLPREFIX""clang""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANG ;;
"$TOOLPREFIX""clang++""$TOOLSUFFIX") NATIVE_TOOL=$NATIVE_CLANGPP ;;
"${TOOLPREFIX}ld${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_LD ;;
*)
  logwrapper "${TOOLPREFIX}"INFER"${TOOLSUFFIX}" "error: infer wrapper has been called with an unknown tool name: $binary_name"
  exit 1
  ;;
esac

if [ $NATIVE_TOOL = "/bin/true" ]; then
  NATIVE_TOOL=$(next_in_path $binary_name infer)
fi

# check whether some parent is the wrapper already
called_by_wrapper $$
parent_result=$?
logwrapper "${TOOLPREFIX}"INFER"${TOOLSUFFIX}" "called $binary_name with $*, parent is infer wrapper: $parent_result"

# if wrapper is not yet active in the calling tree
if [ "$parent_result" != "1" ]; then
  # free the lock and the parent pid file in case something gets wrong
  trap exit_handler EXIT

  # tell that we are using the wrapper now with the current PID
  touch "$WRAPPERPIDFILE$$"

  logwrapper "${TOOLPREFIX}"INFER"${TOOLSUFFIX}" "processing with $binary_name using $NATIVE_TOOL"
  # use the actual compiler binary
  case "$binary_name" in
  "$TOOLPREFIX""cc""$TOOLSUFFIX" | "$TOOLPREFIX""gcc""$TOOLSUFFIX" | \
    "$TOOLPREFIX""clang")
    log_compiler_call "$NATIVE_TOOL" "c" "$@"
    ;;
  "$TOOLPREFIX""c++""$TOOLSUFFIX" | "$TOOLPREFIX""g++""$TOOLSUFFIX" | "$TOOLPREFIX""clang++""$TOOLSUFFIX")
    log_compiler_call "$NATIVE_TOOL" "cpp" "$@"
    ;;
  "$TOOLPREFIX""ld""$TOOLSUFFIX")
    log_tool_call "$NATIVE_TOOL" "$@"
    ;;
  "$TOOLPREFIX""as""$TOOLSUFFIX")
    log_tool_call "$NATIVE_TOOL" "$@"
    ;;
  *)
    logwrapper "${TOOLPREFIX}"INFER"${TOOLSUFFIX}" "error: infer wrapper has been called with an unknown tool name: $binary_name"
    exit 1
    ;;
  esac
fi

STATUS=0
logwrapper "${TOOLPREFIX}"INFER"${TOOLSUFFIX}" "call native $NATIVE_TOOL $@"
[ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
"$NATIVE_TOOL" "$@" || STATUS=$?

# log failed calls
if [ "$STATUS" -ne 0 ]; then
  lock_infer
  echo "exit with $STATUS: cd $(pwd); $NATIVE_TOOL $@ $GCCEXTRAARGUMENTS" >>"$FAILLOG"
  unlock_infer
fi

exit $STATUS
