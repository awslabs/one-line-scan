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

# install the hook
inject_gotocc()
{
  # use source dir to be able to copy the correct wrapper script
  local -r HOOK_SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  # check whether we can find the wrapper script
  if [ ! -f $HOOK_SRC_DIR/gotocc-wrapper.sh ]
  then
    echo "error: cannot find wrapper script $HOOK_SRC_DIR/gotocc-wrapper.sh"
    return 1
  fi

  # handle all prefixes. i.e. no prefix and the potentially specified prefix
  for SUFFIX in "" $TOOLSUFFIX
  do
  for PREFIX in "" $TOOLPREFIX
  do
    # exclude the case where both prefix and suffix are active
    [ -z "$SUFFIX" ] || [ -z "$PREFIX" ] || continue

    # load compilers wrt prefix:
    if [ "$GOTO_GCC_NATIVE_COMPILER" != "/bin/true" ]
    then
      load_compilers "$PREFIX" "$SUFFIX"
    fi

    if [ -n "$(which "${PREFIX}gcc${SUFFIX}")" ] && [ $(which "${PREFIX}gcc${SUFFIX}") = "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}" ]
    then
      echo "error: installing wrapper would result in infinite loop - abort"
      return 1
    fi

    # copy the wrapper
    cp "$HOOK_SRC_DIR/gotocc-wrapper.sh" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    # allow execution
    chmod a+x "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"${SUFFIX}"

    # place the actual names to the tools to be used in the wrappers, as well as the directory
    perl -p -i -e "s:XX/usr/bin/gccXX:$GOTO_GCC_NATIVE_COMPILER:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
    perl -p -i -e "s:XX/usr/bin/ldXX:$GOTO_GCC_NATIVE_LINKER:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
    perl -p -i -e "s:XX/usr/bin/arXX:$GOTO_GCC_NATIVE_AR:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    perl -p -i -e "s:XX/usr/bin/goto-gccXX:$GOTO_GCC_BINARY:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
    perl -p -i -e "s:XX/usr/bin/goto-ldXX:$GOTO_LD_BINARY:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
    perl -p -i -e "s:XX/usr/bin/goto-diffXX:$GOTO_DIFF_BINARY:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    perl -p -i -e "s:XX/tmp/goto-gcc-wrapper-lockXX:$FULLDIRECTORY/wrapper-lock:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    # tell the wrapper about the current tool prefix and suffix
    [ -z "$PREFIX" ] || perl -p -i -e "s:TOOLPREFIX=:TOOLPREFIX=$PREFIX:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
    [ -z "$SUFFIX" ] || perl -p -i -e "s:TOOLSUFFIX=:TOOLSUFFIX=$SUFFIX:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    # configure include warnings
    perl -p -i -e "s:INCLUDE_WARNINGS=:INCLUDE_WARNINGS=$INCLUDE_WARNINGS:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    # set number of locks!
    perl -p -i -e "s:NUM_LOCKS=4:NUM_LOCKS=$NUM_LOCKS:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"

    # add extra arguments to wrapper script
    if [ -n "$GCC_WRAPPER_EXTRAARGUMENTS" ]
    then
        perl -p -i -e "s:^GCCEXTRAARGUMENTS=:GCCEXTRAARGUMENTS=\"$GCC_WRAPPER_EXTRAARGUMENTS\":" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}"
        echo "use extra arguments: $GCC_WRAPPER_EXTRAARGUMENTS"
    fi

    if [ -z "$GOTO_GCC_WRAPPER_ENFORCE_GOTO_LINKING" ]
    then
        perl -p -i -e "s:^ENFORCE_GOTO_LINKING=1$:ENFORCE_GOTO_LINKING=:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/"$PREFIX"gcc${SUFFIX}" 2> /dev/null
    fi

    # optional tools that will be handled specially within the compiler wrapper
    for o in bcc as as86
    do
      O=$(echo $o | tr '[a-z]+' '[A-Z]P')
      if which "$PREFIX"$o"$SUFFIX" > /dev/null 2>&1
      then
        perl -p -i -e "s:^NATIVE_$O=:NATIVE_$O=$(which "$PREFIX"$o 2> /dev/null):" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX"
        which goto-$o > /dev/null 2>&1 && perl -p -i -e "s:XX/usr/bin/goto-${o}XX:$(which goto-$o 2> /dev/null):" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX"
        cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"$o"$SUFFIX"
      fi
    done

    # if we find further compilers, also use them. currently, we simply pass the extra options
    for t in g++ clang clang++
    do
      T=$(echo $t | tr '[a-z]+' '[A-Z]P')
      if which "$PREFIX"$t"$SUFFIX" > /dev/null 2>&1
      then
        perl -p -i -e "s:^NATIVE_COMPILER_$T=:NATIVE_COMPILER_$T=$(which "$PREFIX"$t"$SUFFIX" 2> /dev/null):" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX"
        cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"$t"$SUFFIX"
      elif [ -n "$NESTED" ]
      then
        perl -p -i -e "s:^NATIVE_COMPILER_$T=\$:NATIVE_COMPILER_$T=/bin/true:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX"
        cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"$t"$SUFFIX"
      fi
    done

    # also use the wrapper for ld, ar, cc, c++
    for t in ld ar cc c++
    do
      cp "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"gcc"$SUFFIX" "$GOTO_GCC_WRAPPER_INSTALL_DIR/""$PREFIX"$t"$SUFFIX"
    done
  done
  done

  # add wrapper for make, if KEEP_GOING_IN_MAKE option is set
  if [ -n "$KEEP_GOING_IN_MAKE" ]
  then
    if [ -n "$(which make)" ]
    then
      echo "$(which make) -k \"\$@\"" > "$GOTO_GCC_WRAPPER_INSTALL_DIR/make"
      chmod a+x "$GOTO_GCC_WRAPPER_INSTALL_DIR/make"
    else
      echo "warning: should add -k to make, but did not find make"
    fi
  fi

  # Some GCC packages ship x86_64-unknown-linux-gnu-gcc, but do not include
  # x86_64-unknown-linux-gnu-objcopy
  if [ -n "$NESTED" ]
  then
    FORWARDS+=("x86_64-unknown-linux-gnu-objcopy")
    FORWARDS+=("objcopy")
  fi

  # install all user specified forwards
  if [ ${#FORWARDS[@]} -gt 0 ]
  then
    for i in $(seq 0 2 $((${#FORWARDS[@]} - 1)) )
    do
      SRC="${FORWARDS[$i]}"
      DST="${FORWARDS[$((i+1))]}"
      if which "$DST" > /dev/null 2>&1
      then
        echo "$(which "$DST" 2> /dev/null) \"\$@\"" > "$GOTO_GCC_WRAPPER_INSTALL_DIR"/"$SRC"
        chmod a+x "$GOTO_GCC_WRAPPER_INSTALL_DIR"/"$SRC"
      else
        echo "error: cannot forward $SRC to $DST, as $DST does not exist on the PATH"
      fi
    done
  fi

  # install a wrapper for cflags
  if [ -n "$NESTED" ]
  then
    cp "$HOOK_SRC_DIR/../cflags/cflags-wrapper.sh" "$GOTO_GCC_WRAPPER_INSTALL_DIR/cflags"
    perl -p -i -e "s:XX/tmp/cflags-wrapper-lockXX:$FULLDIRECTORY/wrapper-lock:" "$GOTO_GCC_WRAPPER_INSTALL_DIR/cflags"
  fi

  # tell environment about new installation directory
  export PATH="$GOTO_GCC_WRAPPER_INSTALL_DIR:$PATH"

  # check whether hook worked
  NEW_GCC="$(which gcc)"
  NEW_LD="$(which ld)"

  if [ ! "$NEW_GCC" == "$GOTO_GCC_WRAPPER_INSTALL_DIR/gcc" ]
  then
    echo "error: failed to install goto-gcc wrapper for gcc: $NEW_GCC vs $GOTO_GCC_WRAPPER_INSTALL_DIR/gcc"
    # remove wrapper again
    source remove-wrapper.sh $KEEP_DIRECTORY
  elif [ ! "$NEW_LD" == "$GOTO_GCC_WRAPPER_INSTALL_DIR/ld" ]
  then
    echo "error: failed to install goto-gcc wrapper for ld: $NEW_LD vs $GOTO_GCC_WRAPPER_INSTALL_DIR/ld"
    # remove wrapper again
    source remove-wrapper.sh $KEEP_DIRECTORY
  else
    echo "success: INSTALLED wrapper to $GOTO_GCC_WRAPPER_INSTALL_DIR"
  fi
}
