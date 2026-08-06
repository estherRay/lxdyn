.PHONY: all clean

# The pre-requisite step used to be `make -C ../external/interfaces build`, which built two docker
# images and a wheel just to obtain the generated protobuf stubs. Those stubs are the only
# part xdyn's tests need, and grpc_tools is an ordinary pip package: `mise run integration`
# generates them into the venv-backed work dir instead. See tools/scenario.sh.

# The two lanes need different interpreters: the CLI tests need h5py, and the protocol
# tests need Python 3.10 (xdyngrpc does not import on 3.11+). `mise run integration` and
# `mise run integration:grpc` create them; this Makefile only points at the result, so
# running it directly on a tree that has never seen mise will fail on a missing venv.
CLI_PYTHON  ?= $(abspath $(CURDIR)/../build/venv/bin/python)
GRPC_PYTHON ?= $(abspath $(CURDIR)/../build/venv/grpc/bin/python)

all:
	@make -C xdyn PYTHON=$(CLI_PYTHON)
	@make -C grpc_tests PYTHON=$(GRPC_PYTHON)
	@make -C json_tests PYTHON=$(GRPC_PYTHON)

clean:
	@make -C grpc_tests $@
	@make -C json_tests $@
	@make -C xdyn $@
