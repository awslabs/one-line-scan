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
# Remove the goto-gcc wrapper for cc, gcc and ld from the PATH environment
#
# Usage: source remove-wrapper.sh   ... make the variables visible in the calling shell
#
# options: --keep-dir  does not remove the directory where the wrapper files were stored
#

# set defaults
keepdirectory=

# parse arguments
while [ ! -z "$*" ]
do
	case $1 in
	--keep-dir) 	keepdirectory=t;;
	--no-keep-dir) 	keepdirectory=;;
	*)
		echo "warning: unknown parameter: $1"
	esac
	shift
done

# restore previous path environment variable
if [ -n "$PRE_GOTO_GCC_WRAPPER_PATH" ]
then
  export PATH="$PRE_GOTO_GCC_WRAPPER_PATH"
  PRE_GOTO_GCC_WRAPPER_PATH=""

  # delete all the directories that have been created?
  if [ -z "$keepdirectory" ] && [ -n "$FULLDIRECTORY" ]
  then
    rm -f "$FULLDIRECTORY"/{binaries.list,build.log,environmentInfo.txt,wrapper-log.txt,libraries.list}
  fi
  if [ -n "$GOTO_GCC_WRAPPER_INSTALL_DIR" ]
  then
    # the directory contains the lock as well
    if [ -z "$keepdirectory" ] || [ "x$NESTED" = "xt" ]
    then
      rm -rf "$GOTO_GCC_WRAPPER_INSTALL_DIR/AFL"
      rm -rf "$GOTO_GCC_WRAPPER_INSTALL_DIR/plain"
      rm -rf "$GOTO_GCC_WRAPPER_INSTALL_DIR/cppcheck"
      rm -rf "$GOTO_GCC_WRAPPER_INSTALL_DIR/Fortify"
      rm -f "$GOTO_GCC_WRAPPER_INSTALL_DIR"/ols-library.sh
      for PREFIX in "" $TOOLPREFIX
      do
        for t in gcc bcc as as86 g++ clang clang++ ld ar cc c++ objcopy
        do
          rm -f "$GOTO_GCC_WRAPPER_INSTALL_DIR"/$PREFIX$t
        done
      done
      rm -f "$GOTO_GCC_WRAPPER_INSTALL_DIR"/make
      rm -f "$GOTO_GCC_WRAPPER_INSTALL_DIR"/cflags

      if ! rmdir -p "$GOTO_GCC_WRAPPER_INSTALL_DIR" 2>/dev/null
      then
        echo "warning: wrapper installation directory $GOTO_GCC_WRAPPER_INSTALL_DIR not empty" >&2
      fi
    fi
    # clear the variable
    GOTO_GCC_WRAPPER_INSTALL_DIR=""
  fi

  # do not delete /tmp/goto-gcc-wrapper-pid*, as those might be created by other SHELLS running in parallel
else
  echo "warning: did not find wrapper environment" >&2
fi
