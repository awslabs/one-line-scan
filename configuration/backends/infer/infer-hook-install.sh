#  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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
# Setup the infer wrapper to log all compiler calls, and extract some relevant
# information to make working with large code bases simpler.
#
# This file is meant to be sourced by the setup script that installs all
# selected wrapper hooks. Hence, it contains variables that are not defined in
# this script.

# install the hook.
inject_infer() {
  # we will place the infer wrapper here
  local -r TOOL="infer"
  local -r INSTALL_DIR="$GOTO_GCC_WRAPPER_INSTALL_DIR/$TOOL"

  # check if prerequirements are available
  for CHECK_TOOL in $TOOL jq python3; do
    if ! command -v "$CHECK_TOOL" &>/dev/null; then
      echo "could not find $CHECK_TOOL command, abort"
      return 1
    fi
  done

  # use source dir to be able to copy the correct wrapper script
  local -r HOOK_SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"

  # install wrapper
  mkdir -p "$INSTALL_DIR"
  for SUFFIX in "" $TOOLSUFFIX; do
    for PREFIX in "" $TOOLPREFIX; do
      # exclude the case where both prefix and suffix are active
      [ -z "$SUFFIX" ] || [ -z "$PREFIX" ] || continue

      # we will point all calls to relevant compilers to the same wrapper
      local TARGET_GCC="$INSTALL_DIR/${PREFIX}gcc${SUFFIX}"
      cp "$HOOK_SRC_DIR/$TOOL-wrapper.sh" "$TARGET_GCC"

      # add extra arguments to wrapper script
      if [ ! -z "$GCC_WRAPPER_EXTRAARGUMENTS" ]; then
        perl -p -i -e "s:^GCCEXTRAARGUMENTS=:GCCEXTRAARGUMENTS=\"$GCC_WRAPPER_EXTRAARGUMENTS\":" "$TARGET_GCC"
      fi

      # tell the wrapper about the location of the actual compilers
      perl -p -i -e "s:TOOLPREFIX=:TOOLPREFIX=$PREFIX:" "$TARGET_GCC"
      perl -p -i -e "s:TOOLSUFFIX=:TOOLSUFFIX=$SUFFIX:" "$TARGET_GCC"

      # make sure we use the same lock directory name everywhere
      perl -p -i -e "s:XX/tmp/infer-wrapper-lockXX:$INSTALL_DIR/wrapper-lock:" "$TARGET_GCC"

      # tell the wrapper from where install has been called
      perl -p -i -e "s:CALL_DIR=:CALL_DIR=$(readlink -e $(pwd))/:" "$TARGET_GCC"

      for t in gcc g++ clang clang++; do # as ld  # infer cannot do as and ld
        T=$(echo $t | tr '[a-z]+' '[A-Z]P')
        p=$(find_native "$PREFIX"$t"$SUFFIX")
        perl -p -i -e "s:^NATIVE_$T=.*:NATIVE_$T=$p:" "$TARGET_GCC"
      done

      # make the other compiler use the fortify wrapper
      for TARGET_COMPILER in g++ clang clang++ cc c++; do # as ld  # infer cannot do as and ld
        # might fail, because if check-setup.sh is used, the directory is already
        # there, as well as the links
        cp "$TARGET_GCC" "$INSTALL_DIR/${PREFIX}${TARGET_COMPILER}${SUFFIX}"
      done
    done
  done

  # copy transform python script
  cp "$HOOK_SRC_DIR"/transform_report.py "$INSTALL_DIR"

  # after using all previous tool locations to setup the wrapper script,
  # activate the wrapper script
  export PATH="$INSTALL_DIR":$PATH

  return 0
}
