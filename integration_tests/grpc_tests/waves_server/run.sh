#!/bin/sh
# xdyn's own C++ Airy wave server, exercised by the Python reference client.
# The one scenario where xdyn is the gRPC *server* and Python is the client.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario waves_server

serve waves_server "$BIN/xdyn-grpc-airy" -p 50051
wait_port 50051

pytest tests.py
