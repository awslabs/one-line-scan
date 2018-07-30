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
# Sets up the goto-gcc wrapper, currently replaces cc, gcc and ld
#
# create a (temporary) directory with the necessary tools
# adds this directory to the PATH environment
#
# usage: source setup.sh [options]   ... to make the variables visible in the calling shell
#           --target DIR       ... if specified, the directory DIR will be created and used for the wrapper
#           --origin STR       ... source origin to identify the project
#           --extra  ARG       ... add ARG to end of the gcc command line, can be specified multiple times
#           --no-link / --link ... enforce goto-ld for linking (otherwise, fallback on native linker in case of failure)
#           --keep-going       ... replace the make command with a command that adds the parameter -k
#           --afl              ... wrap AFL compilers
#           --fortify          ... run Fortify sourceanalyzer
#           --smatch           ... run SMATCH code analysis tool
#           -j N               ... allow N compile commands to be executed in parallel (at least 2)
#           --trunc            ... delete binary/library lists from directory, try to reuse existing directory
#           --re-use           ... try to reuse existing directory
#           --forward SRC DST  ... install a tool on the PATH with name SRC that actually would run DST (DST must exist on the PATH already)
#           --prefix PRE       ... prefix for gcc, ld and ar (to be replaced by goto-gcc) , e.g. x86_64-linux-gnu-
#           --suffix SUF       ... suffix for gcc, ld and ar (to be replaced by goto-gcc) , e.g. -7
#           --include-warnings ... test each source file for redundant #include statements
#           --nested           ... delay gcc wrapper configuration to handle paths of nested builds
#
# uninstall wrapper:
#
#        source remove-wrapper.sh
#
# do not return with first non-zero exit of a prorgamm call, as this would terminate the calling shell
# set -e

GCC_WRAPPER_EXTRAARGUMENTS=
TARGET_DIRECTORY=
GOTO_GCC_WRAPPER_ENFORCE_GOTO_LINKING=
KEEP_GOING_IN_MAKE=
WRAP_AFL=
WRAP_CPPCHECK=
WRAP_FORTIFY=
WRAP_SMATCH=
WRAP_GOTOCC=1
WRAP_PLAIN=
NUM_LOCKS=2
USE_EXISTING_DIR=
FORWARDS=()
TOOLPREFIX=
TOOLSUFFIX=
ORIGIN="one-line-scan"
INCLUDE_WARNINGS=
NESTED=

# parse arguments
parse_arguments ()
{
  while [ $# -gt 0 ]
  do
    case $1 in
    --extra)      GCC_WRAPPER_EXTRAARGUMENTS="$GCC_WRAPPER_EXTRAARGUMENTS $2"; shift;;
    --target)     TARGET_DIRECTORY="$2"        ; shift;;
    --afl)        WRAP_AFL=t;;
    --cppcheck)   WRAP_CPPCHECK=t;;
    --fortify)    WRAP_FORTIFY=t;;
    --smatch)     WRAP_SMATCH=t;;
    --no-gotocc)  WRAP_GOTOCC=;;
    --plain)      WRAP_PLAIN=t;;
    --link)       GOTO_GCC_WRAPPER_ENFORCE_GOTO_LINKING=t ;;
    --no-link)    GOTO_GCC_WRAPPER_ENFORCE_GOTO_LINKING=  ;;
    --keep-going) KEEP_GOING_IN_MAKE=t;;
    --trunc)      USE_EXISTING_DIR=trunc;;
                  # set a value different than trunc, the rest of the script checks only for "trunc" or "any other value"
    --re-use)     USE_EXISTING_DIR=reuse;;
    -j)           if [ $2 -ge 2 ]
                  then
                    NUM_LOCKS=$2
                    shift
                  else
                    echo "warning: specified -j without an number, will not change value"
                  fi
                  ;;
    --forward)    if [ -n "$2" ] && [ -n "$3" ]
                  then
                    FORWARDS+=("$2")
                    FORWARDS+=("$3")
                    shift 2
                  else
                    echo "error: forward is called without two following arguments - abort"
                    echo "<$1> <$2> <$3>"
                    return 1
                  fi;;
    --prefix)     TOOLPREFIX+=" $2"; shift;;
    --suffix)     TOOLSUFFIX+=" $2"; shift;;
    --origin)     ORIGIN=$2; shift;;
    --include-warnings) INCLUDE_WARNINGS=t ;;
    --nested)     NESTED=t
                  TOOLPREFIX+=" x86_64-unknown-linux-gnu-";;
    *)            echo "warning: unknown parameter $1" ;;
    esac
    shift
  done

  return 0
}

