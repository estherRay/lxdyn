#!/bin/sh
# Python Airy wave server <- xdyn (gRPC client) <- tests.py (cosimulation client).
# Three processes, two protocols, xdyn in the middle.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario waves
demos

# airy_server.py rather than `-m xdyngrpc.waves.server.airy`: the packaged model draws its
# wave phases unseeded, which diverges this scenario about one run in five. See its docstring.
serve waves_server "$PYTHON" "$SRC/airy_server.py"
wait_port 50051

serve xdyn "$BIN/xdyn-for-cs" tutorial_09_gRPC_wave_model.yml -g --dt 1 -p 9002
wait_port 9002

pytest tests.py
