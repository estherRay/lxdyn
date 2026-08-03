# xdyn deploy image. Build it with `mise run deploy:image`, which stages stripped binaries
# into build/deploy/ first — this file deliberately does no compiling, so the image ships the
# same binaries that were tested, not a second build of them.
#
# The replacement for ./Dockerfile — debian-bullseye-slim + `ADD xdyn.deb`, plus
# libgfortran5 / libquadmath0 / libicu67, plus ~40 lines of `echo >> xdyn_cli.sh`. All of
# that existed because the CMake build links dynamically against a C++ runtime and packages
# via CPack. The zig build links libc++ and every third-party library statically, so the
# image is a COPY. `xdyn --help` replaces the help wrapper, which could not have run on a
# slim base anyway.
#
# Named Containerfile, not Dockerfile: `podman build .` finds this automatically, docker
# needs `-f` either way. `deploy:image` passes -f explicitly so both behave identically.
#
# ---------------------------------------------------------------------------------------
# WHY NOT `FROM alpine`. Not because of the base image — because of the libc. The plan
# assumed the zig build produces fully static binaries; it does not. The native target is
# x86_64-linux-*gnu*, so libc and libm stay dynamic. Everything C++ is static, which is the
# part that removed the .deb, but alpine is musl and these binaries cannot run on it at all.
#
# `-Dtarget=x86_64-linux-musl` and the matching closure now both exist, and musl links
# statically -- so the destination is `FROM scratch` rather than alpine, with no base image at
# all. Measured: the same 112 MB of binaries, 198 MB down to 117 MB. Switching is a separate
# decision with its own verification, deliberately not folded into the rename.
#
# Staying on glibc is fine as long as the binaries are built for a glibc *floor* rather than
# for whatever the build host has — see `deploy:stage`, which pins 2.28 to match the closure.
# That floor clears every maintained base: trixie 2.41, bookworm 2.36, Ubuntu 22.04 2.35, and
# back to Debian 10 and RHEL 8, which are the oldest still in service. The base below is
# therefore a free choice rather than a forced one, and trixie-slim is picked for being
# current and small. Verify with `nm -D --undefined-only`, which `deploy:stage` prints.
# ---------------------------------------------------------------------------------------
FROM debian:trixie-slim

# No apt install line at all. The old image needed libgfortran5 and libquadmath0 for a
# Fortran runtime the build never actually required, and libicu67 for Boost.
COPY build/deploy/ /usr/bin/

# /data, because xdyn writes its .h5/.csv/.json next to the cwd and the container's own
# filesystem is the wrong place for that. Mount over it:
#   podman run --rm --userns=keep-id -v "$PWD:/data" xdyn tutorial_01_falling_ball.yml ...
WORKDIR /data

ENTRYPOINT ["/usr/bin/xdyn"]
