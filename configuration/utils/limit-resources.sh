#!/bin/bash
#
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
# Calculate the amount of resources that are allowed to be use be a script
# Use ulimit to enforce these limits
#
# This script should be sourced by other scripts


# check the available memory, and return 40% is large enough, otherwise return
# almost the full amount (leave 256M is possible)
# returns the number in K
usable_memory()
{
 grep -e "^MemAvailable:" -e "^MemTotal:" /proc/meminfo \
   | sort -V | head -n 1 \
   | awk 'BEGIN {
            freemem=0; M=1024; G=1024 * 1024
            OFMT = "%.0f"
          }
          {
            if ( $2 + 0 >= 0 ) freemem=$2;
          }
          END {
                if( freemem  > 10 * G ) {
                  freemem = (freemem * 2) / 5;
                } else {
                  if (freemem > (512 * M)) freemem = freemem - (256 * M)
                }
                print freemem;
              }
         '
}

# return the available memory in M
usable_memory_in_M()
{
  usableMemory=$(usable_memory)
  echo "$(($usableMemory/1024))"
}

# make this a function, so that variables are local
limit_memory()
{
  # get available memory, if more then 3GB, use 75%, otherwise, use all
  # and leave 256M if possible, if we can have 256 as well
  local usableMemory=$(usable_memory)
  # if we obtained a value, assign the limitation to avoid freezing the machine
  if [ -n "$usableMemory" ] && [ $usableMemory -ne 0 ]
  then
    ulimit -S -v $usableMemory
  fi
}
