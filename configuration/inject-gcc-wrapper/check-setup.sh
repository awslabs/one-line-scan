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
# Checks whether setting up the gcc wrapper would work
#
#
# Usage: check-setup.sh [OPTIONS]   ... to make the variables visible in the calling shell
#           OPTIONS ... options to be used for the test. They are forwarded to setup.sh
#

echo "test setting up the gcc-wrapper ..."
PREVIOUS=$(which gcc)

# use "original" setup script, and pass the parameter for the directory
SOURCE_DIR="$( dirname "${BASH_SOURCE[0]}" )"
source "$SOURCE_DIR"/setup.sh "$@"

AFTER=$(which gcc)

failed=1
if [ ! "$PREVIOUS" == "$AFTER" ] && [ -n "$AFTER" ]
then
  failed=0
  # in case of success, remove the wrapper again (keep directory)
  if [ -n "$SOURCE_DIR" ]
  then
    source "$SOURCE_DIR"/remove-wrapper.sh "--keep-dir"
  fi
fi
echo "Test failed: $failed"

exit $failed
