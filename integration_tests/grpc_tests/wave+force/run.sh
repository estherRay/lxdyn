#!/bin/sh
# A Python force model that asks xdyn for the linearized wave spectrum, so the wave
# information makes a full round trip: tests.py -> xdyn -> model.py -> xdyn -> tests.py.
#
# Under compose the force model and xdyn both listened on 9002, in separate containers.
# On localhost that is a port clash, and xdyngrpc hardcodes 9002 for force models, so it
# is xdyn's cosimulation port that moves.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario wave+force
fixtures xdyn.yml

serve force_model "$PYTHON" "$SRC/model.py"
wait_port 9002

serve xdyn "$BIN/xdyn-for-cs" xdyn.yml --dt 0.1 -g -p 9003
wait_port 9003

# `pytest` is a shell function here, so an assignment prefix would leak; export instead.
export xdyn_server_url=localhost:9003
pytest tests.py
