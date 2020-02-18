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
# Lock wrapping call to goto-cc, to avoid too high memory consumption
#

# useful for debugging the tool chain
#USE_GDB="gdb --args"
#ECHOCOMMAND="echo"
ECHOCOMMAND="true" # use a command that simply consumes all arguments
# if log file is not empty, store logging in wrapper-log.txt in the wrapper installation directory
LOG=log
#GOTO_CC_EXTRA_ARGUMENTS="--verbosity 10"



#################### DO NOT MODIFY ##################

# global variables, will be modified during setup.sh
#
NATIVE_COMPILER=XX/usr/bin/gccXX
NATIVE_LINKER=XX/usr/bin/ldXX
NATIVE_AR=XX/usr/bin/arXX
GOTO_GCC_BINARY=XX/usr/bin/goto-gccXX
GOTO_BCC_BINARY=XX/usr/bin/goto-bccXX
GOTO_LD_BINARY=XX/usr/bin/goto-ldXX
GOTO_DIFF_BINARY=XX/usr/bin/goto-diffXX
GOTO_AS_BINARY=XX/usr/bin/goto-asXX
GOTO_AS86_BINARY=XX/usr/bin/goto-as86XX
NATIVE_BCC=
NATIVE_AS=
NATIVE_AS86=
# arguments that should be added to the compiler (DO NOT TOUCH)
GCCEXTRAARGUMENTS=
ENFORCE_GOTO_LINKING=1
NUM_LOCKS=4
TOOLPREFIX=
TOOLSUFFIX=
INCLUDE_WARNINGS=

# simply wrap these two, to later be able to have statistics
NATIVE_COMPILER_GPP=
NATIVE_COMPILER_CLANG=
NATIVE_COMPILER_CLANGPP=

# directory name used to lock concurrent access
LOCKDIR=XX/tmp/goto-gcc-wrapper-lockXX
WRAPPERPIDFILE=/tmp/goto-gcc-wrapper-pid
TRAPDIR=

# load the library
SCRIPT=$(readlink -e "$0")
source $(dirname $SCRIPT)/ols-library.sh || exit 1

# store the binary in binaries.list; only, if we do not use an intermediate file
function storeBinary
{
  use_next=0
  outputfile="a.out"
  [ "$PERSONALITY" != "AR" ] || outputfile="/dev/null"
  for a in "$@"
  do
    case "$a" in
      -E|-c|-S) return 0 ;;
      -o) use_next=1 ;;
      -b) [ "$PERSONALITY" != "AS86" ] || use_next=1 ;;
      -o*) outputfile=$(echo $a | sed 's/^-o//') ;;
      -b*) [ "$PERSONALITY" != "AS86" ] || outputfile=$(echo $a | sed 's/^-o//') ;;
      *.a)
        if [ $use_next -eq 1 ] || [ "$PERSONALITY" = "AR" ]
        then
          use_next=0
          outputfile=$a
        fi
        ;;
      *)
        if [ $use_next -eq 1 ]
        then
          use_next=0
          outputfile=$a
        fi
        ;;
    esac
  done

  case "$outputfile" in
    /dev/null) return 0 ;;
    *.so|*.a) full_path "$outputfile" >> $LOCK_PARENT_DIR/libraries.list ;;
    *) full_path "$outputfile" >> $LOCK_PARENT_DIR/binaries.list ;;
  esac
}

# for certain binaries, no goto-ld section is required
# hence, select the output file from ld and remove the goto-cc section
function strip_goto ()
{
  logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "check strip-goto for $@"
  use_next=0
  outputfile="a.out"
  for a in "$@"
  do
    case "$a" in
      -o) use_next=1 ;;
      -o*) outputfile=$(echo $a | sed 's/^-o//') ;;
      *)
        if [ $use_next -eq 1 ]
        then
          use_next=0
          outputfile=$a
        fi
        ;;
    esac
  done
  if [ -f "$outputfile" ] && [[ "$(basename "$outputfile")" =~ .xen.efi.(.*).0 ]]
  then
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "remove goto section from $(readlink -e "$outputfile")"
    objcopy -R goto-cc "$outputfile" "${outputfile}.removed-gotocc"
    mv "${outputfile}.removed-gotocc" "${outputfile}"
  fi
}

