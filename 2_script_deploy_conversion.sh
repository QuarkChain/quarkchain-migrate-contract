#!/bin/bash
set -e

if [[ ! -f .env ]]; then
  echo "❌ .env file not found"
  exit 1
fi

export $(grep -v '^#' .env | xargs)
if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY_DEPLOYER" || -z "$ETHERSCAN_API_KEY" ]]; then
  echo "❌ Missing RPC_URL / PRIVATE_KEY_DEPLOYER / ETHERSCAN_API_KEY in .env"
  exit 1
fi

if [[ -z "$OPTIMISM_PORTAL2" || -z "$OLD_QKC_ADDRESS" || -z "$ADMIN_ADDRESS" || -z "$PAUSER_ADDRESS" ]]; then
  echo "❌ Missing one of: OPTIMISM_PORTAL2 / OLD_QKC_ADDRESS / ADMIN_ADDRESS / PAUSER_ADDRESS"
  exit 1
fi

echo "🚀 Deploying TokenConversion..."
forge script script/TokenConverDeployScript.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY_DEPLOYER" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY"
