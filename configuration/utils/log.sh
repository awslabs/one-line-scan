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
# Provide the method for logging

log()
{
  echo "$*" | while IFS="" read -r line; do
  if [ -z "$TERM" ]; then
    echo "$(date -u "+%F %T%z" | sed 's/..$/:&/')$(tput setaf 6) $line$(tput sgr0)"
  else
    echo "$(date -u "+%F %T%z" | sed 's/..$/:&/') $line"
  fi
  done
}
