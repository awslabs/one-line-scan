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
# This file is meant to be sourced by the setup script that installs all
# selected wrapper hooks. Hence, it contains variables that are not defined in
# this script.

# Wrap the Fortify's sourceanalyzer around all further (goto-)gcc calls.
# sourceanalyzer strictly requires that the name of the compiler is gcc,
# thus all prefixes require extra care.
#
inject_fortify()
{
  # use source dir to be able to copy the correct wrapper script
  local -r HOOK_SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  # check whether we can find the wrapper script
  if [ ! -f $HOOK_SRC_DIR/fortify-wrapper.sh ]
  then
    echo "error: cannot find wrapper script $HOOK_SRC_DIR/fortify-wrapper.sh"
    return 1
  fi

  # if we can't find sourceanalyzer on the path, we cannot continue
  if ! which sourceanalyzer > /dev/null 2>&1
  then
    echo "error: cannot inject Fortify wrapper as sourceanalyzer cannot be found on PATH"
    return 1
  fi

  # we will place the Fortify wrapper here
  mkdir -p "$GOTO_GCC_WRAPPER_INSTALL_DIR/Fortify"
  for SUFFIX in "" $TOOLSUFFIX
  do
  for PREFIX in "" $TOOLPREFIX
  do
    # exclude the case where both prefix and suffix are active
    [ -z "$SUFFIX" ] || [ -z "$PREFIX" ] || continue

    # we will point all calls to relevant compilers to the same wrapper
    local TARGET_GCC="$GOTO_GCC_WRAPPER_INSTALL_DIR/Fortify/$PREFIX""gcc""$SUFFIX"
    cp "$HOOK_SRC_DIR"/fortify-wrapper.sh "$TARGET_GCC"

    # add extra arguments to wrapper script
    if [ -n "$GCC_WRAPPER_EXTRAARGUMENTS" ]
    then
        perl -p -i -e "s:^GCCEXTRAARGUMENTS=:GCCEXTRAARGUMENTS=\"$GCC_WRAPPER_EXTRAARGUMENTS\":" "$TARGET_GCC"
    fi

    local FORTIFY_BUILD_ID=$(echo "$ORIGIN" | sed 's%[:/#@]%_%g')
    local FORTIFY_OPTS="-Dcom.fortify.WorkingDirectory=$FULLDIRECTORY/fortify-data -Dcom.fortify.sca.ProjectRoot=$FULLDIRECTORY/fortify-data"

    # find sourceanalyzer
    perl -p -i -e "s:NATIVE_SCA_PATH=:NATIVE_SCA_PATH=$(which sourceanalyzer 2> /dev/null):" "$TARGET_GCC"
    perl -p -i -e "s:FORTIFY_BUILD_ID=.*:FORTIFY_BUILD_ID=$FORTIFY_BUILD_ID:" "$TARGET_GCC"
    perl -p -i -e "s:FORTIFY_OPTS=.*:FORTIFY_OPTS=\"$FORTIFY_OPTS\":" "$TARGET_GCC"
    # tell the wrapper about the location of the actual compilers
    perl -p -i -e "s:TOOLPREFIX=:TOOLPREFIX=$PREFIX:" "$TARGET_GCC"
    perl -p -i -e "s:TOOLSUFFIX=:TOOLSUFFIX=$SUFFIX:" "$TARGET_GCC"
    for t in gcc g++ clang clang++
    do
      T=$(echo $t | tr '[a-z]+' '[A-Z]P')
      p=$(find_native "$PREFIX"$t"$SUFFIX")
      perl -p -i -e "s:^NATIVE_$T=.*:NATIVE_$T=$p:" "$TARGET_GCC"
    done

    # make the other compiler use the fortify wrapper
    for TOOL in g++ clang clang++ cc c++
    do
      # might fail, because if check-setup.sh is used, the directory is already
      # there, as well as the links
      cp "$TARGET_GCC" "$GOTO_GCC_WRAPPER_INSTALL_DIR/Fortify/$PREFIX""$TOOL""$SUFFIX"
    done
  done
  done

  # after using all previous tool locations to setup the wrapper script,
  # activate the wrapper script
  export PATH="$GOTO_GCC_WRAPPER_INSTALL_DIR/Fortify":$PATH
  return 0
}
