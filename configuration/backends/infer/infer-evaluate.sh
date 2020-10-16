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
# Evaluate the infer wrapper run

# Drop gcc parameters that clang does not understand from compilation database
# This is a cache for the automated parameter drop mechanism implemented in the
# below capture function infer_capture
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

# Check the capture log for recoverable errors, and adapt compilation DB accordingly
# Return success (0) in case we should retry
function needs_capturing_retry() {
  local -r COMPILATION_DB="$1"
  local -r CAPTURE_LOG="$2"

  if grep -q "clang.*: error: unknown argument:" "$CAPTURE_LOG"; then
    echo "Found recoverable retry error"
    local -a ARGUMENTS=($(awk '/clang.*: error: unknown argument:/ {print $NF}' "$CAPTURE_LOG" | sort -u | tr -d "'"))

    for ARGUMENT in "${ARGUMENTS[@]}"; do
      sed -i "s:,\"${ARGUMENT}\"::g" "$COMPILATION_DB"
    done

    return 0
  fi

  return 1 # no errors found the require a retry
}

function infer_capture() {
  local -r RESULTS_DIR="$1"
  local -r INFER_OUTPUT_DIR="$2"

  prepare_gcc_compilation_db_for_clang "$RESULTS_DIR"/combined_compilation_database.json

  echo "Running capturing from compilation database (storing output in "$RESULTS_DIR"/infer_capture.log) ..."
  while true; do
    infer capture --keep-going -o "$INFER_OUTPUT_DIR" \
      --compilation-database "$RESULTS_DIR"/combined_compilation_database.json &>"$RESULTS_DIR"/infer_capture.log

    if needs_capturing_retry "$RESULTS_DIR/combined_compilation_database.json" "$RESULTS_DIR/infer_capture.log"; then
      echo "Retrying capturing due to auto-fixed issues"
      continue # Run the capture command again with a modified DB
    fi

    break # We cannot make capturing better automatically
  done

}

# Get some stats, especially around coverage and failures
function print_infer_analysis_stats() {
  local -r RESULTS_DIR="$1"

  local COMPILE_COMMANDS=$(cat "$RESULTS_DIR"/combined_compilation_database.json | wc -l)
  # Take care of opening and closing bracket
  COMPILE_COMMANDS=$((COMPILE_COMMANDS - 2))

  local -r CLANG_ERROR_COUNT=$(grep "Error: the following clang command did not run successfull" -c "$RESULTS_DIR"/infer_capture.log)

  # grep " errors generated." "$RESULTS_DIR"/infer_capture.log | sort -u
  local -r CAPTURE_ERRORS=$(grep -c "Failed to execute compilation command:" "$RESULTS_DIR"/infer_capture.log)

  echo "Number of errors during capturing: $CLANG_ERROR_COUNT"
  echo "Failed to capture $CAPTURE_ERRORS files out of $COMPILE_COMMANDS (check $RESULTS_DIR/infer_capture.log for details)"
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

  infer_capture "$RESULTS_DIR" "$INFER_OUTPUT_DIR"

  # run analysis on combined output from "infer capture --continue" calls
  echo "Running infer analyze (storing output in "$RESULTS_DIR"/infer_analyze.log) ..."
  local -i INFER_ANALYSIS_STATUS=0
  infer analyze \
    --keep-going \
    -o "$INFER_OUTPUT_DIR" &>"$RESULTS_DIR"/infer_analyze.log || INFER_ANALYSIS_STATUS=$?

  # for now, only use what is enabled by default!
  #    --bufferoverrun \
  #    --cost \
  #    --pulse \
  #    --quandary \

  # Handle errors
  if [ "$INFER_ANALYSIS_STATUS" -ne 0 ]; then
    echo "There has been an error during analysis, please check: $RESULTS_DIR/infer_analyze.log"
  fi

  # Other, potentially relevant, parameter to infer analyze:
  #     --purity \
  #     --loop-hoisting \

  local -i STATUS=0

  if [ -r "$INFER_OUTPUT_DIR/report.json" ]; then
    # Turn the output of this JSON file into a gcc-style comments file
    cat "$INFER_OUTPUT_DIR"/report.json |
      python3 "$RESULTS_DIR"/transform_report.py >"$RESULTS_DIR"/gcc_style_report.txt

    # Show the gcc-style results
    cat "$RESULTS_DIR"/gcc_style_report.txt

  else
    echo "error: did not find report.json from Infer analysis"
    STATUS=1
  fi

  print_infer_analysis_stats "$RESULTS_DIR"
  [ -r "$RESULTS_DIR"/gcc_style_report.txt ] && echo "All infer findings are listed in $RESULTS_DIR/gcc_style_report.txt ($(cat "$RESULTS_DIR"/gcc_style_report.txt | wc -l) findings)"

  return $STATUS
}
