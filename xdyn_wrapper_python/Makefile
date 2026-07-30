# This Makefile builds the xdyn wheel from the xdyn python shared library.
#
# Testing and linting the wrapper no longer live here: `mise run python:matrix` builds and tests
# against each supported Python, and `mise run python:lint` replaces isort/black/pylint. Only the
# wheel build remains, until it moves to `mise run python:wheel` too.

DIR := $(notdir $(shell pwd))
PYTHON=python3
DOCKER_AS_ROOT:=docker run -t --rm -w /opt/share/${DIR} -v $(shell pwd)/..:/opt/share
DOCKER_AS_USER:=$(DOCKER_AS_ROOT) -u $(shell id -u):$(shell id -g)
DOCKER_RUN_BUILD_BASH=$(DOCKER_AS_USER) $(DOCKER_IMAGE_BUILD) /bin/bash -c

# Display the name and comment of each target followed by ' ##'
help: ## Display help and exit.
	@echo 'usage: make [target]'
	@echo
	@echo 'targets:'
	@egrep '^(.+)\:\ ##\ (.+)' ${MAKEFILE_LIST} | column -t -c 2 -s ':#'
	@echo
	@echo "Run higher target to build wheel! It can not be built directly from this Makefile"

debian_11_py309_package: DOCKER_IMAGE_BUILD=xdyn-python-deb11-py309-build
debian_11_py309_package: package

debian_11_py307_package: DOCKER_IMAGE_BUILD=xdyn-python-deb11-py307-build
debian_11_py307_package: package

debian_11_py308_package: DOCKER_IMAGE_BUILD=xdyn-python-deb11-py308-build
debian_11_py308_package: package

debian_11_py310_package: DOCKER_IMAGE_BUILD=xdyn-python-deb11-py310-build
debian_11_py310_package: package

xdyn.deb: ../../build_deb11_pywrapper/xdyn.deb
	@cp $< $@

.PHONY=xdyngrpc
xdyngrpc:
	make -C ../../interfaces build
	@cp ../../interfaces/xdyngrpc*.whl .

create_docker_image_debian11_py309: xdyn.deb xdyngrpc
	docker build \
		-f Dockerfile_deploy \
		--build-arg DOCKER_BASE_IMAGE=debian:bullseye-slim \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=9 \
		-t xdyn-debian11-py309 \
		.

create_docker_image_ubuntu2204_py310: xdyn.deb xdyngrpc
	docker build \
		-f Dockerfile_deploy \
		--build-arg DOCKER_BASE_IMAGE=ubuntu:22.04 \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=10 \
		-t xdyn-ubuntu2204-py310 \
		.

doc: ## Create documentation with Sphinx
doc: debian_11_py309_package
	@make -C doc

package: ## Create the wheel package
	make ${DOCKER_IMAGE_BUILD}
	make DOCKER_IMAGE_BUILD=${DOCKER_IMAGE_BUILD} package_build_wheel

package_build_wheel: ## Create xdyn wheel package
	$(eval GIT_VERSION := $(shell $(DOCKER_AS_USER) -v $(shell pwd)/../..:/all $(DOCKER_IMAGE_BUILD) \
		/bin/bash -c "cd /all && git describe --abbrev=0 --tag --always | cut -f2 -dv"))
	@echo "GIT_VERSION = ${GIT_VERSION}"
	$(DOCKER_RUN_BUILD_BASH) \
	    "GIT_VERSION=\"${GIT_VERSION}\" ${PYTHON} setup.py bdist_wheel &&\
		mv dist/*.whl ."

clean: ## Removed all generated files
	@rm -rf build
	@rm -rf core
	@rm -rf dist
	@rm -rf proto
	@rm -rf *.egg-info
	@rm -rf *.whl
	@rm -f *.coverage
	@rm -f nosetests.xml
	@rm -rf unit_tests/__pycache__
	@rm -f unit_tests/*.coverage
	@rm -f unit_tests/core
	@rm -f unit_tests/nosetests.xml
	@rm -f *.deb
	@rm -f *.whl
	@find . -type d -name __pycache__ -exec rm -rf {} \; || true

.PHONY=xdyn-python-deb11-build
xdyn-python-deb11-build:
	docker build \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=9 \
		--build-arg PYTHON_PATCH_VERSION=9 \
		-f Dockerfile_deb11_py3yz_pybind \
		-t $@ .

.PHONY=xdyn-python-deb11-py307-build
xdyn-python-deb11-py307-build:
	docker build \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=7 \
		--build-arg PYTHON_PATCH_VERSION=12 \
		-f Dockerfile_deb11_py3yz_pybind \
		-t $@ .

.PHONY=xdyn-python-deb11-py308-build
xdyn-python-deb11-py308-build:
	docker build \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=8 \
		--build-arg PYTHON_PATCH_VERSION=12 \
		-f Dockerfile_deb11_py3yz_pybind \
		-t $@ .

.PHONY=xdyn-python-deb11-py309-build
xdyn-python-deb11-py309-build:
	docker build \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=9 \
		--build-arg PYTHON_PATCH_VERSION=9 \
		-f Dockerfile_deb11_py3yz_pybind \
		-t $@ .

.PHONY=xdyn-python-deb11-py310-build
xdyn-python-deb11-py310-build:
	docker build \
		--build-arg PYTHON_MAJOR_VERSION=3 \
		--build-arg PYTHON_MINOR_VERSION=10 \
		--build-arg PYTHON_PATCH_VERSION=2 \
		-f Dockerfile_deb11_py3yz_pybind \
		-t $@ .
