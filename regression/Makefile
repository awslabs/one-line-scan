DIRS =  $(filter-out Makefile, $(wildcard *))

test:
	$(foreach var,$(DIRS), $(MAKE) -C $(var) test;)

clean:
	$(foreach var,$(DIRS), $(MAKE) -C $(var) clean;)
