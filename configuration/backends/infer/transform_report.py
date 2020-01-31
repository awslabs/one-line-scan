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
# Script to turn infer output into gcc-style output

import json
import sys

# get JSON data from stdin
data=json.load(sys.stdin)

# only return relevant data, i.e. severity, type and qualifier (defect description)
u="unknown"
defect_list=["{}:{}: [{}] {} {}".format(d.get("file",""), d.get("line",0), d.get("severity",u), d.get("bug_type", u), d.get("qualifier","")) for d in data if d.get("severity",u) != "INFO"]

# remove duplicates, and sort the list, split items per line
gcc_style='\n'.join(sorted(list(set(defect_list))))

# print the list
print(gcc_style)
