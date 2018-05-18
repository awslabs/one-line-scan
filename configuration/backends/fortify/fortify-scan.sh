#!/bin/bash
#
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
# Scan a codebase using Fortify
#
# Usage:
# See usage() function below, or just run the script without parameters

# locate the script to be able to call related scripts
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")

# load functions for logging
. "$SCRIPTDIR/../../utils/log.sh"

RULEDIRS=

# limit the memory that can be used when being executed by this script
source $SCRIPTDIR/../../utils/limit-resources.sh

#
# execute a given command and store Wall time, CPU time, CPU utilization, used memory
# currently this relies on the command /usr/bin/time being available
# otherwise, no measurement is reported
#
measured_execution ()
{
  OUTPUT_FILE="$1"
  shift
  COMMAND="$@"

  if [ -x /usr/bin/time ]
  then
    echo "measure in ${PWD}: /usr/bin/time -f %e\ %U\ %P\ %M --output=$OUTPUT_FILE $COMMAND"
    /usr/bin/time -f %e\ %U\ %P\ %M --output="$OUTPUT_FILE" $COMMAND
    EXIT_CODE=$?
  else
    $COMMAND
    EXIT_CODE=$?
    echo "- - - -" > "$OUTPUT_FILE"
  fi
  return $EXIT_CODE
}

usage()
{
	cat << EOF
usage:
fortify-scan.sh [OPTIONS] source-of-project data-directory

  source-of-project ... origin of source code, determines build id
  data-directory    ... Fortify build data

OPTIONS:
  --logdir DIR      ... directory to store the logs
  --rules DIR       ... directory or file with additional rules (specify multiple times)
  --symex           ... ignored for compatibility
  --timeout SEC     ... allow only SEC seconds for the analysis, or abort
EOF
}

# start with an empty directory for logging, that can be overwritten by a default value later
LOGDIR=
TIMEOUT=

# parse arguments
while [ $# -gt 0 ]
do
    case $1 in
    --logdir)   LOGDIR="$2"; shift;;
    --symex)    true;;
    --help |-h) usage
                exit 0;;
    --timeout)  TIMEOUT="$2"; shift;;
    --rules)    if [ -n "$2" ]
                then
                  RULEDIRS="$RULEDIRS -rules $2"
                  shift
                else
                  log "warning: specified --rules parameter without value"
                fi
                ;;
           *)   break; ;;
    esac
    shift
done

ORIGIN=$1
DATADIR=$2

# check number of parameters
if [ -z $DATADIR ]
then
  usage
  exit 1
fi

# generic check for the selected tool
if ! command -v "sourceanalyzer" > /dev/null 2>&1
then
	echo "error: cannot find sourceanalyzer - abort" 1>&2
	exit 1
fi

# setup a working directory, and temporary file
TMP=$(mktemp)

# call this when exiting the script
# cleans up the used files
exit_handler()
{
  rm -rf $TMP
}

# install the exit handler
trap exit_handler EXIT

#
# DEFINITIONS FOR THE SCRIPT
#
# basic log location
if [ -z "$LOGDIR" ]
then
	LOGDIR=$SCRIPTDIR/log
fi

# load wrapper library
source "$SCRIPTDIR/../../inject-gcc-wrapper/ols-library.sh"

# indicate whether we actually performed a scan
ANALYSIS_HAPPENED=t

# make sure the logging directory exists
mkdir -p $LOGDIR
AVAILABLE_MEM="$(usable_memory_in_M)"
log "limit memory of Fortify to ${AVAILABLE_MEM}M"
FORTIFY_BUILD_ID=$(echo "$ORIGIN" | sed 's%[:/#@]%_%g')
# execute source analyzer (eventually load different environment for java)
load_ols_env &>> $LOGDIR/fortify-scan.log
SCA=$(which sourceanalyzer)
SCAMAJORVERSION=$($SCA -version 2> /dev/null | grep -o -e "Fortify Static Code Analyzer [0-9]\{1,2\}" | grep -o -e "[0-9]\{1,2\}")

# if the major version of Fortify is more recent that 17, use 4 cores for the analysis
MTCOMMAND=""
CORES=1
if [ -n "$SCAMAJORVERSION" ] && [ "$SCAMAJORVERSION" -ge 17 ]; then
  # make sure we use parallel analysis only if enough memory is available
  # do not enable -mt at all, because otherwise the cores preset of Fortify would be used
  if [ "$AVAILABLE_MEM" -ge 32000 ]; then
    CORES=$(($AVAILABLE_MEM / 16000))
    MTCOMMAND="-mt -Dcom.fortify.sca.ThreadCount=$CORES"
  fi
fi

log "use sourceanalyzer with $CORES cores from $SCA ($(file $SCA))"
measured_execution $TMP sourceanalyzer -b $FORTIFY_BUILD_ID \
  -Dcom.fortify.WorkingDirectory=$DATADIR \
  -Dcom.fortify.sca.ProjectRoot=$DATADIR \
  -Dcom.fortify.sca.limiters.MaxIndirectResolutionsForCall=1024 \
  -scan -verbose \
  $MTCOMMAND \
  -Xmx${AVAILABLE_MEM}M \
  -f $LOGDIR/report.fpr -html-report 2>&1 | tee $LOGDIR/fortify-scan.log
ANALYSIS_RESULT=$?
# unload environment again
unload_ols_env &>> $LOGDIR/fortify-scan.log
log "fortify scan ended with $ANALYSIS_RESULT"
log "  internal errors:"
log "$(grep "^\[error\]:" $LOGDIR/fortify-scan.log 2> /dev/null)"

# if no files have been there to be scanned, this is not an error but should
# be forwarded
if [ $ANALYSIS_RESULT -ne 0 ] && [ ! -f .sca.pid ]; then
  log "warning: could not find analysis files. Have you compiled any files?"
  ANALYSIS_RESULT=0
  ANALYSIS_HAPPENED=
fi

# only have metrics if we actually scanned something
# otherwise, a warning is printed above already
if [ -n "$ANALYSIS_HAPPENED" ]; then
	TIMEMETRICS=$(cat $TMP)
	TIMESTAMP=$(( $(date +%s%N) / 1000000 ))
	# collect number of all warnings
	FINDINGS=$(grep "Rendering" $LOGDIR/fortify-scan.log 2>/dev/null | awk 'BEGIN {r="-"} {if( $2 +0 >= 0 ) r=$2} END {print r}')
	if [ -z "$FINDINGS" ]
	then
		log "error: could not find reported number of Fortify findings"
		ANALYSIS_RESULT=1
	else
		if [ "$FINDINGS" -gt 0 ]
		then
			ANALYSIS_RESULT=10
		fi
	fi
	ANALYZEDFILES=$(grep "^Analyzing " "$LOGDIR"/fortify-scan.log 2>/dev/null | grep " source file(s)$" | awk 'BEGIN {r="-"} {if( $2 +0 >= 0 ) r=$2} END {print r}')
	# make sure the date ends up in the log
	LOGENTRY="$TIMESTAMP fortify $ORIGIN ALL ALL \
		0 0 $ANALYSIS_RESULT $FINDINGS $ANALYZEDFILES $TIMEMETRICS"
	echo "$LOGENTRY" >> $LOGDIR/fortify-scan.log
fi

exit $ANALYSIS_RESULT
