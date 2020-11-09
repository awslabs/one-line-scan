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
# Library that offers functionality used by backend wrappers

# locate the wrapped binary on the PATH
next_in_path ()
{
  local cmd=$1
  local inst_path=$(dirname $SCRIPT)
  local subdir=$2
  if [ -n "$subdir" ]
  then
    inst_path=${inst_path%/$subdir}
  fi
  ifs=$IFS
  IFS=:
  state=0
  for p in $PATH
  do
    if [ "$SCRIPT" = "$(readlink -e $p/$cmd)" ]
    then
      state=1
    elif [ $state -eq 0 ] && [ -z "$subdir" -o "$inst_path" != "$(readlink -e $p)" ] && [ -x $p/$cmd ]
    then
      IFS=$ifs
      echo $p/$cmd
      return 0
    elif [ $state -eq 1 ] && [ -x $p/$cmd ]
    then
      IFS=$ifs
      echo $p/$cmd
      return 0
    fi
  done

  IFS=$ifs
  if [ $state -eq 0 ]
  then
    echo "error: $SCRIPT not found in PATH" 1>&2
    echo "/bin/false"
  else
    echo "error: $cmd not found in PATH" 1>&2
    echo "/bin/false"
  fi
  return 1
}

# explicit exit handler function
exit_handler ()
{
   rm -rf "$TRAPDIR"
   rm -f "$WRAPPERPIDFILE$$"
}

# get parent id of pid that is handed in
function called_by_wrapper
{
  parent=$(ps -p $1 -o ppid=  | tr -d " " )
  # reached calling root
  if [ "$parent" -le "1" ] || [ -z "$parent" ]
  then
    return 0
  fi
  # wrapper pid file exists with given PID?
  if [ -f "$WRAPPERPIDFILE$parent" ]
  then
    return 1
  fi
  # else call function with pid of parent
  called_by_wrapper $parent
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

# print/store logging output
function logwrapper
{
  local name=$1
  shift
  echo "[$name-WRAPPER,$$] $@" >> $LOG #1>&2
  return 0
}

# load content of all OLS_X variables into X, and store a backup of X
function load_ols_env
{
  # do not allow to call this method twice
  [ -z "$LOADED_OLS_ENV" ] || return
  # iterate over all variables in env that start with OLS_
  for SP_VAR in $(env | grep ^OLS_ | cut -f1 -d=); do
    # get the part behind the "=" char
    local SP_VAL="${SP_VAR%=*}"
    # cut off OLS prefix and get the part behind the "=" char
    local VAR="${SP_VAR##OLS_}"
    VAR="${VAR%=*}"
    # backup the previous value of the variable
    [ -n "${!VAR}" ] && export BACKUP_OLS_$VAR="${!VAR}"
    # set the new value of the variable
    echo "overwrite environment variable: $VAR=${!SP_VAL}" 1>&2
    export $VAR="${!SP_VAL}"
  done
  # memorize that we called this method already
  export LOADED_OLS_ENV=t
}

# restore (or unset) content of all variables X for which a OLS_X exists
function unload_ols_env
{
  # do not unload, if no environment has been loaded
  [ -n "$LOADED_OLS_ENV" ] || return
  # iterate over all variables in env that start with OLS_
  for SP_VAR in $(env | grep ^OLS_ | cut -f1 -d=); do
    # cut off OLS prefix and get the part behind the "=" char
    local VAR="${SP_VAR##OLS_}"
    VAR="${VAR%=*}"
    local BACKUP_VAR=BACKUP_OLS_$VAR
    # restore backup
    if [ -n "${!BACKUP_VAR}" ]
    then
      export $VAR="${!BACKUP_VAR}"
      echo "restore variable $VAR=${!VAR}" 1>&2
    else
      # if there has not been an initial value, make sure we remove the value
      echo "unset variable $VAR" 1>&2
      unset $VAR
    fi
    # remove the backup variable as well
    unset "$BACKUP_VAR"
  done
  # memorize that we cleaned up the environment again
  unset LOADED_OLS_ENV
}
