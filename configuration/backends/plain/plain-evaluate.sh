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
# Evaluate the plain wrapper run

# Evaluate and return non-zero in case of failure
function evaluate_plain
{
  local -r RESULTS_DIR="$WORKINGDIR/plain"
  local -r CALLLOG="$RESULTS_DIR/calls.json"
  local -r REPLAYLOG="$RESULTS_DIR/replay.log"
  local -r CMDB="$RESULTS_DIR"/compilation_database.json

  if [ -n "$(find "$RESULTS_DIR"/compilation_databases -name "*.json" 2> /dev/null)" ]
  then
    echo "Combining compilation databases into a single one ..."
    echo "[" > "$CMDB"
    find "$RESULTS_DIR"/compilation_databases -name "*.json" | \
      sort -g | \
      xargs cat | \
      sed  '$ s:},$:}:g' >> "$CMDB"
    echo "]" >> "$CMDB"
  else
    echo "Did not find JSON files to assemble a compilation database"
  fi

  echo "found $(cat $REPLAYLOG | wc -l) calls to the compiler"
  [ ! -f "$REPLAYLOG" ] || echo "calls to replay can be found in: $REPLAYLOG"
  [ ! -f "$CALLLOG" ] || echo "more structured calls can be found in: $CALLLOG"
  [ ! -f "$RESULTS_DIR/compilation_database.json" ] || echo "Combilation database can be found in: $CMDB"
  return 0
}
