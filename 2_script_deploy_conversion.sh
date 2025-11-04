#!/bin/bash
set -e

export $(grep -v '^#' .env | xargs)

if [[ -z "OPTIMISM_PORTAL2" || -z "$OLD_QKC_ADDRESS" ]]; then
  echo "❌ Missing addresses in .env"
  exit 1
fi

echo "🚀 Deploying TokenConversion..."
forge script script/TokenConverDeployScript.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY_DEPLOYER" \
  --broadcast \
  --verify