# check whether we already have an active wrapper and warn the user, but do not delete the other wrapper
if [ -n "$GOTO_GCC_WRAPPER_INSTALL_DIR" ]
then
    echo "warning: found a wrapper already at $GOTO_GCC_WRAPPER_INSTALL_DIR"
fi

# use source dir to be able to copy the correct wrapper script
SOURCE_DIR="$( dirname "${BASH_SOURCE[0]}" )"

#
# load compilers, allow a prefix and a suffix
#
load_compilers()
{
  local PREFIX="$1"
  local SUFFIX="$2"

  # find current versions of the used tools, fall back if tools do not exist
  if [ -z "$PREFIX" ] || [ -z "$SUFFIX" ]
  then
    # in case either prefix or suffix are empty, drop the other and fall back to the original tool
    GOTO_GCC_NATIVE_COMPILER="$(which "$PREFIX"gcc"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_COMPILER" ] || GOTO_GCC_NATIVE_COMPILER="$(which gcc)"

    GOTO_GCC_NATIVE_LINKER="$(which "$PREFIX"ld"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_LINKER" ] || GOTO_GCC_NATIVE_LINKER="$(which ld)"

    GOTO_GCC_NATIVE_AR="$(which "$PREFIX"ar"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_AR" ] || GOTO_GCC_NATIVE_AR="$(which ar)"
  else
    # this case is defined to drop the suffix, and if still fails drop the prefix as well
    GOTO_GCC_NATIVE_COMPILER="$(which "$PREFIX"gcc"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_COMPILER" ] || GOTO_GCC_NATIVE_COMPILER="$(which "$PREFIX"gcc)"
    [ -n "$GOTO_GCC_NATIVE_COMPILER" ] || GOTO_GCC_NATIVE_COMPILER="$(which gcc)"

    GOTO_GCC_NATIVE_LINKER="$(which "$PREFIX"ld"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_LINKER" ] || GOTO_GCC_NATIVE_LINKER="$(which "$PREFIX"ld)"
    [ -n "$GOTO_GCC_NATIVE_LINKER" ] || GOTO_GCC_NATIVE_LINKER="$(which ld)"

    GOTO_GCC_NATIVE_AR="$(which "$PREFIX"ar"$SUFFIX")"
    [ -n "$GOTO_GCC_NATIVE_AR" ] || GOTO_GCC_NATIVE_AR="$(which "$PREFIX"ar)"
    [ -n "$GOTO_GCC_NATIVE_AR" ] || GOTO_GCC_NATIVE_AR="$(which ar)"
  fi

  # return success
  [ -x $GOTO_GCC_NATIVE_COMPILER ] && [ -x $GOTO_GCC_NATIVE_LINKER ] && [ -x $GOTO_GCC_NATIVE_AR ] && return 0
  return 1
}

#
# load compilers, allow a prefix
#
load_native_compilers()
{
  local PREFIX="$1"
  local SUFFIX="$2"

  if [ -n "$NESTED" ]
  then
    GOTO_GCC_NATIVE_COMPILER="/bin/true"
    GOTO_GCC_NATIVE_LINKER="/bin/true"
    GOTO_GCC_NATIVE_AR="/bin/true"
  else
    load_compilers "$PREFIX" "$SUFFIX"
  fi
}

