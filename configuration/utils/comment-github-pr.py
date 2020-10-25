#!/usr/bin/env python3
#
# This script will post comments on a github PR based on gcc style reports
# provided as an input text file.

__authors__ = "Norbert Manthey <nmanthey@amazon.de>"
__copyright__ = "Copyright 2020 Amazon.com, Inc. or its affiliates. " "All rights reserved."

import json
import logging
import os
import sys

from argparse import ArgumentParser
from github import Github

# Get logger for this module
log = logging.getLogger(__name__)


def parse_cli():
    """Parse CLI and return parsed parameters"""

    parser = ArgumentParser()

    parser.add_argument(
        "-r",
        "--report-file",
        help="GCC Style Report which should be used to create a PR comment (format: file:line:<message>)",
        default=None,
        required=True,
    )

    parser.add_argument(
        "-s",
        "--summary",
        help="Only comment a summary of the report",
        default=False,
        action="store_true",
    )

    # Parse parameters
    args = vars(parser.parse_args())
    log.debug("Received arguments %r", args)

    return args


def markdownify_gcc_report(report_file, summary=False):
    """This method assumes this script is invoked in a github workflow"""

    try:
        with open(report_file) as report:
            findings = report.readlines()
    except Exception as e:
        log.error("Failed to load report from %s, failed with %e", report_file, e)

    nr_findings = len(findings)
    files = set([x.split(":")[0] for x in findings])

    # Write a basic summary of the findings
    markdown_message = "One Line Scan: **reported {} findings** in {} files".format(
        nr_findings, len(files)
    )

    # Add task list with all findings
    if not summary:
        markdown_message += "\n\n"
        for finding in findings:
            markdown_message += "- [ ] {}\n".format(finding.rstrip())
        markdown_message += "\n\n"

    return markdown_message, 0


def comment_on_github_pr(message):
    """Comment on a PR. (assumes the script is invoked in a github workflow)"""

    # Check whether called via workflow
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        log.error("Did not find GITHUB_TOKEN environment variable, abort")
        return 1

    github_handle = Github(token)
    # Enable to see API
    # log.info("github handle: %r", dir(github_handle))

    # Check the current event
    event_file = os.getenv("GITHUB_EVENT_PATH")
    event = None
    try:
        with open(event_file) as f:
            event = json.load(f)
    except Exception as e:
        log.error("Failed to load event from file %s, failed with %r", event_file, e)
    log.debug("Obtained event: %s", json.dumps(event, indent=4))

    if not event:
        log.error("Did not find an even file, abort.")
        return 1

    # Get repository for current event
    # https://pygithub.readthedocs.io/en/latest/github_objects/Repository.html
    repo_name = event["repository"]["full_name"]
    repo = github_handle.get_repo(repo_name)

    # Get pull request object for current event
    # https://pygithub.readthedocs.io/en/latest/github_objects/PullRequest.html
    pull_request_number = event["pull_request"]["number"]
    pull_request = repo.get_pull(int(pull_request_number))
    # Enable to see API
    # log.info("pull request: %r", dir(pull_request))

    # Create and post message to comment stream
    pull_request.create_issue_comment(message)


def main():

    args = parse_cli()

    markdown_message, ret = markdownify_gcc_report(args["report_file"], args["summary"])
    log.info("Message to be posted: \n===\n%s===\n", markdown_message)

    if ret == 0:
        ret = comment_on_github_pr(markdown_message)

    return ret


if __name__ == "__main__":

    logging.basicConfig(
        format="[%(levelname)-7s] %(asctime)s %(name)s {%(pathname)s:%(lineno)d} %(message)s",
        level="INFO",
    )

    # In case this module is the starting point, execute the command
    ret = main()
    log.debug("Exit main with %d", ret)
    sys.exit(ret)
