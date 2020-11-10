#!/bin/bash
# test building with injected extra options


# the usual compilation should not fail
rm -rf SP
../../../one-line-scan -o SP --stop-after-fail --no-analysis --plain -- gcc -Wextra fail.c || exit 1

# when using an additional -Werror, the compilation should fail
rm -rf SP
../../../one-line-scan -o SP --extra-cflags -Werror --no-analysis --plain -- gcc -Wextra fail.c || exit 0

# if we can reach this, the above command did not fail
exit 1
