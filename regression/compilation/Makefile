DIRS =  $(filter-out Makefile, $(wildcard *))

test:
	$(foreach var,$(DIRS), $(MAKE) -C $(var) test || exit 1;)

clean:
	$(foreach var,$(DIRS), $(MAKE) -C $(var) clean;)
