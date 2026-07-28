.PHONY: all headers update-submodules generate_proto clean changelog CHANGELOG.md

all: update-submodules generate_proto headers

HEADERS=code/ssc/ssc/check_ssc_version.hpp\
        code/ssc/ssc/csv_file_reader.hpp\
        code/ssc/ssc/data_source.hpp\
        code/ssc/ssc/decode_unit.hpp\
        code/ssc/ssc/exception_handling.hpp\
        code/ssc/ssc/geometry.hpp\
        code/ssc/ssc/integrate.hpp\
        code/ssc/ssc/interpolation.hpp\
        code/ssc/ssc/ipopt_interface.hpp\
        code/ssc/ssc/json.hpp\
        code/ssc/ssc/kinematics.hpp\
        code/ssc/ssc/macros.hpp\
        code/ssc/ssc/numeric.hpp\
        code/ssc/ssc/random_data_generator.hpp\
        code/ssc/ssc/solver.hpp\
        code/ssc/ssc/text_file_reader.hpp\
        code/ssc/ssc/websocket.hpp\
        code/ssc/ssc/yaml_parser.hpp

headers: ${HEADERS}

# `git submodule sync` is deliberately absent here and in mise: .gitmodules uses relative URLs,
# which git resolves against the current branch's remote, so syncing from a fork rewrites every
# submodule URL to a repository that does not exist.
update-submodules:
	@echo "Updating Git submodules..."
	@git submodule update --init --recursive
	@git submodule foreach --recursive 'git fetch --tags'

${HEADERS}:
	@git submodule update --init --recursive
	@cd code/ssc/ssc && sh generate_module_header.sh

generate_proto:
	make -C interfaces build

clean:
	@rm -rf build_*
	@make -C doc clean
	@make -C code/xdyn_wrapper_python clean

changelog: CHANGELOG.md
changelog: ## Generates CHANGELOG.md from git merge commits
CHANGELOG.md:
	@make -C changelog
	@cp changelog/$@ .
