# xdyn

xdyn is a lightweight time-domain ship simulator modelling the dynamic behaviour of a ship at sea, with its actuators, including some non-linear aspects of that behaviour and featuring a customizable maneuvring model.
It simulates the mechanical behaviour of a solid body in a fluid environment by
solving Newton's second law of motion, taking hydrodynamic forces into account.

It was developed by SIREHNA through both self-funded projects and various collaborative projects, including the IRT Jules Verne's ["Bassin Numérique"
project](https://www.irt-jules-verne.fr/wp-content/uploads/bassin-numerique.pdf).

(c) 2014-2015, [IRT Jules Verne](https://www.irt-jules-verne.fr/), [SIREHNA](https://www.sirehna.com/), [Naval Group](https://www.naval-group.com/en/), [Bureau Veritas](https://www.bureauveritas.fr/), [Hydrocean](https://marine-offshore.bureauveritas.com/bvsolutions), [STX France](https://chantiers-atlantique.com/en/), [LHEEA](https://lheea.ec-nantes.fr/) for the initial version.

(c) 2015-2022 [SIREHNA](https://www.sirehna.com/) & [Naval Group](https://www.naval-group.com/en/) for all subsequent versions.

**Disclaimer**: the [user documentation](https://sirehna_naval_group.gitlab.io/sirehna/xdyn/)
is written in French, is hosted by the upstream project, and is not part of this repository.
It is incomplete in places and inaccuracies may remain.

## Getting Started

The easiest way to run xdyn is from a container image, built from the `Containerfile` at the
repository root with `mise run deploy:image`:

```bash
podman run --rm localhost/xdyn-deploy --help
```

See [Running xdyn in a container](#running-xdyn-in-a-container) below. Either podman or
docker works.

The **environment models** implemented inside xdyn are described in detail [here](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/modeles_environnementaux.md)

The **force models** implemented inside xdyn are described in detail [here](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/modeles_efforts.md)

You can also learn how to use xdyn using the tutorials:

- [Falling ball](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md)
- [Hydrostatic](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_02.md)
- [Waves](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_03.md)
- [Propulsion](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_06.md)
- [gRPC wave model](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_09.md)

## Building xdyn from source

### Prerequisites

Building xdyn needs [Nix](https://nixos.org/download/) with flakes enabled. The
`flake.nix` at the repository root pins zig and every tool, so nothing else has
to be installed.

Flakes are not on by default. Either add this to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

or use [direnv](https://direnv.net/), which the committed `.envrc` sets up for you --
`direnv allow` once per clone and entering the directory loads the devShell, so `nix develop`
below becomes optional.

The C++ dependencies — Boost, gRPC, HDF5, yaml-cpp, GoogleTest — are
deliberately *not* system packages: they are built against zig's libc++ into a
closure of their own, so the build does not depend on what the host distribution
ships. `tools/deps/` builds one from source in a few hours, or you can download
a prebuilt one in about 35 MB.

```bash
nix develop
mise run bootstrap             # submodules, SSC umbrella headers, and the closure (~35 MB)
```

`bootstrap` is `mise run setup` plus `mise run deps:fetch x86_64-linux-gnu`, and it is
re-runnable: it leaves an existing closure alone. To build a closure from source instead of
downloading it, use `nix develop .#deps` -- that shell adds the cmake and ninja the recipes
need, and the emulators Boost's cross configure probes run -- then
`mise run deps:x86_64-linux-gnu`. It takes hours.

### Building

```bash
zig build
```

The binaries can then be found in `build/<target>/bin` — `build/x86_64-linux-gnu/bin`
on a typical Linux host. Codegen runs as part of the build; there is no configure step.

Cross-compiling needs nothing but the matching closure:

```bash
mise run deps:fetch aarch64-linux-musl
zig build -Dtarget=aarch64-linux-musl
```

## Running the tests

```bash
mise run build                 # build, then the 916 unit tests
zig build test                 # the unit tests alone
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

## Running xdyn

Build xdyn as above, then run it from the build tree:

```bash
$(sh tools/build-dir.sh)/bin/xdyn <yaml file> [xdyn options]
```

All options can be found in [the documentation](https://sirehna_naval_group.gitlab.io/sirehna/xdyn/#ligne-de-commande).

The tutorials are not in the repository — they are generated, so that the input
files and the code that reads them cannot drift apart. To run the first
[tutorial](https://gitlab.com/sirehna_naval_group/sirehna/xdyn/-/blob/master/doc/user_fr/tutorial_01.md):

```bash
BIN=$(sh tools/build-dir.sh)/bin
mkdir -p demos && cd demos
"$BIN/generate_yaml_example" . && "$BIN/generate_stl_examples" .
"$BIN/xdyn" tutorial_01_falling_ball.yml --dt 0.1 --tend 1
```

That prints nothing: each tutorial names its own outputs, so this one writes
`falling_ball.csv`, `.h5` and `.json` beside itself. Add `-o tsv` to get the
results on the terminal instead.

There is no separate install step: `zig build` writes the executables straight
into the build tree, and the container image is built by copying them.

### Running xdyn in a container

The image is built from the `Containerfile` at the repository root. It does no compiling —
`mise run deploy:image` stages already-built, already-tested binaries into `build/scratch/deploy/`
first, so the image ships exactly what the test suite ran:

```bash
mise run deploy:image
```

There is no `.deb` and no package manager step. The binaries link libc++ and every
third-party library statically, and are built for a glibc 2.28 floor, so the image is a
`COPY` onto a slim base.

To run it — `podman` reads the `Containerfile` by name, `docker` needs `-f`, and both take
the same arguments afterwards:

```bash
podman run --rm --userns=keep-id -v "$PWD:/data" localhost/xdyn-deploy <yaml file> [xdyn options]
```

- `--rm` deletes the container (not the image) after exit
- `--userns=keep-id` maps your UID into the container, so files xdyn writes come out owned
  by you. **This is podman-specific**; under docker use `-u $(id -u):$(id -g)` instead.
  Rootless podman already maps your UID to root inside the container, so `-u` there lands on
  a subuid and the output ends up owned by a stray high UID
- `-v "$PWD:/data"` mounts the current directory over the image's `/data` working directory,
  which is where xdyn writes its `.h5`/`.csv`/`.json`

The tutorials are not baked into the image. The generators are, so you get them with:

```bash
podman run --rm --userns=keep-id -v "$PWD:/data" \
    --entrypoint /usr/bin/generate_yaml_example localhost/xdyn-deploy .
podman run --rm --userns=keep-id -v "$PWD:/data" \
    localhost/xdyn-deploy tutorial_01_falling_ball.yml --dt 0.1 --tend 1 -o tsv
```

`mise run deploy:test` is the smoke test for all of this: it checks that the image starts,
that it simulates against a bind mount with readable output, and that a containerised gRPC
server with a published port is reachable from a native client.

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


## Built with

* [Zig](https://ziglang.org/) - `zig cc` is the compiler and `build.zig` the build system, for Linux, Windows and aarch64 alike from a single host.
* [LLVM](https://llvm.org/) - clang and libc++, which is what `zig cc` is; Visual Studio and libstdc++ are **not** supported.
* [mise](https://mise.jdx.dev/) - Task runner for everything around the build.
* [Nix](https://nixos.org/) - Pins the toolchain and the development shell.
* [Boost](https://www.boost.org/) - For command-line options, regular expressions, filesystem library.
* [yaml-cpp](https://github.com/jbeder/yaml-cpp) - To parse the input files.
* [HDF5](https://support.hdfgroup.org/products/hdf5_tools/index.html) - To store the outputs.
* [Eigen](https://eigen.tuxfamily.org/index.php?title=Main_Page) - For matrix manipulations.
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
