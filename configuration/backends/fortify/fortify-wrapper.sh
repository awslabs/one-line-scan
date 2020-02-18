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
# Control whether gcc has been called by Fortify, or some other tool

#################### DO NOT MODIFY ##################

# by default, all supported tools have not been found.
NATIVE_GCC=/bin/false
NATIVE_GPP=/bin/false
NATIVE_CLANG=/bin/false
NATIVE_CLANGPP=/bin/false
TOOLPREFIX=
TOOLSUFFIX=

# path to the actual Fortify sourceanalyzer (SCA)
NATIVE_SCA_PATH=
FORTIFY_BUILD_ID=XXBUILDIDXX
FORTIFY_OPTS=

# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=

# base file to check whether the current process has been called by the wrapper
WRAPPERPIDFILE=/tmp/Fortify-wrapper-pid

# location of this script
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")
LOG="$SCRIPTDIR/fortify-preprocess.log"

# load the library
source $SCRIPTDIR/../ols-library.sh || exit 1

# forwarded options (options of the actual compiler call that should be
# forwarded to the Fortify call)
FORWARD_OPTIONS=( )
FORTIFY_FILES=( )

# preprocess all source files using the provided compiler $1
function preprocess
{
  local compiler="$1"
  local suffix="$2"
  local i=0
  local source_files=( )
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
      FORWARD_OPTIONS+=( "$a" )
      continue
    fi
    case "$a" in
      -M|-MM) return 1 ;; # updates make rules only
      -E) return 1 ;; # invoked as preprocessor only
      -MMD | -MP | -MD) true ;;
      -MT | -MF) skip_next=1 ;;
      -c) true ;;
      -S) mode=S ;;
      -o) skip_next=1 ;;
      -o*) true ;;
      -Wp*) true ;;
      # memorize options for call to fortify
      -std*|-specs=*|-f*|-W*|-m*|-O*) NEWARGV+=( "$a" ); FORWARD_OPTIONS+=( "$a" );;
      # handle split options that need to be forwarded
      -specs) NEWARGV+=( "$a" ); FORWARD_OPTIONS+=( "$a" ) ; forward_next=1;;
      # options that do not need to be treated specially
      -*) NEWARGV+=( "$a" ) ;;
      # collect files
      *.c|*.cc|*.cpp|*.c++|*.C) source_files+=( "$a" ) ;;
      *) NEWARGV+=( "$a" ) ;;
    esac
  done

  FORWARD_OPTIONS+=( "-$mode" )

  if [ ${#source_files[@]} -eq 0 ]
  then
    logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "no source files found, skip preprocessing"
    return 1
  fi
  
  logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "set command: set -- ${NEWARGV[@]} -E -o /dev/stdout"
  set -- "${NEWARGV[@]}" -E -o /dev/stdout

  for f in "${source_files[@]}"
  do
    rd=$(dirname "$f")
    tmpfile=$(TMPDIR="$rd" mktemp -t fortify-preprocessedXXXXXX)
    logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "create fortify source: $f to $tmpfile.$suffix"
    "$compiler" "$@" "$f" $GCCEXTRAARGUMENTS > $tmpfile.$suffix
    rm $tmpfile
    FORTIFY_FILES+=( "$tmpfile.$suffix" )
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
  "$TOOLPREFIX""cc""${TOOLSUFFIX}" | "$TOOLPREFIX""gcc""${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_GCC ;;
  "$TOOLPREFIX""c++""${TOOLSUFFIX}" | "$TOOLPREFIX""g++""${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_GPP ;;
  "$TOOLPREFIX""clang""${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_CLANG ;;
  "$TOOLPREFIX""clang++""${TOOLSUFFIX}") NATIVE_TOOL=$NATIVE_CLANGPP ;;
  *)
    echo "error: Fortify wrapper has been called with an unknown tool name: $binary_name" 2>&1
    exit 1
    ;;
esac

if [ $NATIVE_TOOL = "/bin/true" ]
then
  NATIVE_TOOL=$(next_in_path $binary_name Fortify)
fi

# check whether some parent is the wrapper already
called_by_wrapper $$
parent_result=$?

logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "called $binary_name, parent is Fortify wrapper: $parent_result"

