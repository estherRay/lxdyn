#!/bin/sh
# xdyn as a gRPC model-exchange server (state derivatives rather than integration).
set -eu
. "$(dirname "$0")/../../../tools/scenario.sh"

scenario model_exchange-1
demos

serve xdyn "$BIN/xdyn-for-me" tutorial_01_falling_ball.yml --grpc -p 9002
wait_port 9002

pytest tests.py
