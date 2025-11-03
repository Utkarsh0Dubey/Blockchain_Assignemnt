#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
cd "$HOME/fabric-samples/test-network"
./network.sh down
./network.sh up createChannel -c global-supply
