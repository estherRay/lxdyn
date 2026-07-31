#!/bin/sh
# Same as test-1, but on a model with a GM (metacentric height) output.
set -eu
. "$(dirname "$0")/../../../tools/scenario.sh"

scenario model_exchange-2
demos

serve xdyn "$BIN/xdyn-for-me" tutorial_15_gm.yml --grpc -p 9002
wait_port 9002

pytest tests.py
