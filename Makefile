.PHONY: all headers update-submodules generate_proto clean

all: update-submodules generate_proto headers

HEADERS=external/ssc/ssc/check_ssc_version.hpp\
        external/ssc/ssc/csv_file_reader.hpp\
        external/ssc/ssc/data_source.hpp\
        external/ssc/ssc/decode_unit.hpp\
        external/ssc/ssc/exception_handling.hpp\
        external/ssc/ssc/geometry.hpp\
        external/ssc/ssc/integrate.hpp\
        external/ssc/ssc/interpolation.hpp\
        external/ssc/ssc/ipopt_interface.hpp\
        external/ssc/ssc/json.hpp\
        external/ssc/ssc/kinematics.hpp\
        external/ssc/ssc/macros.hpp\
        external/ssc/ssc/numeric.hpp\
        external/ssc/ssc/random_data_generator.hpp\
        external/ssc/ssc/solver.hpp\
        external/ssc/ssc/text_file_reader.hpp\
        external/ssc/ssc/websocket.hpp\
        external/ssc/ssc/yaml_parser.hpp

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
	@cd external/ssc/ssc && sh generate_module_header.sh

generate_proto:
	make -C interfaces build

clean:
	@rm -rf build_*
	@make -C docs clean
	@make -C xdyn_wrapper_python clean
