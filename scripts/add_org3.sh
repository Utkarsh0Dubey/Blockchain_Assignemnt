#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
cd "$HOME/fabric-samples/test-network/addOrg3"
./addOrg3.sh up -c global-supply -s couchdb
