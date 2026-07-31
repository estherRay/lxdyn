#!/bin/sh
# Five checks against Python force models reached over gRPC. They all bind 9002 (the port
# is hardcoded in xdyngrpc), so each server is stopped before the next one starts.
#
#   sim             -- a plain simulation; the CSV must have one line per time step.
#   cosim           -- the same model driven through xdyn's websocket cosimulation API.
#   hdb / precal-r  -- every coefficient of an HDB / PRECAL-R file must reach the force
#                      model unaltered; the post-checks assert on the exact values.
#   filtered-states -- filtered states with a zero time constant must equal the raw ones.
set -eu
. "$(dirname "$0")/../../tools/scenario.sh"

scenario force
demos

echo "--- sim: simulation driven by a gRPC force model"
serve force_model "$PYTHON" "$SRC/harmonic_oscillator.py"
wait_port 9002
"$BIN/xdyn" tutorial_10_gRPC_force_model.yml tutorial_10_gRPC_force_model_commands.yml \
    --dt 0.1 --tend 0.2 -o out.csv
# $(( )) strips the leading whitespace BSD wc -l emits, which `[ -ne ]` may reject.
lines=$(( $(wc -l < out.csv) ))
if [ "$lines" -ne 4 ]; then
    echo "***error: out.csv has $lines line(s), expected 4 (header + 3 time steps)"
    exit 1
fi
echo "out.csv has the expected 4 lines: test passed!"

echo "--- cosim: same force model, through the cosimulation API"
# xdyn's own server has to move off 9002: the force model already owns it here.
serve xdyn "$BIN/xdyn-for-cs" tutorial_10_gRPC_force_model.yml --dt 0.1 -p 9003
wait_port 9003
export xdyn_server_url=ws://localhost:9003
pytest tests.py
stop xdyn
stop force_model

echo "--- hdb: HDB coefficients must reach the force model unaltered"
serve force_model "$PYTHON" "$SRC/hdb_force_model.py"
wait_port 9002
"$BIN/xdyn" tutorial_13_hdb_force_model.yml --dt 1 --tend 0 -o out.csv
check test_hdb.py
stop force_model

echo "--- precal-r: same, for a PRECAL-R file"
serve force_model "$PYTHON" "$SRC/hdb_force_model.py"
wait_port 9002
"$BIN/xdyn" tutorial_13_precal_r_force_model.yml --dt 1 --tend 0 -o out.csv
check test_precal_r.py
stop force_model

echo "--- filtered-states: tutorial 14"
serve force_model "$PYTHON" "$SRC/filtered_force.py"
wait_port 9002
"$BIN/xdyn" tutorial_14_filtered_states.yml --dt 0.1 --tend 40
check test_filtered_states.py