# check the compiler commandline, and print the md5sum of the output binary, as
# well as the full location
function logOutputfileHash()
{
  local BINARY="$(basename "$1")"
  shift
  use_next=0
  outputfile="a.out"
  [ "$PERSONALITY" != "AR" ] || outputfile="/dev/null"
  for a in "$@"
  do
    case "$a" in
      -o) use_next=1 ;;
      -b) [ "$PERSONALITY" != "AS86" ] || use_next=1 ;;
      -o*) outputfile=$(echo $a | sed 's/^-o//') ;;
      -b*) [ "$PERSONALITY" != "AS86" ] || outputfile=$(echo $a | sed 's/^-o//') ;;
      *.a)
        if [ $use_next -eq 1 ] || [ "$PERSONALITY" = "AR" ]
        then
          use_next=0
          outputfile=$a
        fi
        ;;
      *)
        if [ $use_next -eq 1 ]
        then
          use_next=0
          outputfile=$a
        fi
        ;;
    esac
  done

  case "$outputfile" in
    /dev/null) return 0 ;;
    *)         [ ! -f "$outputfile" ] || logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "tool $BINARY wrote output file $(full_path "$outputfile") with md5 $(md5sum "$outputfile" | cut -d' ' -f1)" ;;
  esac
}

# test whether we are pre-processing only -- just call the native tool in that
# case
function preprocess_only
{
  if [ "$PERSONALITY" != "CC" ]
  then
    return 1
  fi

  for a in "$@"
  do
    if [ "x$a" = "x-E" ]
    then
      return 0
    fi
  done

  return 1
}

# store the binary in binaries.list; only, if we do not use an intermediate file
function checkIncludes
{
  [ "$PERSONALITY" = "CC" ] || return 0

  local goto_cc="$1"
  local native_cc="$2"
  shift 2

  # build a new compiler command line to be used with a single source file at
  # a time; compile only, and output to a newly chosen file
  local NEW_ARGV=( )
  local skip_next=0
  local source_files=( )
  for a in "$@"
  do
    [ $skip_next -eq 0 ] || continue
    case "$a" in
      -E|-c|-S) true ;;
      -o) skip_next=1 ;;
      -o*) true ;;
      -*) NEW_ARGV+=( "$a" ) ;;
      *.c|*.C) source_files+=( "$a" ) ;;
      *) NEW_ARGV+=( "$a" ) ;;
    esac
  done

  if [ ${#source_files[@]} -eq 0 ]
  then
    return 0
  fi

  set -- "${NEW_ARGV[@]}" -c

  # try to compile each source file and compare the compilation result to the
  # original source's result, using goto-diff
  for f in "${source_files[@]}" ; do
    local rf=$(full_path "$f")
    local rd=$(dirname "$rf")
    local tmpfile=$(TMPDIR="$rd" mktemp -t include-checkXXXXXX)
    local TMPFILES=( "$tmpfile" )

    if ! grep -q "^[[:space:]]*#include" "$f"
    then
      rm -f "${TMPFILES[@]}"
      continue
    fi

    TMPFILES+=( "$tmpfile.c" )
    TMPFILES+=( "$tmpfile.o" )
    TMPFILES+=( "${tmpfile}-i.o" )
    cp "$f" "$tmpfile.c"
    if ! $goto_cc --native-compiler $native_cc "$@" "$tmpfile.c" -o "$tmpfile.o" \
      >  >(tee -a "$LOG") \
      2> >(tee -a "$LOG" 1>&2)
    then
      rm -f "${TMPFILES[@]}"
      return 1
    fi

    for l in $(grep -n "^[[:space:]]*#include" "$f" | cut -f1 -d:)
    do
      cat "$f" | sed "${l}s/.*/ /" > "$tmpfile.c"
      $goto_cc --native-compiler $native_cc "$@" "$tmpfile.c" -o "$tmpfile.o" \
        >/dev/null 2>&1 || continue
      local inc=$(sed -n "${l}p" "$f" | \
                  sed -e 's/^.*#include[[:space:]]*[<"]//' \
                      -e 's/[>"][[:space:]]*$//')
      if $GOTO_DIFF_BINARY -u "$tmpfile.o" "${tmpfile}-i.o" | grep -q "^[+-]"
      then
        echo "$f:$l: warning: code compiles both with and without $inc, but instructions differ" \
          | tee -a "$LOG"
      else
        echo "$f:$l: warning: (not) including $inc has no effect" \
          | tee -a "$LOG"
      fi
    done

    rm -f "${TMPFILES[@]}"
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
  REDIRECT_STDIN=1
  exec 4<&0
  exec 0<&-
fi

# the directory, in which the lock directory should be created, has to exist
# otherwise the wrapper is broken (and the locking mkdir would block forever)
LOCK_PARENT_DIR="$(dirname $LOCKDIR)"
if [ ! -d "$LOCK_PARENT_DIR" ]
then
  echo "error: goto-gcc wrapper is broken" >&2
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

PERSONALITY=CC
case "$binary_name" in
  "$TOOLPREFIX""ar${TOOLSUFFIX}") PERSONALITY=AR ;;
  "$TOOLPREFIX""ld${TOOLSUFFIX}") PERSONALITY=LD ;;
  "$TOOLPREFIX""as86") PERSONALITY="AS86" ;;
  "$TOOLPREFIX""as${TOOLSUFFIX}") PERSONALITY=AS ;;
