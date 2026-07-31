#!/bin/sh
# The websocket + JSON cosimulation API -- the same conversation as grpc_tests/cosim, over
# the other transport. This is the only scenario that is not gRPC.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario json_cosim
demos

serve xdyn "$BIN/xdyn-for-cs" tutorial_01_falling_ball.yml --dt 0.1 -p 9002
wait_port 9002

pytest tests.py
