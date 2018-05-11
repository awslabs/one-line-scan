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
# Evaluate the plain wrapper run

# Evaluate and return non-zero in case of failure
function evaluate_plain
{
  local -r RESULTS_DIR="$WORKINGDIR/plain"
  local -r CALLLOG="$RESULTS_DIR/calls.json"
  local -r REPLAYLOG="$RESULTS_DIR/replay.log"

  echo "found $(cat $REPLAYLOG | wc -l) calls to the compiler"
  [ ! -f "$REPLAYLOG" ] || echo "calls to replay can be found in: $REPLAYLOG"
  [ ! -f "$CALLLOG" ] || echo "more structured calls can be found in: $CALLLOG"
  return 0
}
