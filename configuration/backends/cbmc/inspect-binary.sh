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
# Analyze a single binary with the given options
#
# Usage:
# See usage() function below, or just run the script without parameters

# locate the script to be able to call related scripts
SCRIPT=$(readlink -e "$0")
SCRIPTDIR=$(dirname "$SCRIPT")

set -eux

# limit the memory that can be used when being executed by this script
source $SCRIPTDIR/../../utils/limit-resources.sh
limit_memory

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

  EXIT_CODE=0
  if [ -x /usr/bin/time ]
  then
    /usr/bin/time -f %e\ %U\ %P\ %M --output="$OUTPUT_FILE" $COMMAND || EXIT_CODE=$?
  else
    $COMMAND || EXIT_CODE=$?
    echo "- - - -" > "$OUTPUT_FILE"
  fi
  return $EXIT_CODE
}

usage()
{
	cat << EOF
usage:
inspect-binary.sh [OPTIONS] binary source-of-binary loop-unwind-limit depth

  binary            ... location to the binary
  source-of-binary  ... where does the binary come from
  loop-unwind-limit ... how much loop unrolling should be performed during the analysis
  depth             ... how long should the maximum reachable path be

OPTIONS:
  --logdir DIR      ... directory to store the logs
  --symex           ... use symex instead of cbmc (symbolic execution instead of BMC model checking)
  --timeout SEC     ... allow only SEC seconds for the analysis, or abort
  --library         ... treat target as library, start analysis from multiple entry points ( all functions with no parameter )
EOF
}

# start with an empty directory for logging, that can be overwritten by a default value later
LOGDIR=
TOOL=cbmc
TIMEOUT=
LIBRARY=

# parse arguments
while [ $# -gt 0 ]
do
    case $1 in
    --logdir)   LOGDIR="$2"; shift;;
    --symex)    TOOL=symex;;
    --help |-h) usage
                exit 0;;
    --timeout)  TIMEOUT="$2"; shift;;
    --library)  LIBRARY=t;;
           *)   break; ;;
    esac
    shift
done

FILENAME=$1
SOURCELOCATION=$2
UNWIND=$3
DEPTH=$4

# check number of parameters
if [ -z $DEPTH ]
then
  usage
  exit 1
fi

# check whether cbmc and goto-instrument are available in the PATH
if ! command -v goto-instrument > /dev/null 2>&1
then
	echo "error: cannot find goto-instrument - abort" 1>&2
	exit 1
fi

# generic check for the selected tool
if ! command -v "$TOOL" > /dev/null 2>&1
then
	echo "error: cannot find $TOOL - abort" 1>&2
	exit 1
fi

# setup a working directory, and temporary file
TMPDIR=$(mktemp -d)
TMP=$(mktemp)
TMPPROPERTIES=$(mktemp)

# call this when exiting the script
# cleans up the used files
exit_handler()
{
  rm -rf $TMPDIR $TMP $TMPPROPERTIES
}

# install the exit handler
trap exit_handler EXIT

# handle to the binary
BINARYNAME=$(basename $FILENAME)
TARGETBINARY=$TMPDIR/$BINARYNAME

# load functions for logging
. "$SCRIPTDIR/../../utils/log.sh"

#
# DEFINITIONS FOR THE SCRIPT
#
# log versions (including their headers)
PROPERTYLOGVERSION=2
#TIMEMETRICS=WallTime CPUTime CPUutilization MaxMemory
# header = "$PROPERTYLOGVERSION $TIMESTAMP show-properties $SOURCELOCATION $BINARYNAME $ANALYSIS_RESULT $PROPERTIES $SHORTESTPATH WallTime CPUTime CPUutilization MaxMemory"
ANALYZEALLLOGVERSION=4
# header = "$ANALYZEALLLOGVERSION $TIMESTAMP analyzse-all-properties $SOURCELOCATION $BINARYNAME $function $UNWIND $DEPTH $ANALYSIS_RESULT $FAILEDPROPERTIES WallTime CPUTime CPUutilization MaxMemory"
ANALYZESINGLELOGVERSION=3
# header = "$ANALYZESINGLELOGVERSION $TIMESTAMP analyzse-single-property $SOURCELOCATION $BINARYNAME $function $UNWIND $DEPTH $ANALYSIS_RESULT $p $COUNTEREXAMPLESTEPS $DECISIONPROCEDURETIME WallTime CPUTime CPUutilization MaxMemory"
ANALYZESYMEXVERSION=2
# header = "$ANALYZESYMEXVERSION $TIMESTAMP symex $SOURCELOCATION $BINARYNAME $function $UNWIND $DEPTH $LOG_TIMEOUT $ANALYSIS_RESULT $COUNTER_EXAMPLES TOTAL_PROPERTIES WallTime CPUTime CPUutilization MaxMemory"
# basic log location
if [ -z $LOGDIR ]
then
	LOGDIR=$SCRIPTDIR/log
fi

# make sure the logging directory exists
mkdir -p $LOGDIR