# if wrapper is not yet active in the calling tree
if [ "$parent_result" != "1" ]
then
  # free the lock and the parent pid file in case something gets wrong
  trap exit_handler EXIT

  # tell that we are using the wrapper now with the current PID
  touch "$WRAPPERPIDFILE$$"

  # make sure we create our artificial compiler somewhere, where we can write
  fortify_code=0
  tmpdir=$(mktemp -d -t fortify.XXXXXX ) || fortify_code=1
  tmpdir=$(readlink -f $tmpdir) || fortify_code=1

  if [ "$fortify_code" -ne 0 ]
  then
    logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "creating temporary directory in $(pwd) falied, skip fortify compilation for call: $@"
    exit $fortify_code
  fi

  logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "preprocessing with $binary_name using $NATIVE_TOOL to $tmpdir/"
  # use the actual compiler binary
  case "$binary_name" in
    "$TOOLPREFIX""cc""${TOOLSUFFIX}" | "$TOOLPREFIX""gcc""${TOOLSUFFIX}" | \
      "$TOOLPREFIX""clang""${TOOLSUFFIX}" )
      # rename the currently used compiler to "gcc", such that Fortify can
      # work with it
      ln -s $NATIVE_TOOL $tmpdir/gcc
      if preprocess "$NATIVE_TOOL" "c" "$@"
      then
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "run fortify analysis: "
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "original command line: $binary_name $@"
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "$NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" $FORTIFY_OPTS $tmpdir/gcc ${FORTIFY_FILES[@]} ${FORWARD_OPTIONS[@]} $GCCEXTRAARGUMENTS"
        # execute source analyzer (eventually load different environment for java)
        load_ols_env &> $LOG
        if [ $REDIRECT_STDIN -eq 1 ]
        then
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/gcc "${FORTIFY_FILES[@]}" "${FORWARD_OPTIONS[@]}" $GCCEXTRAARGUMENTS \
            >  >(tee -a "$LOG") \
            2> >(tee -a "$LOG" 1>&2)
        else
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/gcc "${FORTIFY_FILES[@]}" "${FORWARD_OPTIONS[@]}" $GCCEXTRAARGUMENTS
        fi
        fortify_code=$?
        # unload environment again
        unload_ols_env &> $LOG
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "exit code $fortify_code"
        for f in "${FORTIFY_FILES[@]}"
        do
          rm -f "$f" $(basename "${f/%.c/.o}")
        done
      else
        logwrapper "${TOOLPREFIX}"FORTIFY "run fortify link-time analysis: "
        logwrapper "${TOOLPREFIX}"FORTIFY "original command line: $binary_name $@"
        logwrapper "${TOOLPREFIX}"FORTIFY "$NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" $FORTIFY_OPTS $tmpdir/gcc $@ $GCCEXTRAARGUMENTS"
        # execute source analyzer (eventually load different environment for java)
        load_ols_env &> $LOG
        if [ $REDIRECT_STDIN -eq 1 ]
        then
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/gcc "$@" $GCCEXTRAARGUMENTS \
            >  >(tee -a "$LOG") \
            2> >(tee -a "$LOG" 1>&2)
        else
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/gcc "$@" $GCCEXTRAARGUMENTS
        fi
        fortify_code=$?
        # unload environment again
        unload_ols_env &> $LOG
        logwrapper "${TOOLPREFIX}"FORTIFY "exit code $fortify_code"
      fi
      ;;
    "$TOOLPREFIX""c++""${TOOLSUFFIX}" | "$TOOLPREFIX""g++""${TOOLSUFFIX}" | "$TOOLPREFIX""clang++""${TOOLSUFFIX}" )
      # rename the currently used compiler to "g++", such that Fortify can
      # work with it
      ln -s $NATIVE_TOOL $tmpdir/g++
      if preprocess "$NATIVE_TOOL" "cpp" "$@"
      then
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "run fortify analysis: "
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "$NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" $FORTIFY_OPTS $tmpdir/g++ ${FORTIFY_FILES[@]} ${FORWARD_OPTIONS[@]} $GCCEXTRAARGUMENTS"
        # execute source analyzer (eventually load different environment for java)
        load_ols_env &> $LOG
        if [ $REDIRECT_STDIN -eq 1 ]
        then
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/g++ "${FORTIFY_FILES[@]}" "${FORWARD_OPTIONS[@]}" $GCCEXTRAARGUMENTS \
            >  >(tee -a "$LOG") \
            2> >(tee -a "$LOG" 1>&2)
        else
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/g++ "${FORTIFY_FILES[@]}" "${FORWARD_OPTIONS[@]}" $GCCEXTRAARGUMENTS
        fi
        fortify_code=$?
        # unload environment again
        unload_ols_env &> $LOG
        logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "exit code $fortify_code"
        for f in "${FORTIFY_FILES[@]}"
        do
          rm -f "$f" $(basename "${f/%.cpp/.o}")
        done
      else
        logwrapper "${TOOLPREFIX}"FORTIFY "run fortify link-time analysis: "
        logwrapper "${TOOLPREFIX}"FORTIFY "$NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" $FORTIFY_OPTS $tmpdir/g++ $@ $GCCEXTRAARGUMENTS"
        # execute source analyzer (eventually load different environment for java)
        load_ols_env &> $LOG
        if [ $REDIRECT_STDIN -eq 1 ]
        then
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/g++ "$@" $GCCEXTRAARGUMENTS \
            >  >(tee -a "$LOG") \
            2> >(tee -a "$LOG" 1>&2)
        else
          $NATIVE_SCA_PATH -b "$FORTIFY_BUILD_ID" -nc $FORTIFY_OPTS \
            $tmpdir/g++ "$@" $GCCEXTRAARGUMENTS
        fi
        fortify_code=$?
        # unload environment again
        unload_ols_env &> $LOG
        logwrapper "${TOOLPREFIX}"FORTIFY "exit code $fortify_code"
      fi
      ;;
    *)
      echo "error: Fortify wrapper has been called with an unknown tool name: $binary_name" 2>&1
      rm -r $tmpdir
      exit 1
      ;;
  esac
  rm -r $tmpdir
  [ $fortify_code -eq 0 ] || exit $fortify_code
fi

logwrapper "${TOOLPREFIX}"FORTIFY"${TOOLSUFFIX}" "call native $NATIVE_TOOL $@"
[ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
$NATIVE_TOOL "$@" $GCCEXTRAARGUMENTS
