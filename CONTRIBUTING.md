# Contributing to lxdyn

## Code of conduct

This project and everyone participating in it is governed by the [lxdyn Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to charles-edouard.cady@sirehna.com.

## How can I contribute?

### Reporting bugs
### Suggesting enhancements
### Pull requests

We do not accept AI-generated prose in issues or pull requests. A human must explain what the problem is and why the proposed change solves it. Generated code is fine when a human can defend it; a generated description of that code is not.

## Running the tests

`mise run bootstrap` and `zig build` first, as described in the [README](README.md#building-from-source).

```bash
mise run build                 # build, then the 916 unit tests
zig build test                 # the unit tests alone
mise run integration           # 10 command-line scenarios
mise run integration:grpc      # 8 gRPC + 1 JSON protocol scenarios
mise run python:test           # 285 tests for the Python bindings
```

The unit tests are written using Google Test. They are both end-to-end tests and unit tests. The end-to-end ones can be a bit long, so you can disable them with a Google Test filter by running the binary directly:

```bash
$(sh tools/build-dir.sh)/bin/run_all_tests --gtest_filter=-'*LONG*'
```

Please refer to [the Google Test documentation for details and other available options](https://github.com/google/googletest/blob/master/googletest/docs/advanced.md#running-a-subset-of-the-tests).

The cross suites run the same tests under an emulator, and need `nix develop .#cross` for qemu and wine:

```bash
mise run cross
```

Do not reach for `zig build test -Dtarget=...` directly. Where the host has `binfmt_misc` handlers registered, zig runs the foreign binary transparently and the lane passes without either emulator being involved, which makes the result a property of the machine rather than of the build. `mise run cross` names the emulators explicitly with `-fqemu` and `-fwine`.

## Debugging

Build a debug version first. This is `-O0 -g` for lxdyn's own code only; the dependency closure stays optimized, which is what you want, since stepping into Boost is rarely the point.

```bash
zig build -Ddebug
```

Note that this is `-Ddebug`, not `-Doptimize=Debug`.

### Valgrind

The memory analyzer [Valgrind](https://valgrind.org/) can be used during development to check for memory leaks and use of uninitialized values:

```bash
valgrind $(sh tools/build-dir.sh)-debug/bin/run_all_tests
```

Any [flag `run_all_tests` accepts](https://google.github.io/googletest/advanced.html#running-test-programs-advanced-options) can be passed through, in particular filtering:

```bash
valgrind $(sh tools/build-dir.sh)-debug/bin/run_all_tests --gtest_filter='Gravity*'
```

### GDB

`mise run gdb` starts GDB on one of the debug binaries built above, with the repository's `.gdbinit` loaded. GDB otherwise declines to auto-load it, and the helpers it defines would silently not be there:

```bash
mise run gdb -- xdyn tutorial_01_falling_ball.yml
mise run gdb -- run_all_tests --gtest_filter='Gravity*'
```

This will open a GDB prompt. To close it, press Ctrl+D. For more details on how to use GDB, refer to [the official GDB documentation](https://www.gnu.org/software/gdb/).

## Style guides

### Git commits

Commit messages start with a gitmoji, then a summary line in the past tense, then a body explaining why the change was made and what it cost. Never replace something in a single commit: add the new thing, switch to it, then remove the old one, as three commits. Read the last few commits before writing one.

### C++
### Fortran
### C
### Python
