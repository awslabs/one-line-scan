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

# drop gcc parameters that clang does not understand from compilation database
function prepare_gcc_compilation_db_for_clang() {
  local -r DB="$1"

  # Make sure we keep the original compilation database, so that we can easily restore it.
  cp "$DB" "$DB".original

  local -a BAD_PARAMS=("-mskip-rax-setup" "-mindirect-branch=thunk-extern")
  BAD_PARAMS+=("-mindirect-branch-register" "-mpreferred-stack-boundary=2")
  BAD_PARAMS+=("-fno-var-tracking-assignments" "-fconserve-stack")

  for PATTERN in "${BAD_PARAMS[@]}"; do
    sed -i "s:,\"${PATTERN}\"::g" "$DB"
  done
}

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

  prepare_gcc_compilation_db_for_clang "$RESULTS_DIR"/combined_compilation_database.json

  echo "Running capturing from compilation database (storing output in "$RESULTS_DIR"/infer_capture.log) ..."
  infer capture --keep-going -o "$INFER_OUTPUT_DIR" \
    --compilation-database "$RESULTS_DIR"/combined_compilation_database.json &>"$RESULTS_DIR"/infer_capture.log
  grep " errors generated." "$RESULTS_DIR"/infer_capture.log | sort -u

  # run analysis on combined output from "infer capture --continue" calls
  echo "Running infer analyze (storing output in "$RESULTS_DIR"/infer_analyze.log) ..."
  infer analyze \
    --keep-going \
    --bufferoverrun \
    --litho \
    --pulse \
    --quandary \
    --quandaryBO \
    -o "$INFER_OUTPUT_DIR" &>"$RESULTS_DIR"/infer_analyze.log

  CLANG_ERROR_COUNT=$(grep "Error: the following clang command did not run successfull" -c "$RESULTS_DIR"/infer_capture.log)

  # Other, potentially relevant, parameter to infer analyze:
  #     --purity \
  #     --loop-hoisting \

  if [ -r ""$INFER_OUTPUT_DIR"/report.json" ]; then
    # Turn the output of this JSON file into a gcc-style comments file
    cat "$INFER_OUTPUT_DIR"/report.json |
      python3 "$RESULTS_DIR"/transform_report.py >"$RESULTS_DIR"/gcc_style_report.txt

    # Show the gcc-style results
    cat "$RESULTS_DIR"/gcc_style_report.txt

    echo "Clang capture errors: $CLANG_ERROR_COUNT"
  else
    echo "error: did not find report.json from Infer analysis"
    echo "Clang capture errors: $CLANG_ERROR_COUNT"
    return 1
  fi

  return 0
}
