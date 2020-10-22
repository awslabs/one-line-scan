#!/bin/bash
#
# Copyright (C) 2020 Amazon.com, Inc. or its affiliates.
# Author: Norbert Manthey <nmanthey@amazon.de>
#
# Script to report errors/warnings/static code analysis output for a git commit series
#
# Tools currently used: infer, cppcheck
# To potentially add: gcc-10 fanalyzer, cbmc
#
# If cppcheck or infer are not present in PATH, the tools can be obtained, and
# build from their respective source in the www, all in a temporary folder that
# will be thrown away after the invocation. If you plan to use this script
# multiple time, consider installing these tools natively! To use this feature,
# use the flag -I, or assign the value "true" to the environment variable
# INSTALL_MISSING. Note, installation from the www might fail due to
# unavailability.
#
# To customize the analysis of the used tools, check the documentation for the
# backends of the one-line-scan tool. Configuration via environment variables is
# possible.

# Variables that can be influenced via environment, or CLI
BASE_COMMIT="${BASE_COMMIT:-}"
BUILD_COMMAND="${BUILD_COMMAND:-make -B}"
CLEAN_COMMAND="${CLEAN_COMMAND:-make clean}"
DEBUG="${DEBUG:-}"
INFER_VERSION="${INFER_VERSION:-1.0.0}" # currently, we only support v1.0.0
INGORE_ERRORS="${INGORE_ERRORS:-false}"
INSTALL_MISSING="${INSTALL_MISSING:-false}"
ONELINESCAN_PARAMS="${ONELINESCAN_PARAMS:-}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
OVERRIDE_ANALYSIS_ERROR="${OVERRIDE_ANALYSIS_ERROR:-false}"
REPORT_NEW_ONLY="${REPORT_NEW_ONLY:-false}"
WORK_COMMIT="${WORK_COMMIT:-}"
declare -i VERBOSE
VERBOSE=${VERBOSE:-0}

# Track tools to be run
declare -a SUPPORTED_TOOLS=("infer" "cppcheck")
declare -A RUN_TOOL
RUN_TOOL["INFER"]="true"
RUN_TOOL["CPPCHECK"]="true"

#
# DO NOT TOUCH THE BELOW
#
readonly PROG=$(basename "$0")
readonly SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
readonly REPOSITORY_DIR=${PWD}

TMP_DATA_FOLDER=""

usage() {
    cat <<EOF
One-Line-CR Bot

This script allows to run code analysis based on One-Line-Scan against a given
code base. Using these results, the user can choose to print the diff in defects
in comparison to those found for a base commit. The commands to be used, as well
as the commits to be used for comparison, can be specified via environment or
CLI parameters, where CLI will override the environment.

Tools currently used: ${SUPPORTED_TOOLS[*]}

If cppcheck or infer are not present in PATH, the tools can be obtained, and
built from their respective source in the www, all in a temporary folder that
will be thrown away after the invocation. If you plan to use this script
multiple times, consider installing these tools natively! To use this feature,
use the flag -I, or assign the value "true" to the environment variable
INSTALL_MISSING. Note, installation from the www might fail due to
unavailability.

To customize the analysis options of the tools used, check the documentation for
the backends of the one-line-scan tool. Configuration via environment variables
is possible.

Some parameters can be set via environment variables. Those are named next to
the default value for certain CLI parameters.

  Usage:
    $0 [options]

  Options:

  -b cmd ...... command used for building the project
                (default: "$BUILD_COMMAND", env: BUILD_COMMAND)
  -c cmd ...... command used for cleaning up the project
                (default: "$CLEAN_COMMAND", env: CLEAN_COMMAND)

  -B commit ... base commit to compare findings to
                (default: "$BASE_COMMIT", env: BASE_COMMIT)
  -W commit ... work commit to be used for current defect analysis
                (default: "$WORK_COMMIT", env: WORK_COMMIT)

  Enable tools, supported: ${SUPPORTED_TOOLS[*]}
  -E TOOL ..... enable analysis with tool TOOL
  -D TOOL ..... disable analysis with tool TOOL

  -f .......... ignore errors during analysis of 1 commit
                (default: $OVERRIDE_ANALYSIS_ERROR, env: OVERRIDE_ANALYSIS_ERROR)
  -n .......... report only new findings, ignore moved lines
                (default: $REPORT_NEW_ONLY, env: REPORT_NEW_ONLY)
  -O args ..... extra command line options for one-line-scan invocations
                (default: $ONELINESCAN_PARAMS, env: ONELINESCAN_PARAMS)
  -y .......... ignore analysis errors
                (default: $INGORE_ERRORS, env: INGORE_ERRORS)

  -h .......... print this help message
  -I .......... Try to install missing tools, if they cannot be found.
                (default: $INSTALL_MISSING, env INSTALL_MISSING)
  -d .......... print more information about the analysis invocation
                (default: $DEBUG, env: DEBUG)
  -o file ..... Text file where the introduced defects will be written to in gcc
                error style.
                (default: $OUTPUT_FILE, env: OUTPUT_FILE)
  -v .......... be more verbose
                (default: $VERBOSE, env: VERBOSE)
EOF
}