esac

# check whether some parent is the wrapper already
parent_result=0
called_by_wrapper $$ || parent_result=$?

# grep for patterns that should not be run through the analysis
# grep "linux" $@ > /dev/null 2>&1
# pattern_result=$?

# logging
logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "called $binary_name as $$ with $0 $@"
logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "parent is wrapper: $parent_result"

if [ "$parent_result" == 0 ] && preprocess_only "$@"
then
  logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "preprocessing only"
  parent_result=1
fi

# if wrapper is already active somewhere in the calling tree, call original program
if [ "$parent_result" == "1" ]
then
  case "$binary_name" in
    "$TOOLPREFIX""ar${TOOLSUFFIX}")
      if [ "$NATIVE_AR" = "/bin/true" ]
      then
        NATIVE_AR=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_AR $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_AR "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_AR" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""ld${TOOLSUFFIX}")
      if [ "$NATIVE_LINKER" = "/bin/true" ]
      then
        NATIVE_LINKER=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_LINKER $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_LINKER "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_LINKER" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""cc${TOOLSUFFIX}" | "$TOOLPREFIX""gcc${TOOLSUFFIX}")
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER preset: $NATIVE_COMPILER"
      if [ "$NATIVE_COMPILER" = "/bin/true" ]
      then
        NATIVE_COMPILER=$(next_in_path $binary_name)
        logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER next-in-path: $NATIVE_COMPILER"
        # Some GCC packages ship x86_64-unknown-linux-gcc, but do not ship
        # x86_64-unknown-linux-objcopy, as would be expected by goto-gcc. Fix
        # this on-demand
        if [ "$(basename $NATIVE_COMPILER)" = "x86_64-unknown-linux-gnu-gcc" ]
        then
          objcopy_path=$(echo $NATIVE_COMPILER | sed 's/-gcc$/-objcopy/')
          if ! which "$objcopy_path" &>/dev/null
          then
            logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "installing objcopy symlink at $objcopy_path"
            ln -sf $(dirname $objcopy_path)/objcopy "$objcopy_path"
          fi
        fi
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_COMPILER $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_COMPILER "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_COMPILER" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""bcc${TOOLSUFFIX}")
      if [ "$NATIVE_BCC" = "/bin/true" ]
      then
        NATIVE_BCC=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_BCC $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_BCC "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_BCC" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""as86")
      if [ "$NATIVE_AS86" = "/bin/true" ]
      then
        NATIVE_AS86=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_AS86 $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_AS86 "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_AS86" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""as${TOOLSUFFIX}")
      if [ "$NATIVE_AS" = "/bin/true" ]
      then
        NATIVE_AS=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_AS $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_AS "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_AS" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""g++${TOOLSUFFIX}")
      if [ "$NATIVE_COMPILER_GPP" = "/bin/true" ]
      then
        NATIVE_COMPILER_GPP=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_COMPILER_GPP $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_COMPILER_GPP "$@"
      EXITSTATUS=$?
      logOutputfileHash "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""clang${TOOLSUFFIX}")
      if [ "$NATIVE_COMPILER_CLANG" = "/bin/true" ]
      then
        NATIVE_COMPILER_CLANG=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_COMPILER_CLANG $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_COMPILER_CLANG "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_COMPILER_CLANG" "$@"
      exit $EXITSTATUS
      ;;
    "$TOOLPREFIX""clang++${TOOLSUFFIX}")
      if [ "$NATIVE_COMPILER_CLANGPP" = "/bin/true" ]
      then
        NATIVE_COMPILER_CLANGPP=$(next_in_path $binary_name)
      fi
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call native $NATIVE_COMPILER_CLANGPP $@"
      [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
      $NATIVE_COMPILER_CLANGPP "$@"
      EXITSTATUS=$?
      logOutputfileHash "$NATIVE_COMPILER_CLANGPP" "$@"
      exit $EXITSTATUS
      ;;
  esac

  # make sure we do not enter the goto-gcc path again, if there are spaces
  echo "warning: unknown (child) compiler binary name $0 with basename $binary_name" >&2
  exit 1
fi

# free the lock and the parent pid file in case something gets wrong
trap exit_handler EXIT

# tell that we are using the wrapper now with the current PID
touch "$WRAPPERPIDFILE$$"

# if we wrap g++, clang or clang++, update NATIVE_COMPILER
case "$binary_name" in
  "$TOOLPREFIX""g++${TOOLSUFFIX}")
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER_GPP: $NATIVE_COMPILER_GPP"
    NATIVE_COMPILER=$NATIVE_COMPILER_GPP
    ;;
  "$TOOLPREFIX""clang${TOOLSUFFIX}")
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER_CLANG: $NATIVE_COMPILER_CLANG"
    NATIVE_COMPILER=$NATIVE_COMPILER_CLANG
    ;;
  "$TOOLPREFIX""clang++${TOOLSUFFIX}")
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER_CLANGPP: $NATIVE_COMPILER_CLANGPP"
    NATIVE_COMPILER=$NATIVE_COMPILER_CLANGPP
    ;;
