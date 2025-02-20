PACT := pact -t

POST := | grep "FAILURE" || true


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
	${PACT} test-consuming.repl ${POST}

test-reporting: vectors/blocks-800000-800050-init.repl
	${PACT} test-reporting.repl ${POST}

test-gas: vectors/blocks-800000-800050-init.repl vectors/blocks-800051-800060.repl
	${PACT} test-gas.repl | grep "GAS:"

test-range-0: vectors/blocks-0-2500-init.repl
	${PACT} test-range-0.repl ${POST}

test-range-1: vectors/blocks-400000-402500-init.repl
	${PACT} test-range-1.repl ${POST}

test-range-2: vectors/blocks-800000-802500-init.repl
	${PACT} test-range-2.repl ${POST}

test-ranges: test-range-0 test-range-1 test-range-2

tests: test-reporting test-consuming test-gas test-ranges

clean:
	rm vectors/*
