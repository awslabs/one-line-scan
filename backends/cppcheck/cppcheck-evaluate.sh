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
# Evaluate the cppcheck output of an cppcheck analysis run

# Evaluate and return non-zero in case of failure
function evaluate_cppcheck
{
  local -r RESULTS_DIR="$WORKINGDIR/cppcheck/results"
  local -r LOGDIR="$WORKINGDIR/log"
  mkdir -p "$LOGDIR"
  local -r LOGFILE="$LOGDIR/cppcheck.log"

  TOTAL_DEFECTS=0
  TOTAL_ERRORS=0
  TOTAL_FILES=$(ls "$RESULTS_DIR/" 2> /dev/null | wc -l)

  ERROR_FILES=

  for f in $(ls "$RESULTS_DIR"/* 2> /dev/null)
  do
    DEFECTS=$(cat $f | grep -v "^::" | grep -v "(information) Couldn't find path given by -I" | wc -l)
    ERRORS=$(grep " (error:" "$f" | wc -l)

    ERROR_FILES+=" $f"

    TOTAL_DEFECTS=$((TOTAL_DEFECTS + DEFECTS))
    TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))
  done

  log "Cppcheck found $TOTAL_ERRORS errors in $TOTAL_DEFECTS total defects in $TOTAL_FILES files" |& tee "$LOGFILE"
  echo "ERRORS:" | tee -a "$LOGFILE"
  [ -z "$ERROR_FILES" ] || grep " (error:" $ERROR_FILES | sort -V -u | tee -a "$LOGFILE" || true  # display errors, in case we found some
  echo "RUNTIME INFO:" | tee -a "$LOGFILE"
  grep "^::" "$RESULTS_DIR"/* | sort -u | tee -a "$LOGFILE" || true # display cppcheck runtime info (each once)
  echo "DEFECT DISTRIBUTION:" | tee -a "$LOGFILE"
  grep -v "^::" "$RESULTS_DIR"/* | grep -v "(information) Couldn't find path given by -I" | \
    awk '{print $2}' | sort | uniq -c | sort -n -r | tee -a "$LOGFILE"
  log "Cppcheck results per source file can be found in: $WORKINGDIR/cppcheck/results/" |& tee -a "$LOGFILE"

  [ "$TOTAL_ERRORS" -eq 0 ] || return 1
  return 0
}
