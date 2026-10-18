#!/usr/bin/env bash
# Pinned Solidity dependencies: exact versions, deliberate upgrades.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf lib
forge install --no-git foundry-rs/forge-std@v1.17.0
forge install --no-git OpenZeppelin/openzeppelin-contracts@v5.7.0
