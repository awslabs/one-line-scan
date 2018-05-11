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

# Evaluate and return non-zero in case of failure
function evaluate_cbmc
{
  local -r LOGDIR="$WORKINGDIR/log"
  local UNWIND=1
  local DEPTH=250
  local -r SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  # check whether there are environment variables that control the cbmc behavior
  [ -z "$CBMC_UNWIND" ] || UNWIND="$CBMC_UNWIND"
  [ -z "$CBMC_DEPTH" ] || DEPTH="$CBMC_DEPTH"

  mkdir -p "$LOGDIR"

  # collect all binaries and link them against the produced libraries
  log "perform analyze on binaries ($(cat $WORKINGDIR/binaries.list 2> /dev/null | wc -l))"
  mkdir -p $WORKINGDIR/log
  local ANALYSISRESULT=0
  for f in $(cat $WORKINGDIR/binaries.list 2>/dev/null)
  do
    # try analysis only if the binary (still) exists
    if [ ! -x $f ]
    then
      continue
    fi

    log "analyze $f via $SRC_DIR/inspect-binary.sh $ANALYSIS_OPTIONS --logdir $LOGDIR $f "$BINARY_ORIGIN" $UNWIND $DEPTH"
    # use pretty simple analysis here
    $SCRIPT_CALLER $SRC_DIR/inspect-binary.sh $ANALYSIS_OPTIONS --logdir "$LOGDIR" $f "$BINARY_ORIGIN" $UNWIND $DEPTH
    EXITSTATUS=$?
    [ $ANALYSISRESULT -ne 0 ] || ANALYSISRESULT=$EXITSTATUS
  done
  return $ANALYSISRESULT
}
