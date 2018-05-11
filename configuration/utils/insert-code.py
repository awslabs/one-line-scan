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

import fileinput
import sys

print len(sys.argv)
print sys.argv

if ( len(sys.argv) < 2 ):
    print "usage: insert-code.py [--comment] code-file"
    print "   --comment  will add each statement as a commend (with prefix '//')"
    print "   code-file  text file of the form filename:linenumber:statement for each line"
    sys.exit(0)

comment=0
if (sys.argv[1] == "--comment" ):
    comment=1

if (len(sys.argv) < 3 ):
    print "error: no code file specified, abort"
    sys.exit(1)

statements = []
with open(sys.argv[1+comment], 'r') as outfile:
    statements = outfile.readlines()

files = {}

for line in statements:
    tokens = line.split(':')
    if( len(tokens) < 3 ):
      continue

    filename = tokens[0]
    lineno = int(tokens[1])
    statement_begin = line.replace(':',' ',1).find(':')+1
    statement = line[statement_begin:]
    # add the element in the set, if there has been a list before
    if filename not in files:
        files[filename] = []
    # append the current line to the set of files
    files[filename].append( (lineno, statement) )

for filename in files:
    print "workon " + filename
    # sort the statements to be inserted, so that we can process the file
    # linearly
    statementlist = sorted(files[filename] )

    # keep track of statements and where to put them
    nextStatement = 0
    nextStatementLineno = statementlist[ nextStatement ][0]
    lastPrinted = 0
    # open the file and add the lines
    for line in fileinput.input(filename, inplace=1):
      # currentLine = currentLine + 1
      # if we still have statements to insert
      if ( nextStatement != -1 ):
        # check whether we should do so on the current line
        while ( nextStatementLineno == fileinput.lineno() ):
          spacePrefix = len(line) - len(line.lstrip()) - 1
          if( lastPrinted != nextStatementLineno ):
            print ""
          if ( comment == 1 ):
            print "//",
          print line[0:spacePrefix],
          print statementlist[ nextStatement ][1],
          # check if there is a next statement
          if ( nextStatement + 1 >= len(statementlist)):
            nextStatement = -1
            break
          else:
            # select next statement and memorize its line number
            nextStatement = nextStatement + 1
            lastPrinted = nextStatementLineno
            nextStatementLineno = statementlist[ nextStatement ][0]
      # finally, print the line of code
      print line,