esac

# build directory to check whether we have the lock, do not print errors, iterate over 2 locks
PICKLOCK=$(($$ % $NUM_LOCKS))
BASELOCKDIR="$LOCKDIR"
LOCKDIR="$BASELOCKDIR$PICKLOCK"
while ! mkdir "$LOCKDIR" 2> /dev/null
do
  HOLDINGPID=$(cat $LOCKDIR/pid 2> /dev/null)
  logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "PID $$ with name $binary_name waits for the lock held by $HOLDINGPID"
  # try the next lock
  PICKLOCK=$((($PICKLOCK + 1) % $NUM_LOCKS))

  # busy waiting, not putting too much load on the file system
  if [ $PICKLOCK -eq 0 ]
  then
    sleep 1
  fi
  LOCKDIR="$BASELOCKDIR$PICKLOCK"
done

# record the pid of the process who took the lock
echo "lock taken by PID $$ with name $binary_name" >> $LOCKDIR/info.txt
echo "$$" >> $LOCKDIR/pid

# tell trap about the directory only after we actually hold the lock
TRAPDIR="$LOCKDIR"

# cleanup is performed by exit handler
logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "use goto-gcc (PID $$,calling basename: $binary_name) with --native-linker $NATIVE_LINKER $@ $GCCEXTRAARGUMENTS"
case "$binary_name" in
  "$TOOLPREFIX""ar${TOOLSUFFIX}")
    if [ "$NATIVE_AR" = "/bin/true" ]
    then
      NATIVE_AR=$(next_in_path $binary_name)
    fi
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "create archive: $NATIVE_AR $@"
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    ar_code=0
    $NATIVE_AR "$@" || ar_code=$?
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "ar (PID $$) exit code: $ar_code"
    if [ "$ar_code" == "0" ]
    then
        storeBinary "$@"
    fi
    logOutputfileHash "$NATIVE_AR" "$@"
    exit $ar_code
    ;;
  "$TOOLPREFIX""ld${TOOLSUFFIX}")
    if [ "$NATIVE_LINKER" = "/bin/true" ]
    then
      NATIVE_LINKER=$(next_in_path $binary_name)
    fi
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call linker $GOTO_LD_BINARY"
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    ld_code=0
    FINALLINKBINARY="$GOTO_LD_BINARY"
    $USE_GDB $GOTO_LD_BINARY $GOTO_CC_EXTRA_ARGUMENTS --native-compiler $NATIVE_COMPILER --native-linker $NATIVE_LINKER "$@" || ld_code=$?
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "$FINALLINKBINARY (PID $$) exit code: $ld_code"
    # if no linking with goto-ld should be enforced, fall back in case of errors
    if [ "$ld_code" -ne 0 ] && [ "$ld_code" -ne 134 ] &&  [ "$ld_code" -ne 139 ] && [ -z "$ENFORCE_GOTO_LINKING" ]
    then
        logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "linking with goto-ld failed with $ld_code, retry with native linker $NATIVE_LINKER"
        ld_code=0
        FINALLINKBINARY="$NATIVE_LINKER"
        $NATIVE_LINKER "$@" || ld_code=$?
        logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "$NATIVE_LINKER (PID $$) exit code: $ld_code"
    fi
    if [ "$ld_code" == "0" ]
    then
        storeBinary "$@"
    fi
    strip_goto "$@"
    logOutputfileHash "$FINALLINKBINARY" "$@"
    exit $ld_code
    ;;
  "$TOOLPREFIX""cc${TOOLSUFFIX}" | "$TOOLPREFIX""gcc${TOOLSUFFIX}" | "$TOOLPREFIX""bcc${TOOLSUFFIX}" | "$TOOLPREFIX""g++${TOOLSUFFIX}" | "$TOOLPREFIX""clang${TOOLSUFFIX}" | "$TOOLPREFIX""clang++${TOOLSUFFIX}")
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER preset: $NATIVE_COMPILER"
    if [ "$NATIVE_COMPILER" = "/bin/true" ]
    then
      NATIVE_COMPILER=$(next_in_path $binary_name)
      logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "NATIVE_COMPILER next-in-path: $NATIVE_COMPILER"
      # Some GCC packages ship x86_64-unknown-linux-gcc, but do not ship
      # x86_64-unknown-linux-objcopy, as would be expected by goto-gcc. Fix
      # this on-demand
      if [ "$(basename $NATIVE_COMPILER)" = "x86_64-unknown-linux-gnu-gcc" ]
      then
        objcopy_path=$(echo $NATIVE_COMPILER | sed 's/-gcc$/-objcopy/')
        if ! which "$objcopy_path" &>/dev/null
        then
          logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "installing objcopy symlink at $objcopy_path"
          ln -sf $(dirname $objcopy_path)/objcopy "$objcopy_path"
        fi
      fi
    fi
    if [ $binary_name = "$TOOLPREFIX""bcc${TOOLSUFFIX}" ] && [ "$NATIVE_BCC" = "/bin/true" ]
    then
      NATIVE_BCC=$(next_in_path $binary_name)
    fi
    # set the compiler to bcc, if the called compiler is actually bcc
    USE_COMPILER="$NATIVE_COMPILER"
    USE_GOTO_COMPILER="$GOTO_GCC_BINARY"
    # when bcc should be used, set goto-bcc and native bcc tools
    [ $binary_name = "$TOOLPREFIX""bcc${TOOLSUFFIX}" ] && [ -n "$NATIVE_BCC" ] && USE_COMPILER="$NATIVE_BCC"
    [ $binary_name = "$TOOLPREFIX""bcc${TOOLSUFFIX}" ] && USE_GOTO_COMPILER="$GOTO_BCC_BINARY"
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call compiler $USE_GOTO_COMPILER with --native-compiler $USE_COMPILER"
    FAULTYINPUT=$(mktemp faulty-goto-gcc-input-for-$$.XXXXXX)
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    # here, output to stdout and stderr is added to the same log file with two
    # different tee processes. While this might mix up lines in the log, for the
    # moment we go with this simple version
    gcc_code=0
    $USE_GDB $USE_GOTO_COMPILER $GOTO_CC_EXTRA_ARGUMENTS --print-rejected-preprocessed-source "$FAULTYINPUT" \
             --native-compiler $USE_COMPILER --native-linker $NATIVE_LINKER "$@" $GCCEXTRAARGUMENTS \
             >  >(tee -a "$LOG") \
             2> >(tee -a "$LOG" 1>&2) || gcc_code=$?
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "goto-gcc (PID $$) exit code: $gcc_code"
    if [ "$gcc_code" == "0" ]
    then
        storeBinary "$@"
        # delete created faulty input file, as we do not need it
        rm -f "$FAULTYINPUT"

        if [ -n "$INCLUDE_WARNINGS" ]
        then
          checkIncludes $USE_GOTO_COMPILER $USE_COMPILER "$@" || gcc_code=$?
        fi
    else
        if [ -s "$FAULTYINPUT" ]
        then
            mkdir -p "$LOCK_PARENT_DIR/faultyInput"
            mv "$FAULTYINPUT" "$LOCK_PARENT_DIR/faultyInput/$(basename "$FAULTYINPUT")"
            logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "stored input for failed gcc call with PID $$ at: $LOCK_PARENT_DIR/faultyInput/$(basename $FAULTYINPUT)"
        else
            rm -f "$FAULTYINPUT"
        fi
    fi
    logOutputfileHash "$USE_GOTO_COMPILER" "$@"
    exit $gcc_code
    ;;
  "$TOOLPREFIX"as"${TOOLSUFFIX}" | "$TOOLPREFIX"as86"${TOOLSUFFIX}" )
    if [ "$NATIVE_AS" = "/bin/true" ]
    then
      NATIVE_AS=$(next_in_path $binary_name)
    fi
    USE_ASSEMBLER="$NATIVE_AS"
    USE_GOTO_COMPILER="$GOTO_AS_BINARY"
    if [ $binary_name = "$TOOLPREFIX"as86 ]
    then
      if [ "$NATIVE_AS86" = "/bin/true" ]
      then
        NATIVE_AS86=$(next_in_path $binary_name)
      fi
      USE_ASSEMBLER="$NATIVE_AS86"
      USE_GOTO_COMPILER="$GOTO_AS86_BINARY"
    fi
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "call compiler $USE_GOTO_COMPILER with --native-assembler $USE_ASSEMBLER"
    FAULTYINPUT=$(mktemp faulty-goto-gcc-input-for-$$.XXXXXX)
    [ $REDIRECT_STDIN -ne 1 ] || exec 0<&4 4<&-
    # here, output to stdout and stderr is added to the same log file with two
    # different tee processes. While this might mix up lines in the log, for the
    # moment we go with this simple version
    gcc_code=0
    $USE_GDB $USE_GOTO_COMPILER $GOTO_CC_EXTRA_ARGUMENTS --print-rejected-preprocessed-source "$FAULTYINPUT" \
             --native-assembler $USE_ASSEMBLER "$@" \
             >  >(tee -a "$LOG") \
             2> >(tee -a "$LOG" 1>&2) || gcc_code=$?
    logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "goto-gcc (PID $$) exit code: $gcc_code"
    if [ "$gcc_code" == "0" ]
    then
        storeBinary "$@"
        # delete created faulty input file, as we do not need it
        rm -f "$FAULTYINPUT"
    else
        mkdir -p "$LOCK_PARENT_DIR/faultyInput"
        mv "$FAULTYINPUT" "$LOCK_PARENT_DIR/faultyInput/$(basename "$FAULTYINPUT")"
        logwrapper "${TOOLPREFIX}"GOTO-GCC"${TOOLSUFFIX}" "stored input for failed gcc call with PID $$ at: $LOCK_PARENT_DIR/faultyInput/$(basename $FAULTYINPUT)"
    fi
    logOutputfileHash "$USE_GOTO_COMPILER" "$@"
    exit $gcc_code
    ;;
esac

# make sure we do not enter the goto-gcc path again
# cleanup is performed by exit handler
echo "warning: unknown tool binary name $0 with basename $binary_name" >&2
exit 1
