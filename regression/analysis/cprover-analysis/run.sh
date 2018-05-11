# check whether the analysis reveals bugs that can be spotted by humans

rm -rf SP

# test setup
export CBMC_UNWIND=17
export CBMC_DEPTH=10000

# perform the analysis
../../../configuration/one-line-scan -o SP -- gcc main.c -o buggy

# show log of binary analysis
FAILS=$(grep ": FAILURE" SP/log/violation/buggy-d$CBMC_DEPTH-uw$CBMC_UNWIND.cbmc.log | wc -l)

# check the number and exit
if [ -z "$FAILS" ] || [ "$FAILS" -lt 2 ]; then
	echo "error: did not see all expected fails (2 overflow, 1 out of bounds)"
	exit 1
fi

exit 0
