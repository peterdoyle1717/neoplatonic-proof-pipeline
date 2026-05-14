CC      ?= cc
CFLAGS  ?= -O3 -Wall -Wextra -std=c11

UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
  SOLVER_LDLIBS = -framework Accelerate
else
  SOLVER_LDLIBS = -llapack -lblas -lm
endif
PROVER_LDLIBS = -lm

all: euclid_clean euclid_prover euclid_check

euclid_clean: euclid_clean.c
	$(CC) $(CFLAGS) -o $@ $< $(SOLVER_LDLIBS)

euclid_prover: euclid_prover.c
	$(CC) $(CFLAGS) -pedantic -o $@ $< $(PROVER_LDLIBS)

euclid_check: euclid_check.c
	$(CC) $(CFLAGS) -pedantic -o $@ $< -lm

smoke: euclid_clean euclid_prover euclid_check
	./euclid_check --netcode "1,2,3;1,3,4;1,4,2;2,4,3"
	./euclid_clean "1,2,3;1,3,4;1,4,2;2,4,3" > /tmp/euclid_clean_ccae.obj
	./euclid_check --obj /tmp/euclid_clean_ccae.obj
	@head -3 /tmp/euclid_clean_ccae.obj
	@echo "--- ccae vertex/face counts ---"
	@grep -c '^v ' /tmp/euclid_clean_ccae.obj
	@grep -c '^f ' /tmp/euclid_clean_ccae.obj
	@echo "--- ccae prover ---"
	@./euclid_prover /tmp/euclid_clean_ccae.obj | tail -5

batch-smoke: euclid_clean euclid_prover euclid_check
	rm -rf /tmp/euclid_batch_smoke
	mkdir -p /tmp/euclid_batch_smoke/solverout /tmp/euclid_batch_smoke/proverout
	printf '%s\n%s\n' \
	  '1,2,3;1,3,4;1,4,2;2,4,3' \
	  '1,2,3;1,3,4;1,4,2;2,4,3' \
	  > /tmp/euclid_batch_smoke/nets.txt
	./euclid_check --netcodes < /tmp/euclid_batch_smoke/nets.txt > /tmp/euclid_batch_smoke/netcheck.tsv
	./euclid_clean --batch --outdir /tmp/euclid_batch_smoke/solverout \
	  < /tmp/euclid_batch_smoke/nets.txt \
	  > /tmp/euclid_batch_smoke/solver.tsv
	awk -F '\t' '$$2=="ok"{print $$4}' /tmp/euclid_batch_smoke/solver.tsv \
	  > /tmp/euclid_batch_smoke/objs.txt
	./euclid_check --objs < /tmp/euclid_batch_smoke/objs.txt > /tmp/euclid_batch_smoke/objcheck.tsv
	./euclid_prover --batch --outdir /tmp/euclid_batch_smoke/proverout \
	  < /tmp/euclid_batch_smoke/objs.txt \
	  > /tmp/euclid_batch_smoke/prover.tsv || test $$? -eq 2
	@echo "--- netcode check manifest ---"
	@cat /tmp/euclid_batch_smoke/netcheck.tsv
	@echo "--- obj check manifest ---"
	@cat /tmp/euclid_batch_smoke/objcheck.tsv
	@echo "--- solver manifest ---"
	@cat /tmp/euclid_batch_smoke/solver.tsv
	@echo "--- prover manifest ---"
	@cat /tmp/euclid_batch_smoke/prover.tsv

clean:
	rm -f euclid_clean euclid_prover euclid_check /tmp/euclid_clean_*.obj

.PHONY: all smoke batch-smoke clean
