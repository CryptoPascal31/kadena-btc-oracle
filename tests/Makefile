PACT := pact
.PHONY: all tests clean test-consuming test-reporting test-gas test-range-0 test-range-1 test-range-3 test-ranges checktypes

all: tests

vectors/blocks-0-2500-init.repl:
	python3 gen_tests_vectors.py --init --log 0 2500

vectors/blocks-400000-402500-init.repl:
	python3 gen_tests_vectors.py --init --log 400000 402500

vectors/blocks-800000-802500-init.repl:
	python3 gen_tests_vectors.py --init --log 800000 802500

vectors/blocks-800000-800050-init.repl:
	python3 gen_tests_vectors.py --init 800000 800050

vectors/blocks-800051-800060.repl:
	python3 gen_tests_vectors.py 800051 800060

test-consuming: vectors/blocks-800000-800050-init.repl
	pact test-consuming.repl

test-reporting: vectors/blocks-800000-800050-init.repl
	pact test-reporting.repl

test-gas: vectors/blocks-800000-800050-init.repl vectors/blocks-800051-800060.repl
	pact test-gas.repl

test-range-0: vectors/blocks-0-2500-init.repl
	pact test-range-0.repl

test-range-1: vectors/blocks-400000-402500-init.repl
	pact test-range-0.repl

test-range-2: vectors/blocks-800000-802500-init.repl
	pact test-range-0.repl

test-ranges: test-range-0 test-range-1 test-range-2

checktypes:
	pact checktypes.repl

tests: test-reporting test-consuming test-gas test-ranges

clean:
	rm vectors/*
