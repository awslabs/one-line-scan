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
# Wrap all compiler calls by an extra step to run cppcheck with all -I and -D
# flags of the compiler calls.
#
# This file is meant to be sourced by the setup script that installs all
# selected wrapper hooks. Hence, it contains variables that are not defined in
# this script.

# install the hook.
inject_cppcheck()
{
  # we will place the cppcheck wrapper here
  local -r TOOL="cppcheck"
  local -r INSTALL_DIR="$GOTO_GCC_WRAPPER_INSTALL_DIR/$TOOL"

  # use source dir to be able to copy the correct wrapper script
  local -r HOOK_SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  # check if prerequirements are available
  if ! command -v "$TOOL" &> /dev/null
  then
    echo "could not find $TOOL command, abort"
    return 1
  fi

  # check the cppcheck version, and warn if there is a more recent version (at the time of writing)
  CPPCHECK_VERSION=$(cppcheck --version | cut -d ' ' -f 2)
  if (( $(echo "$CPPCHECK_VERSION < 1.81" |bc -l) ))
  then
    log "Note: there is a more recent cppcheck version, visit http://cppcheck.sourceforge.net/!"
  fi

  # install wrapper
  mkdir -p "$INSTALL_DIR"
  for SUFFIX in "" $TOOLSUFFIX
  do
  for PREFIX in "" $TOOLPREFIX
  do
    # exclude the case where both prefix and suffix are active
    [ -z "$SUFFIX" ] || [ -z "$PREFIX" ] || continue

    # we will point all calls to relevant compilers to the same wrapper
    local TARGET_GCC="$INSTALL_DIR/${PREFIX}gcc${SUFFIX}"
    cp "$HOOK_SRC_DIR/$TOOL-wrapper.sh" "$TARGET_GCC"

    # add extra arguments to wrapper script
    if [ ! -z "$GCC_WRAPPER_EXTRAARGUMENTS" ]
    then
        perl -p -i -e "s:^GCCEXTRAARGUMENTS=:GCCEXTRAARGUMENTS=\"$GCC_WRAPPER_EXTRAARGUMENTS\":" "$TARGET_GCC"
    fi

    # tell the wrapper about the location of the actual compilers
    perl -p -i -e "s:TOOLPREFIX=:TOOLPREFIX=$PREFIX:" "$TARGET_GCC"
    perl -p -i -e "s:TOOLSUFFIX=:TOOLSUFFIX=$SUFFIX:" "$TARGET_GCC"

    # tell the wrapper from where install has been called
    perl -p -i -e "s:CALL_DIR=:CALL_DIR=$(readlink -e $(pwd))/:" "$TARGET_GCC"

    for t in gcc g++ clang clang++
    do
      T=$(echo $t | tr '[a-z]+' '[A-Z]P')
      p=$(find_native "$PREFIX"$t"$SUFFIX")
      perl -p -i -e "s:^NATIVE_$T=.*:NATIVE_$T=$p:" "$TARGET_GCC"
    done

    # make the other compiler use the fortify wrapper
    for TARGET_COMPILER in g++ clang clang++ cc c++
    do
      # might fail, because if check-setup.sh is used, the directory is already
      # there, as well as the links
      cp "$TARGET_GCC" "$INSTALL_DIR/${PREFIX}${TARGET_COMPILER}${SUFFIX}"
    done
  done
  done

  # after using all previous tool locations to setup the wrapper script,
  # activate the wrapper script
  export PATH="$INSTALL_DIR":$PATH
  return 0
}
