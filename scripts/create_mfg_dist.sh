#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"

TN="$HOME/fabric-samples/test-network"
cd "$TN"

# Use the test-network helper to create & join a new app channel the v2.5 way
./network.sh createChannel -c mfg-dist
