# xdyn

xdyn is a lightweight time-domain ship simulator modelling the dynamic behaviour of a ship at sea, with its actuators, including some non-linear aspects of that behaviour and featuring a customizable maneuvring model.
It simulates the mechanical behaviour of a solid body in a fluid environment by
solving Newton's second law of motion, taking hydrodynamic forces into account.

It was developed by SIREHNA through both self-funded projects and various collaborative projects, including the IRT Jules Verne's ["Bassin Numérique"
project](https://www.irt-jules-verne.fr/wp-content/uploads/bassin-numerique.pdf).

(c) 2014-2015, [IRT Jules Verne](https://www.irt-jules-verne.fr/), [SIREHNA](https://www.sirehna.com/), [Naval Group](https://www.naval-group.com/en/), [Bureau Veritas](https://www.bureauveritas.fr/), [Hydrocean](https://marine-offshore.bureauveritas.com/bvsolutions), [STX France](https://chantiers-atlantique.com/en/), [LHEEA](https://lheea.ec-nantes.fr/) for the initial version.

(c) 2015-2022 [SIREHNA](https://www.sirehna.com/) & [Naval Group](https://www.naval-group.com/en/) for all subsequent versions.

**Disclaimer**: [External documentation](https://sirehna_naval_group.gitlab.io/sirehna/xdyn/) and [internal documentation](https://sirehna.gitlab-pages.sirehna.com/xdyn/)
was written for a French project, with
French participants, therefore it is in French. It will be translated
eventually. Also, please note that it is still a work-in-progress and, as such,
can be incomplete. Despite our best efforts, inaccuracies may remain. However,
the documentation will continue to evolve as new developments on xdyn are
on-going.

## Getting Started

The easiest way to run xdyn is to use [Docker](https://www.docker.com/):

```bash
docker run sirehna/xdyn
```

This does not require installing or downloading anything except Docker itself.

Pre-built binaries of xdyn are also available:

- [for Debian 11](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/jobs/artifacts/master/download?job=build%3Adebian11-release)
- [for Windows](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/jobs/artifacts/master/download?job=build%3Awindows)

There are many other ways of using xdyn, all of which are described
in [the documentation](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/jobs/artifacts/master/download?job=doc).

The **environment models** implemented inside xdyn are described in detail [here](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/modeles_environnementaux.md)

The **force models** implemented inside xdyn are described in detail [here](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/modeles_efforts_commandes_et_non_commandes.md)

You can also learn how to use xdyn using the tutorials:

- [Falling ball](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md)
- [Hydrostatic](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_02.md)
- [Waves](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_03.md)
- [Propulsion](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_06.md)
- [gRPC wave model](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_09.md)
- [gRPC force model](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_10.md)
- [gRPC controller](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_11.md)

## Building xdyn from source

This section describes what you need to do if you wish to compile xdyn
yourself.
These instructions will get you a copy of the project up and running on your
local machine for development and testing purposes. See deployment for notes on
how to deploy the project on a live system.

### Prerequisites

Building xdyn needs [Nix](https://nixos.org/download/) with flakes enabled. The
`flake.nix` at the repository root pins zig and every tool, so nothing else has
to be installed.

The C++ dependencies — Boost, gRPC, HDF5, yaml-cpp, GoogleTest — are
deliberately *not* system packages: they are built against zig's libc++ into a
closure of their own, so the build does not depend on what the host distribution
ships. `tools/deps/` builds one from source in a few hours, or you can download
a prebuilt one in about 35 MB.

```bash
nix develop
mise run deps:fetch native     # or `mise run deps:native` to build it yourself
mise run setup                 # submodules and the SSC umbrella headers
```

### Installing

```bash
zig build
```

The binaries can then be found in `build/<target>/bin` — `build/x86_64-linux-gnu/bin`
on a typical Linux host. Codegen runs as part of the build; there is no configure step.

Cross-compiling needs nothing but the matching closure:

```bash
mise run deps:fetch aarch64
zig build -Dtarget=aarch64-linux-musl
```

## Running the tests

```bash
zig build test                 # 916 unit tests
mise run integration           # 10 command-line scenarios
mise run integration:grpc      # 8 gRPC + 1 JSON protocol scenarios
mise run python:test           # 285 tests for the Python bindings
```

The unit tests are written using Google test. These are both end-to-end tests
and unit tests. The end-to-end tests can be a bit long, so you can disable them
with a Google Test filter by running the binary directly:

```bash
$(sh tools/build-dir.sh)/bin/run_all_tests --gtest_filter=-'*LONG*'
```

Please refer to [the Google Test documentation for details and other available
options](https://github.com/google/googletest/blob/master/googletest/docs/advanced.md#running-a-subset-of-the-tests).

### The CMake build

CMake is kept as a second opinion — it compiles the same sources with g++ and
libstdc++, which is worth having when a failure looks like it might be a zig or
libc++ problem. It is **not** the supported build, and CI does not run it: it
resolves Boost, gRPC and HDF5 from the environment, which is the dependency the
zig lane exists to remove.

```bash
mise run configure && mise run build && mise run test
```

## Running xdyn

### Running xdyn

Build xdyn as above, then from `build_native/xdyn/executables` run:

```bash
./xdyn <yaml file> [xdyn options]
```

All options can be found in [the documentation](https://sirehna_naval_group.gitlab.io/sirehna/xdyn/#ligne-de-commande).

For example, to run the first [tutorial](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md),
from the executables/demos folder, you can run:

```bash
./xdyn tutorial_01_falling_ball.yml --dt 0.1 --tend 1
```

### Running an installed xdyn

After `mise run install` the executable is in `install_native`. You can then run:

```bash
xdyn <yaml file> [xdyn options]
```

All options can be found in [the documentation](https://sirehna_naval_group.gitlab.io/sirehna/xdyn/#ligne-de-commande).

For example, to run the first [tutorial](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md),

```bash
xdyn tutorial_01_falling_ball.yml --dt 0.1 --tend 1
```

### Running xdyn on Debian with Docker

To create a Docker image containing xdyn, build the `.deb` and then:

```bash
docker build . --tag xdyn
```

To run the xdyn Docker container, use:

```bash
docker run -it --rm -u $(id -u):$(id -g) -v $(pwd):/build -w /build/path_to_yaml_file xdyn <yaml file> [xdyn options]
```

- Flag `--rm` deletes the container (not the image) after exit
- Flag `-u $(id -u):$(id -g)` launches the container with the permissions
of the current user, which ensures the files generated by xdyn (if any) are
owned by the current user
- Flag `-v $(pwd):/build` mounts the current directory to the container's
`/build` directory
- Flag `-w /build/path_to_yaml_file` sets the container's working directory and
`path_to_yaml_file` should be replaced by a sub-path of the current directory

More details can be found in
[Docker's official documentation](https://docs.docker.com/engine/reference/commandline/run/).

For example, to run the first [tutorial](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md) and display the results in the terminal, assuming we are in the project's root directory:

```bash
docker run -it --rm -w /usr/demos sirehna/xdyn tutorial_01_falling_ball.yml --dt 0.1 --tend 1 -o tsv
```

## Debugging

Build a debug version first. This is `-O0 -g` for xdyn's own code only; the
dependency closure stays optimized, which is what you want — stepping into
Boost is rarely the point.

```bash
zig build -Ddebug
```

### Valgrind

The memory analyzer [Valgrind](https://valgrind.org/) can be used during
development to check for memory leaks and use of uninitialized values:

```bash
valgrind $(sh tools/build-dir.sh)-debug/bin/run_all_tests
```

Any [flag `run_all_tests` accepts](https://google.github.io/googletest/advanced.html#running-test-programs-advanced-options)
can be passed through, in particular filtering:

```bash
valgrind $(sh tools/build-dir.sh)-debug/bin/run_all_tests --gtest_filter='Gravity*'
```

### GDB

`mise run gdb` starts GDB on one of the debug binaries built above, with the
repository's `.gdbinit` loaded — GDB otherwise declines to auto-load it, and
the helpers it defines would silently not be there:

```bash
mise run gdb -- xdyn tutorial_01_falling_ball.yml
mise run gdb -- run_all_tests --gtest_filter='Gravity*'
```

This will open a GDB prompt. To close it, press Ctrl+D. For more details on how
to use GDB, refer to [the official GDB
documentation](https://www.gnu.org/software/gdb/).


## Deployment

Add additional notes about how to deploy this on a live system.

## Built with

* [CMake](https://cmake.org/) - Used to compile C++ code for various platforms.
* [Make](https://www.gnu.org/software/make/) - Used for the one-step build described above.
* [GCC](https://gcc.gnu.org/) - Compiler used for both the Windows & Linux: Visual Studio is currently **not** supported.
* [Boost](https://www.boost.org/) - For command-line options, regular expressions, filesystem library.
* [yaml-cpp](https://github.com/jbeder/yaml-cpp) - To parse the input files.
* [HDF5](https://support.hdfgroup.org/products/hdf5_tools/index.html) - To store the outputs.
* [Eigen](https://eigen.tuxfamily.org/index.php?title=Main_Page) - For matrix manipulations.
* [Pandoc](https://pandoc.org/) - To generate the documentation.
* [Pweave](https://mpastell.com/pweave/) - To generate the tutorials.
* [SSC](https://gitlab.com/sirehna_naval_group/sirehna/ssc) - For websockets, units decoding, interpolations, kinematics, CSV file reading and exception handling.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to submit
issues & pull requests to xdyn.
Our code of conduct is the [Contributor Covenant](CODE_OF_CONDUCT.md) (original
version available
[here](https://www.contributor-covenant.org/version/1/4/code-of-conduct) ).

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/tags).

## Authors

The main contributors to this project are:

* [Charles-Edouard CADY](https://gitlab.com/CharlesEdouardCady_SIREHNA)
* [Guillaume JACQUENOT](https://gitlab.com/GuillaumeJacquenot)
* [Léa LINCKER](https://gitlab.com/llincker)
* [Moran CHARLOU](https://gitlab.com/mcharlou)


See also the [full list of contributors](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/contributors) who took part in this project.

## License

This project is licensed under the Eclipse Public License (version 2) - see the [LICENSE.md](LICENSE.md) file for details.
