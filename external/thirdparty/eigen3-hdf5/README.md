# eigen3-hdf5

Vendored from [github.com/garrison/eigen3-hdf5](https://github.com/garrison/eigen3-hdf5)
at `f161974` (2021-08-26), which is upstream's tip — the project has not moved since.
MIT, © 2013 James R. Garrison; `LICENSE` is kept beside the headers as that requires.

Vendored rather than carried as a git submodule because it is two headers from a dormant
upstream, and because a submodule is invisible to a Nix flake's source tree: it would have
been the one dependency that could not be pinned by hash. Only `eigen3-hdf5.hpp` is included
by xdyn (`Hdf5WaveObserver.cpp`, `stl_io_hdf5.cpp`); `eigen3-hdf5-sparse.hpp` comes along
because upstream ships the pair and separating them would be a local edit.