cleanup_handler() {
    local _PROG="$0"
    local ERR="$1"
    if [ "$ERR" != 0 ]; then
        echo "$_PROG: cleanup_handler() invoked, exit status $ERR" 1>&2

        # Print collected error output in case we failed
        echo "Full stderr:"
        [ -d "$TMP_DATA_FOLDER" ] && cat "$TMP_DATA_FOLDER"/stderr.log 2>/dev/null | awk '{print "stderr.log:" $0}'
    fi

    [ -d "$TMP_DATA_FOLDER" ] && rm -rf "$TMP_DATA_FOLDER"

    # Try to get back to the initial commit as before (might result in head-less
    # state). This is to not confuse interactive users of this script.
    if [ -n "$WORK_COMMIT" ] && [ -n "$BASE_COMMIT" ]; then
        pushd "$REPOSITORY_DIR" 1>&2
        git checkout "$WORK_COMMIT" &>/dev/null
        git submodule update --init --recursive &>/dev/null
        popd 1>&2
    fi

    return "$ERR"
}

error_handler() {
    local _PROG="$0"
    local LINE="$1"
    local ERR="$2"
    if [ "$ERR" != 0 ]; then
        echo "$_PROG: error_handler() invoked, line $LINE, exit status $ERR" 1>&2
    fi

    exit "$ERR"
}

trap 'error_handler ${LINENO} $?' ERR
trap 'cleanup_handler $?' EXIT

check_environment() {
    local -i ret=0
    # Print the version output of the available tools
    echo "Versions of used tools:" 1>&2
    for tool in "${SUPPORTED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null && [ "${RUN_TOOL["${tool^^}"]}" == "true" ]; then
            echo "Error: Failed to find tool $tool, which has been activated. Abort" 1>&2
            ret=1
        else
            $tool --version 1>&2 || true
        fi
    done

    return $ret
}

setup_infer() {

    local INSTALL_DIR="$1"
    pushd "$INSTALL_DIR" 1>&2

    echo "Setting up Infer..." 1>&2

    # prepare for checking downloaded tar ball (taken from release web page)
    echo "510eeccc7e6bcc2678ac92a88f8e1cb9c07c3e14d272dcc06834e93845bb120f  infer-linux64-v1.0.0.tar.xz" >infer-linux64-v1.0.0.tar.xz.sha256

    # get infer with specified version, check and install
    local -i ret=0
    curl -sSL "https://github.com/facebook/infer/releases/download/v${INFER_VERSION}/infer-linux64-v${INFER_VERSION}.tar.xz" \
        --output "infer-linux64-v${INFER_VERSION}.tar.xz" || ret=$?

    # fail in case the download failed
    if [ "$ret" -ne 0 ]; then
        popd 1>&2
        return 1
    fi

    # check obtained artefact, extract and make available in PATH
    if ! shasum --status --algorithm 256 --check infer-linux64-v1.0.0.tar.xz.sha256; then
        echo "Error: checksum of obtained infer version does not match"
        popd 1>&2
        return 1
    fi

    tar -xJf "infer-linux64-v${INFER_VERSION}.tar.xz" || ret=$?
    export PATH=$PATH:"$(pwd)/infer-linux64-v${INFER_VERSION}/bin"

    popd 1>&2

    return "$ret"
}

