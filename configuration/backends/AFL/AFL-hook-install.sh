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
# This file is meant to be sourced by the setup script that installs all
# selected wrapper hooks. Hence, it contains variables that are not defined in
# this script.

# To be able to compile for fuzzing with AFL, inject wrappers
inject_afl()
{
  # use source dir to be able to copy the correct wrapper script
  local -r HOOK_SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  # check whether we can find the wrapper script
  if [ ! -f $HOOK_SRC_DIR/afl-wrapper.sh ]
  then
    echo "error: cannot find wrapper script $HOOK_SRC_DIR/afl-wrapper.sh"
    return 1
  fi

  # we will place the AFL wrapper here
  mkdir -p "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL"
  # we will point all calls to relevant compilers to the same wrapper
  local TARGET_GCC="$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/gcc"
  cp "$HOOK_SRC_DIR"/afl-wrapper.sh "$TARGET_GCC"

  # we did not find afl-gcc on the path, so we cannot continue
  if ! which afl-gcc > /dev/null 2>&1
  then
    echo "error: cannot inject AFL compilers, as afl-gcc cannot be found"
    return 1
  fi

  # extract the AFL directory from the afl-gcc binary location, set in environment
  local AFL_GCC_LOCATION=$(which afl-gcc 2> /dev/null)

  # add extra arguments to wrapper script
  if [ -n "$GCC_WRAPPER_EXTRAARGUMENTS" ]
  then
    perl -p -i -e "s:^GCCEXTRAARGUMENTS=:GCCEXTRAARGUMENTS=\"$GCC_WRAPPER_EXTRAARGUMENTS\":" "$TARGET_GCC"
  fi

  # check whether AFL is set up correctly (i.e. a link of as is located in the
  # directory that is pointed to by AFL_PATH. Without that link, compilation
  # will fail
  if [ ! -x "$(dirname "$AFL_GCC_LOCATION")/as" ]
  then
    echo "error: cannot find \"as\" binary in AFL PATH, i.e. in $(dirname "$AFL_GCC_LOCATION")"
    return 1
  fi

  export AFL_PATH=$(dirname "$AFL_GCC_LOCATION")
  perl -p -i -e "s:NATIVE_AFL_PATH=:NATIVE_AFL_PATH=$(dirname "$AFL_GCC_LOCATION"):" "$TARGET_GCC"
  # tell the wrapper about the location of AFL
  perl -p -i -e "s:NATIVE_GCC=/bin/false:NATIVE_GCC=$GOTO_GCC_NATIVE_COMPILER:" "$TARGET_GCC"

  # activate all other AFL binaries
#  if which afl-as > /dev/null 2>&1
#  then
#    perl -p -i -e "s:NATIVE_AS=/bin/false:NATIVE_AS=$(which afl-as 2> /dev/null):" "$TARGET_GCC"
#    cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/gcc" "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/as"
#    cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/gcc" "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/afl-as"
#  else
#    echo "error: cannot find afl-as"
#    return 1
#  fi

  # it is not too bad, if we cannot find the other compilers, so we do not complain in these cases
  perl -p -i -e "s:NATIVE_CLANG=/bin/false:NATIVE_CLANG=$(find_native clang):" "$TARGET_GCC"
  perl -p -i -e "s:NATIVE_GPP=/bin/false:NATIVE_GPP=$(find_native g++):" "$TARGET_GCC"
  perl -p -i -e "s:NATIVE_CLANGPP=/bin/false:NATIVE_CLANGPP=$(find_native clang++):" "$TARGET_GCC"

  for t in clang afl-clang g++ afl-g++ clang++ afl-clang++ ${OLS_TARGET_COMPILER:-}
  do
    cp "$TARGET_GCC" "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL/$t"
  done

  # after using all previous tool locations to setup the wrapper script,
  # activate the wrapper script
  export PATH="$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL":$PATH
  return 0
}