#
# instrument the binary
#
INSTRUMENT_ERROR=$(mktemp)
log "instrument binary $FILENAME, write result to $TARGETBINARY"
INSTRUMENT_STATUS=0
goto-instrument --bounds-check --pointer-check --memory-leak-check \
                --signed-overflow-check --div-by-zero-check --undefined-shift-check \
                --nan-check --float-overflow-check --stack-depth 10 \
                --model-argc-argv 4 --conversion-check \
                $FILENAME $TARGETBINARY > $INSTRUMENT_ERROR 2>&1 || INSTRUMENT_STATUS=$?
log "instrumenting the binary finished with status: $INSTRUMENT_STATUS"
if [ $INSTRUMENT_STATUS -ne 0 ]
then
  echo "abort due to unsuccessful binary instrumentation" 1>&2
  cat $INSTRUMENT_ERROR
  rm -f $INSTRUMENT_ERROR
  exit $INSTRUMENT_STATUS
fi
rm -f $INSTRUMENT_ERROR

#
# show properties of the binary
#
# use logs
PROPERTYLOG="$LOGDIR/cbmc-properties.log"
SINGLEPROPERTYLOG="$LOGDIR/properties/$BINARYNAME.log"
mkdir -p $(dirname $SINGLEPROPERTYLOG)

# list all available properties
ANALYSIS_RESULT=0
measured_execution $TMP cbmc --show-properties $TARGETBINARY \
  > "$SINGLEPROPERTYLOG" 2>&1 || ANALYSIS_RESULT=$?
log "property analysis ended with $ANALYSIS_RESULT"
TIMEMETRICS=$(cat $TMP)
TIMESTAMP=$(( $(date +%s%N) / 1000000 ))
# collect number of all properties
PROPERTIES=$(grep "^Property " $SINGLEPROPERTYLOG | wc -l)
# also go for path properties
goto-instrument --print-path-lengths $TARGETBINARY >> "$SINGLEPROPERTYLOG" 2>&1
SHORTESTPATH=$(grep "^Shortest control-flow path:" "$SINGLEPROPERTYLOG" | awk '{print $4}')
# make sure the date ends up in the log
LOGENTRY="$TIMESTAMP show-properties $SOURCELOCATION $BINARYNAME $ANALYSIS_RESULT $PROPERTIES $SHORTESTPATH $TIMEMETRICS"
echo "$LOGENTRY" >> "$PROPERTYLOG"

#
# analyze whether properties fail (given unwinding and search depth limitation)
#
# use logs
ALLLOG="$LOGDIR/cbmc-allproperties.log"
SINGLELOG="$LOGDIR/cbmc-singleproperty.log"
SYMEXLOG="$LOGDIR/symex.log"
VIOLATION_OUTPUT="$LOGDIR/violation/$BINARYNAME-d$DEPTH-uw$UNWIND.$TOOL.log"
mkdir -p $(dirname "$VIOLATION_OUTPUT")

# as CBMC currently does not support specifying a timeout, wrap the call with
# the timeout tool, that kills CBMC after the given amount of time
TIMEOUT_CALL=
if [ -n "$TIMEOUT" ]
then
  log "set timeout to $TIMEOUT"
  TIMEOUT_CALL="/usr/bin/timeout -s KILL $TIMEOUT"
fi

# store all starting points (functions) in the following file
FUNCTIONS=$(mktemp)
if [ -z "$LIBRARY" ]
then
  # in case its a binary, we want to start scanning starting with the main function (and it has to be the first function)
  goto-instrument --list-symbols $TARGETBINARY | awk '{print $1}' | grep "^main$" 2> /dev/null > $FUNCTIONS;
else
  # in case of a library, we furthermore want to scan from other functions, currently only the ones without parameters
  goto-instrument --list-symbols $TARGETBINARY | grep "(void)" 2> /dev/null | awk '{print $1}' >> $FUNCTIONS;
fi
NUM_FUNCTIONS=$(cat $FUNCTIONS | wc -l)
log "will perform analysis on $NUM_FUNCTIONS entry points"