setup_cppcheck() {

    local -i ret=0
    local INSTALL_DIR="$1"
    pushd "$INSTALL_DIR" 1>&2

    echo "Setting up CppCheck..." 1>&2

    CPPCHECK_VERSION="2.2"

    # prepare for checking downloaded tar ball (taken from release web page)
    echo "11bdc2f82269cf74f9882719f761cde79443a928  cppcheck-2.2.tar.gz" >cppcheck-2.2.tar.gz.sha256

    # get infer with specified version, check and install
    local -i ret=0
    curl -sSL "https://github.com/danmar/cppcheck/archive/${CPPCHECK_VERSION}.tar.gz" \
        --output "cppcheck-${CPPCHECK_VERSION}.tar.gz" || ret=$?

    # fail in case the download failed
    if [ "$ret" -ne 0 ]; then
        popd 1>&2
        return 1
    fi

    # check obtained artefact, extract and make available in PATH
    if ! shasum --status --algorithm 256 --check cppcheck-2.2.tar.gz.sha256; then
        echo "Error: checksum of obtained cppcheck version does not match"
        popd 1>&2
        return 1
    fi

    # extract cppcheck and build it, point to it's cfg directory for configuration
    tar -xzf "cppcheck-${CPPCHECK_VERSION}.tar.gz" || ret=$?
    cd cppcheck-"${CPPCHECK_VERSION}"
    make MATCHCOMPILER=yes FILESDIR=$(pwd) HAVE_RULES=yes -j "$(nproc)" &>build_cppcheck.log || ret=$?
    # for f in $(ls cfg/*.cfg); do ln -s $f; done

    export PATH=$PATH:"$(pwd)"

    popd 1>&2

    return "$ret"
}

setup_onelinescan() {
    # use one-line-scan, which is also in our directory
    export PATH="$SCRIPT_DIR":$PATH

    command -v one-line-scan &>/dev/null || return 1
    return 0
}

setup_environment() {
    TMP_DATA_FOLDER="$(mktemp -d)"

    if [ -z "$TMP_DATA_FOLDER" ]; then
        echo "Error: failed to setup temporary directory, abort"
        exit 1
    fi

    # In case no output file was specified, create one
    [ -z "$OUTPUT_FILE" ] && OUTPUT_FILE="$TMP_DATA_FOLDER"/introduced-defects.txt

    # Forward error output into stderr.log file, and do not print it unless we
    # fail execution.
    [ "$DEBUG" != "true" ] && exec 2>>"$TMP_DATA_FOLDER"/stderr.log

    # Install tools, in case they are not present already
    if [ "$INSTALL_MISSING" == "true" ]; then
        if ! command -v infer &>/dev/null; then
            setup_infer "$TMP_DATA_FOLDER" || return $?
        fi

        if ! command -v cppcheck &>/dev/null; then
            setup_cppcheck "$TMP_DATA_FOLDER" || return $?
        fi
    fi

    return 0
}

check_plain_build() {
    # only show output of failed build
    if ! $BUILD_COMMAND &>"$TMP_DATA_FOLDER"/plain_build.log; then
        echo "Error: failed to build, log:"
        cat "$TMP_DATA_FOLDER"/plain_build.log
        return 1
    fi

    if ! $CLEAN_COMMAND &>"$TMP_DATA_FOLDER"/plain_clean.log; then
        echo "Error: failed to clean, log:"
        cat "$TMP_DATA_FOLDER"/plain_clean.log
        return 2
    fi
    return 0
}

