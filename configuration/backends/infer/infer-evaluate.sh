#  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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
# Evaluate the infer wrapper run

# Evaluate and return non-zero in case of failure
function evaluate_infer() {
  local -r RESULTS_DIR="$WORKINGDIR/infer"
  local -r INFER_OUTPUT_DIR="$RESULTS_DIR/combined_output"

  echo "Combining compilation databases into a single one ..."
  echo "[" >"$RESULTS_DIR"/combined_compilation_database.json
  find "$RESULTS_DIR"/deps_output -name "*.json" |
    sort -g |
    xargs cat |
    sed '$ s:},$:}:g' >>"$RESULTS_DIR"/combined_compilation_database.json
  echo "]" >>"$RESULTS_DIR"/combined_compilation_database.json

  echo "Running capturing from compilation database ..."
  infer capture -o "$INFER_OUTPUT_DIR" \
    --compilation-database "$RESULTS_DIR"/combined_compilation_database.json

  # run analysis on combined output from "infer capture --continue" calls
  echo "Running infer analyze ..."
  infer analyze \
    --keep-going \
    --bufferoverrun \
    --litho \
    --pulse \
    --quandary \
    --quandaryBO \
    -o "$INFER_OUTPUT_DIR" &>"$RESULTS_DIR"/infer_analyze.log

  # Other, potentially relevant, parameter to infer analyze:
  #     --purity \
  #     --loop-hoisting \

  if [ -r ""$INFER_OUTPUT_DIR"/report.json" ]; then
    # Turn the output of this JSON file into a gcc-style comments file
    cat "$INFER_OUTPUT_DIR"/report.json |
      python3 "$WORKINGDIR"/transform_report.py >"$RESULTS_DIR"/gcc_style_report.txt

    # Show the gcc-style results
    cat "$RESULTS_DIR"/gcc_style_report.txt
  else
    echo "error: did not find report.json from Infer analysis"
    return 1
  fi

  return 0
}