# iterate over all functions / entry points and perform analysis
# as C conventions do not alow spaces in function names, a simple for loop works here
NUM_ENTRYPOINT=1
for function in $(cat $FUNCTIONS)
do
  log "perform scan on entry point $NUM_ENTRYPOINT / $NUM_FUNCTIONS : function $function"
  NUM_ENTRYPOINT=$(($NUM_ENTRYPOINT+1))

  # choose form of analysis
  if [ "$TOOL" = "cbmc" ]
  then

    # perform analysis to check whether properties fail, ignore dependent libraries for now
    rm -f $TMP
    ANALYSIS_RESULT=0
    measured_execution $TMP \
      $TIMEOUT_CALL \
      cbmc --unwind $UNWIND --verbosity 8 --depth $DEPTH \
      --all-properties $TARGETBINARY   \
      --function $function \
      > "$VIOLATION_OUTPUT" 2>&1 || ANALYSIS_RESULT=$?
    log "checking for failed properties ended with $ANALYSIS_RESULT"
    TIMEMETRICS=$(tail -n 1 $TMP)
    TIMESTAMP=$(( $(date +%s%N) / 1000000 ))

    # look for failed properties
    grep ": FAILURE$"  $VIOLATION_OUTPUT | awk '{print $1}' | sed s:^.::g | sed s:]$::g > $TMPPROPERTIES
    FAILEDPROPERTIES=$(cat $TMPPROPERTIES | wc -l)

    # make sure the date ends up in the log
    LOGENTRY="$TIMESTAMP analyzse-all-properties $SOURCELOCATION $BINARYNAME $function \
      $UNWIND $DEPTH $ANALYSIS_RESULT $FAILEDPROPERTIES $TIMEMETRICS"
    log "stored log: $VIOLATION_OUTPUT"
    echo "$LOGENTRY" >> "$ALLLOG"

    #
    # iterate over all single properties and create counter examples for them
    #
    iteration=1
    mkdir -p "$LOGDIR/violation/single"
    for p in $(cat $TMPPROPERTIES)
    do
      FAILEDPROPERTYLOG="$LOGDIR/violation/single/$BINARYNAME-d$DEPTH-uw$UNWIND.log-failure$iteration.log"

      rm -f $TMP
      ANALYSIS_RESULT=0
      measured_execution $TMP \
        $TIMEOUT_CALL \
        cbmc --unwind $UNWIND --verbosity 8 --depth $DEPTH \
        --property $p $TARGETBINARY      \
        --function $function
        >> "$FAILEDPROPERTYLOG" 2>&1 || ANALYSIS_RESULT=$?
      # echo "Wall CPU CPUutilization Memory(kB)" >> $TASKDIR/build-metrics.log
      log "counter example generation for ($iteration / $FAILEDPROPERTIES) ended with $ANALYSIS_RESULT"
      TIMEMETRICS=$(tail -n 1 $TMP)
      TIMESTAMP=$(( $(date +%s%N) / 1000000 ))
      # count number of steps in counter example
      COUNTEREXAMPLESTEPS=$(grep "^State " "$FAILEDPROPERTYLOG" | tail -n 1 | awk '{if ($2 != "") print $2; else print "-"}')
      DECISIONPROCEDURETIME=$(grep "Runtime decision procedure: " "$FAILEDPROPERTYLOG" | awk '{print $4 * 1}')

      LOGENTRY="$TIMESTAMP analyzse-single-property $SOURCELOCATION $BINARYNAME $function \
        $UNWIND $DEPTH $ANALYSIS_RESULT $p $COUNTEREXAMPLESTEPS $DECISIONPROCEDURETIME $TIMEMETRICS"
      echo "$LOGENTRY" >> "$SINGLELOG"

      iteration=$(($iteration+1))
    done
  # we have TOOL != cbmc
  else
    # test for timeout, and enable the tool side timeout if possible
    ANALYSIS_TIME=
    if [ -n "$TIMEOUT" ] && [ $TIMEOUT -gt 10 ]
    then
      ANALYSIS_TIME="--max-search-time $(($TIMEOUT-10))"
    fi

    # perform analysis to check whether properties fail, ignore dependent libraries for now
    rm -f $TMP
    TIMEOUT_CALL= # disable timeout call when using symex
    log "run: symex $TARGETBINARY"
    ANALYSIS_RESULT=0
    measured_execution $TMP \
      symex \
      $ANALYSIS_TIME \
      $TARGETBINARY   \
      --unwind $UNWIND --depth $DEPTH \
      --function $function \
      > "$VIOLATION_OUTPUT" 2>&1 || ANALYSIS_RESULT=$?
    #for now, use the full "power" of symex without any limitations, otherwise: --unwind $UNWIND --depth $DEPTH
    log "checking for failed properties ended with $ANALYSIS_RESULT"
    TIMEMETRICS=$(tail -n 1 $TMP)
    TIMESTAMP=$(( $(date +%s%N) / 1000000 ))
    LOG_TIMEOUT=-
    [ -n "$TIMEOUT" ] && LOG_TIMEOUT=$TIMEOUT
    COUNTER_EXAMPLES=$(grep -e "^\*\* [0-9]\+ of [0-9]\+ failed$" "$VIOLATION_OUTPUT" 2> /dev/null | awk '{print $2,$4}')
    [ -n "$COUNTER_EXAMPLES" ] || COUNTER_EXAMPLES="- -"
    LOGENTRY="$TIMESTAMP symex $SOURCELOCATION $BINARYNAME $function $UNWIND $DEPTH \
      $LOG_TIMEOUT $ANALYSIS_RESULT $COUNTER_EXAMPLES $TIMEMETRICS"
    log "stored log: $VIOLATION_OUTPUT"
    echo "$LOGENTRY" >> "$SYMEXLOG"
    exit $ANALYSIS_RESULT
  fi

done

# clean up
rm -f $FUNCTIONS