#
# locate an executable
#
find_native()
{
  local cmd="$1"

  if [ -n "$NESTED" ]
  then
    echo "/bin/true"
  else
    if which "$cmd" > /dev/null 2>&1
    then
      which "$cmd" 2>/dev/null
    else
      echo "/bin/false"
    fi
  fi
}

#
# check whether all necessary tools are there
#
load_tools()
{
  PREFIX="$1"
  SUFFIX="$2"

  if [ "$GOTO_GCC_NATIVE_COMPILER" != "/bin/true" ]
  then
    load_compilers "$PREFIX" "$SUFFIX"
  fi

  GOTO_GCC_BINARY="$(which goto-gcc 2> /dev/null)"
  GOTO_LD_BINARY="$(which goto-ld 2> /dev/null)"
  GOTO_DIFF_BINARY="$(which goto-diff 2> /dev/null)"

  # check whether the minimum set of tools is available
  if [ -n "$WRAP_GOTOCC" ]
  then
    if [ ! -x "$GOTO_GCC_NATIVE_COMPILER" ] || [ ! -x "$GOTO_GCC_NATIVE_LINKER" ]\
      || [ ! -x "$GOTO_GCC_BINARY" ] || [ ! -x "$GOTO_LD_BINARY" ] \
      || [ ! -x "$GOTO_GCC_NATIVE_AR" ] || [ ! -x "$GOTO_DIFF_BINARY" ]
    then
      echo "error: did not find all necessary tools in the PATH environment"
      echo "gcc:      $GOTO_GCC_NATIVE_COMPILER"
      echo "ld:       $GOTO_GCC_NATIVE_LINKER"
      echo "goto-gcc: $GOTO_GCC_BINARY"
      echo "goto-ld:  $GOTO_LD_BINARY"
      echo "goto-diff:$GOTO_DIFF_BINARY"
      echo "abort setup"
      return 1
    fi
  fi
  return 0
}

# portable implementation of realpath
function full_path
{
  local f="$1"
  if readlink -f / >/dev/null 2>&1
  then
    readlink -f $f
  else
    if [[ "$f" =~ ^/ ]]
    then
      echo "$f"
    else
      echo "$(pwd -P)/""$f"
    fi
  fi
}

#
# create the target directory
#
create_environment ()
{
  # check whether a target directory can be used
  local KEEP_DIRECTORY=--keep-dir
  if [ -n "$TARGET_DIRECTORY" ]
  then
      FULLDIRECTORY=$(full_path "$TARGET_DIRECTORY")
      if [ -d "$FULLDIRECTORY" ]
      then
        if [ -e $FULLDIRECTORY/.checked-ok ]
        then
          rm $FULLDIRECTORY/.checked-ok
        elif [ -e $FULLDIRECTORY/.checked-missing ]
        then
          echo "warning: target directory $TARGET_DIRECTORY did not exist"
          rm $FULLDIRECTORY/.checked-missing
        else
          [ -z "$USE_EXISTING_DIR" ] && echo "warning: target directory $TARGET_DIRECTORY already exists"
        fi
      else
        KEEP_DIRECTORY=
        if ! mkdir "$FULLDIRECTORY" 2> /dev/null
        then
          echo "error: creating the target directory finished with a failure - abort"
          return 1
        fi
        if [ -n "$USE_EXISTING_DIR" ]
        then
          echo "warning: target directory $TARGET_DIRECTORY did not exist"
          touch $FULLDIRECTORY/.checked-missing
        else
          touch $FULLDIRECTORY/.checked-ok
        fi
      fi
  fi

  if [ -n "$NESTED" ]
  then
    mkdir -p build-tools/bin
    GOTO_GCC_WRAPPER_INSTALL_DIR=$(full_path build-tools/bin)
  elif [ -n "$TARGET_DIRECTORY" ]
  then
    GOTO_GCC_WRAPPER_INSTALL_DIR="$FULLDIRECTORY"
  else
    # create a (temporary) target directory where the wrapper goes to
    GOTO_GCC_WRAPPER_INSTALL_DIR="$(mktemp -d)"
  fi

  if [ "$USE_EXISTING_DIR" = "trunc" ]
  then
    # currently, use a white list approach for clean up
    rm -f "$FULLDIRECTORY"/{binaries.list,build.log,environmentInfo.txt,wrapper-log.txt,libraries.list}
    rm -f "$FULLDIRECTORY/Fortify/fortify-preprocess.log"
    rm -f "$FULLDIRECTORY/log/fortify-scan.log"
  fi

  # memorize old path, if it has not been set before
  if [ -z "$PRE_GOTO_GCC_WRAPPER_PATH" ]
  then
    PRE_GOTO_GCC_WRAPPER_PATH="$PATH"
  fi
}

