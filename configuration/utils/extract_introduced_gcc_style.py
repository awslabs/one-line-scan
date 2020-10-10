#!/usr/bin/env python
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

from __future__ import print_function

import logging
import sys


# setup logger for this module
log = logging.getLogger(__name__)

def usage(toolname="extract_introduced_gcc_style.py"):
    print ("""usage: {} previous_msgs.txt current_msgs.txt

  This script prints lines from the second input file that are not present in the first input file.
  The files are assumed to be in gcc error style, i.e. when splitting each line into columns based
  on the colon symbol ':', the first column is the file name, the second column is the line number,
  and all remaining columns form the message. This script will ignore the line number for maching,
  and instead just compare number of occurrences of messages per file, i.e. the comparison is done
  on the remainder of the line.

  As a result, all full lines from the second input file are printed, whose pattern without the line
  information does not match the first input file often enough.

  previous_msgs.txt ... text file of the form 'filename:linenumber: ...' for older msgs/warnings/...
  current_msgs.txt .... text file of the form 'filename:linenumber: ...' for current msgs/warnings/...
""".format(toolname))


def drop_second_col(in_list):
    """ Drop line info, convert into list """
    ret = []
    log.debug("Drop second col from %r", in_list)
    for x in in_list:
        y = x.split(":")
        lineless = y[0:1] + y[2:]
        log.debug("Add lineless list: %r", lineless)
        ret.append(lineless)
    return ret


def main():

    logging.basicConfig(
        format="[%(levelname)-7s] %(asctime)s %(name)s %(message)s", level="WARNING",
    )

    # briefly check input
    if len(sys.argv) != 3:
        usage(sys.argv[0])
        sys.exit(0)

    # read files, fail early in case they cannot be found or opened
    oldf = open(sys.argv[1])
    newf = open(sys.argv[2])

    # get the actual msg output, assume style to be correct
    new_msgs = newf.readlines()
    log.info("parsed %d new info", len(new_msgs))
    old_msgs = oldf.readlines()
    log.info("parsed %d old info", len(old_msgs))

    # drop line in content
    new_lineless = drop_second_col(new_msgs)
    old_lineless = drop_second_col(old_msgs)
    log.info("new lineless: %d", len(new_lineless))
    log.info("old lineless: %d", len(old_lineless))

    # calculate actual introduced msgs (could be done quicker using e.g. sets)
    old_lineless_to_match = old_lineless[:]
    introduced_lineless = []
    for x in new_lineless:
        if x in old_lineless_to_match:
            old_lineless_to_match.remove(x)
        else:
            introduced_lineless.append(x)
    log.info(
        "introduced lineless: %d, left to match %d from %d",
        len(introduced_lineless),
        len(old_lineless_to_match),
        len(old_lineless),
    )

    # get all candidates from new msgs that match above info, collect for all available line info
    introduced_candidates = [
        x for x in new_msgs if (x.split(":")[0:1] + x.split(":")[2:]) in introduced_lineless
    ]
    log.debug("introduced full candidates: %r", introduced_candidates)

    # drop all candidates that appear in the old msgs with the same line number
    introduced = []
    old_msgs_to_match = old_msgs[:]
    for x in introduced_candidates:
        log.debug("Analyze %s", x)
        if x in old_msgs_to_match:
            old_msgs_to_match.remove(x)
        else:
            introduced.append(x.rstrip())
    log.debug("Left %d from %d messages to match", len(old_msgs_to_match), len(old_msgs))

    # present introduced msgs, each at most once
    for msg in sorted(set(introduced)):
        print (msg)

    # indicate error in case we spotted new defects
    return 0 if len(introduced) == 0 else 1


if __name__ == "__main__":
    # in case this module is the starting point, run the main function
    ret = main()
    log.debug("Exit main with %d", ret)
    sys.exit(ret)
