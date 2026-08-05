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
# WHY `FROM scratch`. Not for the sake of a small number — because after `deploy:stage`
# there is nothing left for a base image to provide. The binaries are staged from
# `-Dtarget=x86_64-linux-musl`, which links libc statically on top of the libc++ and
# third-party libraries that were already static, so they have no loader to find and no
# NEEDED entry to satisfy. Anything underneath them would be bytes nothing reads.
#
# This is also why the answer was never `FROM alpine`, which is the obvious small base and is
# wrong for a subtler reason than size: it is a *libc* question, not a base image one. The
# image used to ship x86_64-linux-*gnu* binaries, and those cannot execute on musl at all.
# Fixing the libc is what made the base image unnecessary rather than merely smaller — alpine
# would have been the right base for the wrong binaries.
#
# Measured, and the numbers disagree with each other on purpose. The image is one layer
# holding the same 112 MB of binaries: 117 MB as a tar layer, 43 MB as a registry pull. The
# debian-slim image it replaces was 198 MB, which is 81 MB of base plus that same layer.
#
# `podman images` reports this one as 234 MB. That is not a regression and it is not bytes --
# it is exactly twice the layer, and it contradicts `podman history` on the same image, which
# attributes 117 MB to the COPY and 0 B to WORKDIR and ENTRYPOINT. `podman history` and
# `podman save` agree with each other; the SIZE column double-counts a single-layer scratch
# image. Do not chase the difference.
#
# What scratch costs, so that it is not rediscovered under a deadline. There is no shell, so
# `podman run --entrypoint sh` is not a debugging option and neither is a HEALTHCHECK that
# shells out. There is no /etc/passwd or /etc/group, so the container runs as a bare numeric
# uid. And there are no CA certificates, which costs nothing today because nothing in the
# image speaks TLS, and would have to be COPYed in the day something does.
# ---------------------------------------------------------------------------------------
FROM scratch

# No apt install line, and now no package manager that could run one. The old image needed
# libgfortran5 and libquadmath0 for a Fortran runtime the build never actually required, and
# libicu67 for Boost.
COPY build/deploy/ /usr/bin/

# /data, because xdyn writes its .h5/.csv/.json next to the cwd and the container's own
# filesystem is the wrong place for that. WORKDIR is also the only thing that creates the
# directory — there is no mkdir in this image. Mount over it:
#   podman run --rm --userns=keep-id -v "$PWD:/data" xdyn tutorial_01_falling_ball.yml ...
WORKDIR /data

ENTRYPOINT ["/usr/bin/xdyn"]