#
# install wrappers for nested builds
#
nested_wrappers()
{
  local last_tool=$1

  for f in $GOTO_GCC_WRAPPER_INSTALL_DIR/$last_tool/*
  do
    bn=$(basename $f)
    ln -s $last_tool/$bn $GOTO_GCC_WRAPPER_INSTALL_DIR/$bn
  done
  cp "$SOURCE_DIR/../backends/cflags/cflags-wrapper.sh" "$GOTO_GCC_WRAPPER_INSTALL_DIR/cflags"
  perl -p -i -e "s:XX/tmp/cflags-wrapper-lockXX:$FULLDIRECTORY/wrapper-lock:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/cflags"
  echo "$(which "objcopy" 2> /dev/null) \"\$@\"" > "$GOTO_GCC_WRAPPER_INSTALL_DIR"/x86_64-unknown-linux-gnu-objcopy
  chmod a+x "$GOTO_GCC_WRAPPER_INSTALL_DIR"/x86_64-unknown-linux-gnu-objcopy
}


#
# main script
#
# only execute, if options can be parsed and all necessary tools can be found
if parse_arguments "$@" && load_native_compilers
then

  # setup environment
  if create_environment
  then
    cp "$SOURCE_DIR/ols-library.sh" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"

    # wrap cppcheck
    if [ -n "$WRAP_CPPCHECK" ]
    then
      source "$SOURCE_DIR/../backends/cppcheck/cppcheck-hook-install.sh"
      inject_cppcheck
      load_compilers
    fi

    # wrap plain
    if [ -n "$WRAP_PLAIN" ]
    then
      source "$SOURCE_DIR/../backends/plain/plain-hook-install.sh"
      inject_plain
      load_compilers
    fi

    # wrap Fortify
    if [ -n "$WRAP_FORTIFY" ]
    then
      source "$SOURCE_DIR/../backends/fortify/fortify-hook-install.sh"
      inject_fortify
      # need to re-load the compiler locations, as Fortify wrappers have been installed
      load_compilers
      [ -z "$NESTED" ] || nested_wrappers Fortify
    fi

    # wrap smatch
    if [ -n "$WRAP_SMATCH" ]
    then
      source "$SOURCE_DIR/../backends/smatch/smatch-hook-install.sh"
      inject_smatch
      # need to re-load the compiler locations, as smatch wrappers have been installed
      load_compilers
      [ -z "$NESTED" ] || nested_wrappers smatch
    fi

    # wrap AFL
    if [ -n "$WRAP_AFL" ]
    then
        source "$SOURCE_DIR/../backends/AFL/AFL-hook-install.sh"
        inject_afl
        load_compilers
        [ -z "$NESTED" ] || nested_wrappers AFL
    fi

    # wrap goto-(g)cc
    if load_tools
    then
      # run the actual injection
      source "$SOURCE_DIR/../backends/cbmc/gotocc-hook-install.sh"
      [ -z "$WRAP_GOTOCC" ] || inject_gotocc
    fi
  fi
fi
