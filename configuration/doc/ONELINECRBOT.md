The basic functionality of the one line cr bot is described in the [doc/README.md](https://github.com/awslabs/one-line-scan/blob/master/configuration/doc/README.md)
file. Examples to use the file are given in the [doc/EXAMPLES.md](https://github.com/awslabs/one-line-scan/blob/master/configuration/doc/EXAMPLES.md) file. This file
highlights using one-line-cr-bot.sh as part of CI systems.

# Workflows

There are workflows that allow to automate analysis, and also block. The below
YAML file can be used as an example to start implementing code analysis for your
C and C++ projects using github workflows.

## Github Workflows

Github workflows are activated by placing a YAML file in the .github/workflows
directory. By placing the below file into that directory, i.e. storing the full
below content in the file .github/workflows/one-line-cr-bot.yml any future pull
request will receive code analysis.

The file has sections labeled "[ACTION REQUIRED]" which likely need to be
adapted to meet the configuration of your project.

In case the analysis creates many false positive alarms for your project,
consider to pass the parameter '-y' to the one-line-cr-bot.sh call. This will
still run the analysis, but will not fail in case of errors. When doing so,
spotting new defects becomes a more manual process, but will not block your pull
requests unnecessarily.

    # Author: Norbert Manthey <nmanthey@amazon.de>
    #
    # This workflow will present introduced defects of a pull request to a given
    # branch of a package.
    #
    # The workflow has locations labeled '[ACTION REQUIRED]' where adaptation for
    # your build might be required, as well as where to compare the findings to.
    #
    # To learn more about the available options, check the CLI parameters of the
    # script 'one-line-cr-bot.sh' in https://github.com/awslabs/one-line-scan.git
    name: One Line CR Bot

    on:
    pull_request:
        # [ACTION REQUIRED] Set the branch you want to analyze PRs for
        branches: [ mainline ]

    # [ACTION REQUIRED] Use this, if you want analysis for push to repository as well
    push:
        branches: [ mainline ]

    jobs:
    build:

        runs-on: ubuntu-latest

        # Get the code, fetch the full history to make sure we have the compare commit as well
        steps:
        - uses: actions/checkout@v2
        with:
            fetch-depth: 0

        # one-line-cr-bot.sh will get infer and cppcheck, if not available
        - name: Install CppCheck Package
        env:
            # This is needed in addition to -yq to prevent apt-get from asking for user input
            DEBIAN_FRONTEND: noninteractive
        # [ACTION REQUIRED] Add your build dependencies here, drop cppcheck to get latest cppcheck
        run: |
            sudo apt-get install -y cppcheck

        # Get the reference remote
        - name: Setup Reference Commit Remote
        # [ACTION REQUIRED] Add the https URL of your repository
        run: git remote add reference https://github.com/awslabs/ktf.git
        - name: Fetch Reference Commit Remote
        run: git fetch reference

        # Get one-line-scan, the tool we will use for analysis
        - name: Get OneLineScan
        run:  git clone -b one-line-cr-bot https://github.com/awslabs/one-line-scan.git ../one-line-scan

        # Check how repository is setup
        - name: Be Verbose about Git Setup
        run: |
            git remote -v
            git branch -a
            git log --pretty=oneline --decorate --graph | head -n 10

        # Run the analysis, parameterized for this package
        - name: one-line-cr-analysis
        env:
            # [ACTION REQUIRED] Adapt the values below accordingly
            # 'reference' is the name of the remote to use
            BASE_COMMIT: "reference/mainline"
            BUILD_COMMAND: "make -B all"
            CLEAN_COMMAND: "make clean"
            # Parameters to be forwarded to used tools in one-line-scan for customization
            # Additional CppCheck parameters, do not use e.g. --inconclusive
            CPPCHECK_EXTRA_ARG: "--enable=style --enable=performance --enable=information --enable=portability"
            # Additional Infer parameters, do not use e.g. --pulse
            INFER_ANALYSIS_EXTRA_ARGS: "--bufferoverrun"
            # These settings are more preferences, and not directly related to your project
            # Set INSTALL_MISSING to false, if ALL targetted tools are already present
            INSTALL_MISSING: true
            OVERRIDE_ANALYSIS_ERROR: true
            REPORT_NEW_ONLY: true
            VERBOSE: 0 # >0 shows all currently present defects as well
        # Be explicit about the tools to be used
        run: ../one-line-scan/one-line-cr-bot.sh -E infer -E cppcheck

Configurations similar to the above are already used in github projects, e.g. [KTF](https://github.com/awslabs/ktf/blob/mainline/.github/workflows/one-line-cr-bot.yml).