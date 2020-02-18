#!/usr/bin/env bash
#
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
# This scripts matches each line of a datafile with file and line info to the changes
# that have been introduced in a certain commit range, between upstream and branch.
# If no git IDs are specified, the full data file is printed (after sorting).
#
# USAGE: ./display-series-data.sh DATAFILE [UPSTREAMGITID [BRANCHGITID]]
#	 DATAFILE file with the data to display, of the format <file>:<line>:message
#        UPSTREAMGITID show coverity defects introduced since this ID,
#              if not specified show all found defects
#        BRANCHGITID show introduced coverity defects introduced since this ID,
#              if not specified, show all defects until the current commit
#

log() {
	echo "$@" 1>&2
}

error() {
	log "$@"
	exit 1
}

DATAFILE=
UPSTREAMGITID=
BRANCHGITID=HEAD

if [ -n "$*" ]; then
	DATAFILE="$1"
	shift
fi

if [ -n "$2" ]; then
    	# try to get a nice description of the upstream commit
	BRANCHGITID="$2"
	GIT_STATUS=0
	headid=$(git rev-parse $BRANCHGITID || GIT_STATUS=$?)
	if [ $GIT_STATUS -ne 0 ]; then
		error "error: cannot find $BRANCHGITID as reference in git history, abort."
	fi
	# try to find branch (some) pointer
	branches=$(git branch --contains $BRANCHGITID | grep -v " detached at ")
	for branch in $branches; do
		branchid=$(git rev-parse $branch)
		if [ $branchid = $headid ]; then
			BRANCHGITID="$branch"
			break
		fi
	done
fi

if [ -n "$1" ]; then
	UPSTREAMGITID="$1"
	GIT_STATUS=0
	git rev-list --count "$BRANCHGITID" ^$UPSTREAMGITID &> /dev/null || GIT_STATUS=$?
	if [ $GIT_STATUS -ne 0 ]; then
		error "error: cannot find $UPSTREAMGITID as reference in git history, abort."
	fi
	log "map defects to commits $UPSTREAMGITID to $BRANCHGITID"
fi

# have one directory where are temporary files go to
TMPDIR=$(mktemp -d --tmpdir=$TMPDIR display-series-data-XXXXXX)
trap 'rm -rf $TMPDIR' EXIT

SUMMARIZE_STATUS=0
# show partial results based on git blame, or full results
if [ -n "$UPSTREAMGITID" ]; then
	# get number of last commits to look at
	ANALYZE_LAST_COMMITS=$(git rev-list --count $BRANCHGITID ^$UPSTREAMGITID)

	CHANGED_FILES="$TMPDIR"/changed-files.txt
	CHANGED_LOCATIONS="$TMPDIR"/changed-locations.txt
	JOIN1="$TMPDIR"/join1.txt
	JOIN2="$TMPDIR"/join2.txt

	# check whether the referenced commits changed anything
	for commit in $(seq 0 $(($ANALYZE_LAST_COMMITS-1))); do
		git diff-tree --no-commit-id --name-only -r $BRANCHGITID~$commit > $CHANGED_FILES

		PAT=$(git rev-parse HEAD~$commit)
		cat $CHANGED_FILES | while IFS="" read -r filename; do
			# get all lines for current commit with line number, only print the filename
			# and line number
			git blame -l -s $filename 2> /dev/null | grep -n "^$PAT" 2> /dev/null | \
				awk -F : -v fn="$filename" '{if($1+0 > 0) print fn ":" $1 ","}' \
				2> /dev/null >> $CHANGED_LOCATIONS
		done
	done

	# sort all found locations, and match them against the locations of the findings
	cat $CHANGED_LOCATIONS | sort -k 1b,1 | uniq > $JOIN1
	awk -F: '{print $1 ":" $2}' "$DATAFILE" | sort -k 1b,1 | uniq > $JOIN2
	join $JOIN1 $JOIN2 > $CHANGED_LOCATIONS

	# display actually found problems
	NUM_HIT_LINES=$(cat $CHANGED_LOCATIONS | wc -l)
	log "found items introduced during last $ANALYZE_LAST_COMMITS ($UPSTREAMGITID to $BRANCHGITID) commits: $NUM_HIT_LINES"

	# set status back to 0, if no defects have been introduced in this series
	[ $NUM_HIT_LINES -gt 0 ] || SUMMARIZE_STATUS=0

	rm $JOIN2
	cat $CHANGED_LOCATIONS | while IFS="" read -r location; do
		grep "^${location}:" "$DATAFILE" >> $JOIN2
	done
	[ -f $JOIN2 ] && sort $JOIN2 | uniq
else
	sort "$DATAFILE"
fi

# clean up and exit
exit $SUMMARIZE_STATUS
