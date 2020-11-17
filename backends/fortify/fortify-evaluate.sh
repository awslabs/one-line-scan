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

# Evaluate and return non-zero in case of failure
function evaluate_fortify
{
  local -r SRC_DIR="$( dirname "${BASH_SOURCE[0]}" )"

  $SCRIPT_CALLER "$SRC_DIR"/fortify-scan.sh $ANALYSIS_OPTIONS $FORTIFY_ANALYSIS_CONFIG \
    --logdir "$WORKINGDIR"/log "$BINARY_ORIGIN" $WORKINGDIR/fortify-data
  ANALYSISRESULT=$?

  # summarize the results, if an html is present
  if [ -f "$WORKINGDIR"/log/report.html ]
  then
    python "$SRC_DIR"/summarize-fortify.py $WORKINGDIR \
      >> $WORKINGDIR/log/fortify-summary.txt || touch $WORKINGDIR/log/fortify-summary.txt

    if [ -n $GITUPSTREAM ]
    then
      $SCRIPT_CALLER "$SCRIPTDIR"/utils/display-series-data.sh \
        "$WORKINGDIR/log/fortify-summary.txt" $GITUPSTREAM $GITBRANCH \
        > $WORKINGDIR/log/fortify-summary-filtered.txt
      FILTER_STATUS=$?
      # on the given git commit range, no defects mean successful analysis
      if [ $FILTER_STATUS -eq 0 ] && [ $ANALYSISRESULT -eq 10 ]
      then
        ANALYSISRESULT=0
      fi
    fi
  else
    touch $WORKINGDIR/log/fortify-summary.txt
  fi
  log "Fortify summary and FPR file can be found at: $WORKINGDIR/log"

  return $ANALYSISRESULT
}
