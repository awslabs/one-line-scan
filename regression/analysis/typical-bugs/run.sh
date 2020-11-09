# check whether the analysis reveals bugs that can be spotted by humans

rm -rf SP

export CBMC_UNWIND=4
export CBMC_DEPTH=1000

../../../one-line-scan -o SP -- gcc test.c -o typical-bugs

# show log of binary analysis
cat SP/log/violation/typical-bugs-d1000-uw4.cbmc.log

exit 0
