#!/bin/sh
# xdyn as a gRPC cosimulation server, driven by the Python client. No model server.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario cosim
demos

serve xdyn "$BIN/xdyn-for-cs" tutorial_01_falling_ball.yml --grpc --dt 0.1 -p 9002
wait_port 9002

pytest tests.py
