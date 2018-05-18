#!/usr/bin/env python
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
# Parse the report.html of Fortify and create an ASCII summary

import os
import sys
from subprocess import call
from xml.etree import ElementTree

# print usage
if len(sys.argv) != 2:
  print "usage summarizy-fortify.py LOGDIR"
  sys.exit(1)

# get directory where the logs are placed
logdir=sys.argv[1]

# strip this part of the directory information of
workdirectory = os.getcwd() + '/'

# get the fortify report; first make it valid XML
filename=logdir+'/log/report.html'
call(['perl', '-p', '-i', '-e', 's#<((img|meta) [^>]+)>#<$1/>#', filename])
# make sure we can run this script multiple times on the same html file
call(['perl', '-p', '-i', '-e', 's#//>#/>#', filename])

# parse the html file and jump to the last table
data=ElementTree.parse(filename).getroot()
table=data.find('.//table')[-1]

# iterate over all rows and print their content in a more useable format
for data in table.iter('tr'):
  # handle only the rows that contain results
  if len(data) != 4:
    continue
  # extract file information, convert absolute path into relative one
  location=data[2].find('a')
  # header does not have <a ...>
  if location is None:
    continue
  filename=location.get('href')
  filename=filename.replace('file://','')
  filename=filename.replace(workdirectory,'')
  severity=data[3].text
  if severity is None:
    severity=data[3].find('span').text
  # strip newline and space sequences
  problem=data[0].text.replace('\n','').replace('\r','')
  short=problem.replace('  ',' ')
  while len(short) < len(problem):
    problem=short
    short=problem.replace('  ',' ')
  column=ElementTree.tostring(data[2].findall("*")[0]).split(':')[2]
  printstring = filename + ':' + column.strip() + ', ' + \
    severity.strip() + ', ' + \
    problem
  if data[1].text is not None:
    printstring = printstring + ', ' + data[1].text
  print printstring