infer_analysis_findings() {
    rm -rf "$TMP_DATA_FOLDER"/infer_files
    local -i INFER_STATUS=0
    one-line-scan -o "$TMP_DATA_FOLDER"/infer_files --trunc-existing --no-gotocc --infer $ONELINESCAN_PARAMS -- $BUILD_COMMAND &>"$TMP_DATA_FOLDER"/infer.log || INFER_STATUS=$?
    cat "$TMP_DATA_FOLDER"/infer_files/infer/gcc_style_report.txt 2>/dev/null >>"$TMP_DATA_FOLDER"/findings.txt
    $CLEAN_COMMAND &>/dev/null
    return $INFER_STATUS
}

cppcheck_analysis_findings() {
    rm -rf "$TMP_DATA_FOLDER"/cppcheck_files
    local -i CPPCHECK_STATUS=0
    one-line-scan -o "$TMP_DATA_FOLDER"/cppcheck_files --trunc-existing --no-gotocc --cppcheck $ONELINESCAN_PARAMS -- $BUILD_COMMAND &>"$TMP_DATA_FOLDER"/cppcheck.log || CPPCHECK_STATUS=$?
    # forward findings, reduce noise for known noisy checkers
    cat "$TMP_DATA_FOLDER"/cppcheck_files/cppcheck/results/* 2>/dev/null |
        grep -v "^::" |
        grep -v " (error:shiftTooManyBits) " |
        grep -v " (error:integerOverflow) " |
        sed "s:${PWD}/::g" \
            >>"$TMP_DATA_FOLDER"/findings.txt
    [ "$DEBUG" == "true" ] && cat "$TMP_DATA_FOLDER"/cppcheck_files/cppcheck/results/* | grep "^::" 1>&2 # present extra failures
    $CLEAN_COMMAND &>/dev/null
    return $CPPCHECK_STATUS
}

show_findings_for_series() {
    [ ! -r "$TMP_DATA_FOLDER"/findings.txt ] && return 0
    sort -u -V "$TMP_DATA_FOLDER"/findings.txt >"$TMP_DATA_FOLDER"/sorted-findings.txt 2>/dev/null

    "$TMP_DATA_FOLDER"/one-line-scan/configuration/utils/display-series-data.sh "$TMP_DATA_FOLDER"/sorted-findings.txt "$BASE_COMMIT"
}

# analyze a project for a given commit
analyze_project_commit() {
    local COMMIT="${1:-}"

    # handle slashes in commits properly
    local COMMIT_FNAME=${COMMIT//\//_}

    # if there is a commit to work with, look into this commit
    if [ -n "$COMMIT" ]; then
        git checkout "$COMMIT" &>/dev/null || exit $?
        git submodule update --init --recursive &>/dev/null
    fi

    local -i BUILD_STATUS=0
    check_plain_build || BUILD_STATUS=$?
    if [ "$BUILD_STATUS" -ne 0 ]; then
        echo "Failed to build and clean project, received exit code: $BUILD_STATUS" 1>&2
        return $BUILD_STATUS
    fi

    local -i INFER_STATUS=0
    if [ "${RUN_TOOL["INFER"]}" == "true" ]; then
        infer_analysis_findings || INFER_STATUS=$?
    else
        echo "Configured to not run Infer" 1>&2
    fi

    local -i CPPCHECK_STATUS=0
    if [ "${RUN_TOOL["CPPCHECK"]}" == "true" ]; then
        cppcheck_analysis_findings || CPPCHECK_STATUS=$?
    else
        echo "Configured to not run CppCheck" 1>&2
    fi

    if [ "$INFER_STATUS" -ne 0 ]; then
        echo "Failed infer analysis (on $COMMIT), received exit code: $INFER_STATUS" 1>&2
        if [ "$DEBUG" == "true" ]; then
            echo "Infer: output of failure" 1>&2
            cat "$TMP_DATA_FOLDER"/infer.log 1>&2
        fi
    fi

    if [ "$CPPCHECK_STATUS" -ne 0 ]; then
        echo "Failed CppCheck analysis (on $COMMIT, might mean defects have been spotted), received exit code: $CPPCHECK_STATUS" 1>&2
        if [ "$DEBUG" == "true" ]; then
            echo "CppCheck: output of failure" 1>&2
            cat "$TMP_DATA_FOLDER"/cppcheck.log 1>&2
        fi
    fi

    # store findings for the current commit
    touch "$TMP_DATA_FOLDER"/findings.txt
    sort -u -V "$TMP_DATA_FOLDER"/findings.txt >"$TMP_DATA_FOLDER"/sorted-findings-"$COMMIT_FNAME".txt
    mv "$TMP_DATA_FOLDER"/findings.txt "$TMP_DATA_FOLDER"/findings-"$COMMIT_FNAME".txt 2>/dev/null

    mv "$TMP_DATA_FOLDER"/cppcheck_files "$TMP_DATA_FOLDER"/cppcheck_files-"$COMMIT_FNAME" 2>/dev/null
    mv "$TMP_DATA_FOLDER"/infer_files "$TMP_DATA_FOLDER"/infer_files-"$COMMIT_FNAME" 2>/dev/null

    [ "$INFER_STATUS" -ne 0 ] && return 1
    [ "$CPPCHECK_STATUS" -ne 0 ] && return 1
    return 0
}

# Use current commit as work commit, if no other commit is specified
if [ -z "$WORK_COMMIT" ]; then
    # Try to use a symbolic name, fall back to plain commit ID
    WORK_COMMIT=$(git rev-parse --symbolic-full-name HEAD | sed 's:^refs/heads/::g')
    [ -z "$WORK_COMMIT" -o "$WORK_COMMIT" == "HEAD" ] && WORK_COMMIT=$(git rev-parse HEAD)
fi

while getopts "0b:B:c:dD:E:fhIno:O:vW:y" opt; do
    case $opt in
    b)
        BUILD_COMMAND="$OPTARG"
        ;;
    B)
        BASE_COMMIT="$OPTARG"
        ;;
    c)
        CLEAN_COMMAND="$OPTARG"
        ;;
    d)
        DEBUG="true"
        ;;
    D)
        if [[ ! " ${SUPPORTED_TOOLS[*]^^} " =~ " ${OPTARG^^} " ]]; then
            echo "Error: unknown tool to disable ${OPTARG} (supported: ${SUPPORTED_TOOLS[*]})"
            exit 1
        fi
        RUN_TOOL["${OPTARG^^}"]="false"
        ;;
    E)
        if [[ ! " ${SUPPORTED_TOOLS[*]^^} " =~ " ${OPTARG^^} " ]]; then
            echo "Error: unknown tool to enable ${OPTARG} (supported: ${SUPPORTED_TOOLS[*]})"
            exit 1
        fi
        RUN_TOOL["${OPTARG^^}"]="true"
        ;;
    f)
        OVERRIDE_ANALYSIS_ERROR="true"
        ;;
    I)
        INSTALL_MISSING="true"
        ;;
    n)
        REPORT_NEW_ONLY="true"
        ;;
    h)
        usage
        exit 0
        ;;
    o)
        OUTPUT_FILE="$OPTARG"
        ;;
    O)
        ONELINESCAN_PARAMS="$OPTARG"
        ;;
    W)
        WORK_COMMIT="$OPTARG"
        ;;
    v)
        VERBOSE=$((VERBOSE + 1))
        ;;
    y)
        INGORE_ERRORS="true"
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
        echo ""
        usage
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

if [ "$DEBUG" == "true" ]; then
    echo "Tool Environment:" 1>&2
    env | sort -V 1>&2
fi

setup_environment 1>&2 || exit 1
setup_onelinescan 1>&2 || exit 2
check_environment 1>&2 || exit 3

# make sure we handle slashes in commit names for files
BASE_COMMIT_FNAME=${BASE_COMMIT//\//_}
WORK_COMMIT_FNAME=${WORK_COMMIT//\//_}

# analyze series, if presented, or just analyze current state
declare -i DEFECT_STATUS=0
declare -i OVERALL_STATUS=0
if [ -n "$BASE_COMMIT" ]; then
    echo "Run diff analysis with given base commit $BASE_COMMIT ($(git rev-parse "$BASE_COMMIT"))"
    if [ "$(git rev-parse "$BASE_COMMIT")" == "$(git rev-parse "$WORK_COMMIT")" ]; then
        echo "Reject diff analysis, due to using same commit."
    else
        analyze_project_commit "$BASE_COMMIT" || OVERALL_STATUS=$?
        analyze_project_commit "$WORK_COMMIT" || OVERALL_STATUS=$?

        BASE_FINDINGS=$(cat "$TMP_DATA_FOLDER"/sorted-findings-"$BASE_COMMIT_FNAME".txt | sort -u | wc -l)
        TIP_FINDINGS=$(cat "$TMP_DATA_FOLDER"/sorted-findings-"$WORK_COMMIT_FNAME".txt | sort -u | wc -l)
        echo "Spotted $BASE_FINDINGS findings for base, and $TIP_FINDINGS for current commit"

        if [ -r "$TMP_DATA_FOLDER"/sorted-findings-"$BASE_COMMIT_FNAME".txt ] &&
            [ -r "$TMP_DATA_FOLDER"/sorted-findings-"$BASE_COMMIT_FNAME".txt ]; then
            echo -e "\n\nAll findings worth reporting as introduced:"
            if [ "$REPORT_NEW_ONLY" == "true" ]; then
                "$SCRIPT_DIR"/configuration/utils/extract_introduced_gcc_style.py \
                    "$TMP_DATA_FOLDER"/sorted-findings-"$BASE_COMMIT_FNAME".txt \
                    "$TMP_DATA_FOLDER"/sorted-findings-"$WORK_COMMIT_FNAME".txt | tee -a "$OUTPUT_FILE"
                DEFECT_STATUS="${PIPESTATUS[0]}"
            else
                diff --new-line-format="" --unchanged-line-format="" \
                    "$TMP_DATA_FOLDER"/sorted-findings-"$WORK_COMMIT_FNAME".txt \
                    "$TMP_DATA_FOLDER"/sorted-findings-"$BASE_COMMIT_FNAME".txt | tee -a "$OUTPUT_FILE"
                DEFECT_STATUS="${PIPESTATUS[0]}"
            fi
            echo -e "\n\n"

            [ "$DEFECT_STATUS" -eq 0 ] && echo "Did not detect relevant findings"
            [ "$OVERRIDE_ANALYSIS_ERROR" == "true" ] && OVERALL_STATUS=0
        else
            echo "Error: Did not find comparison files for both commits, abort"
            OVERALL_STATUS=1
        fi

        if [ "$VERBOSE" -gt 0 ]; then
            SHOW_WORK_COMMIT=$(git rev-parse $WORK_COMMIT)
            [ "$SHOW_WORK_COMMIT" != "$WORK_COMMIT" ] && SHOW_WORK_COMMIT="$WORK_COMMIT ($SHOW_WORK_COMMIT)"
            echo -e "\n\nAll findings in current work commit ($SHOW_WORK_COMMIT):"
            sort -uV "$TMP_DATA_FOLDER"/sorted-findings-"$WORK_COMMIT_FNAME".txt
            echo -e "\n\n"
        fi
    fi
else
    echo "Did not spot a base commit, run plain analysis ..."
    TARGET_COMMIT=""
    analyze_project_commit "$TARGET_COMMIT" || DEFECT_STATUS=$?
    cat "$TMP_DATA_FOLDER"/sorted-findings-"$TARGET_COMMIT".txt
fi

# ignore errors, if requested
[ "$INGORE_ERRORS" == "true" ] && exit 0

# All steps we ran worked, signal success
if [ "$DEFECT_STATUS" -eq 0 ]; then
    exit $OVERALL_STATUS
fi
exit $DEFECT_STATUS
