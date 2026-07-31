#!/bin/sh
# Two independent checks against a Python PID controller reached over gRPC:
#
#   tutorial_11 -- a 500 s heading-control run; test.py asserts the heading converged on
#                  both setpoints.
#   issue 204   -- the first state time must honour --tstart. Regression only: it passes
#                  if xdyn exits 0.
#
# Each uses its own controller process, because tutorial_11 drives the scenario-local
# pid_controller.py while issue 204 drives the one packaged in xdyngrpc.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario controller
demos
fixtures xdyn_param_issue_204.yml

echo "--- tutorial_11: heading control"
serve pid "$PYTHON" "$SRC/pid_controller.py"
wait_port 9002
"$BIN/xdyn" tutorial_11_gRPC_controller.yml --dt 1 --tend 500 \
    -o tutorial_11_gRPC_controller.hdf5
check test.py

echo "--- issue 204: first state time must match --tstart"
stop pid
serve controller "$PYTHON" -m xdyngrpc.controllers.pid_controller
wait_port 9002
"$BIN/xdyn" xdyn_param_issue_204.yml --dt 0.1 --tend -5.0 --tstart -10.0
echo "xdyn accepted a negative tstart with a gRPC controller: test passed!"
