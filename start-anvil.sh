#!/bin/sh
# Simulate Arbitrum L2 with EIP-4844 (Proto-Danksharding) support
# EIP-4844 provides ultra-cheap blob data availability for L2s
#
# Key features:
# - Cancun hardfork enables blob transactions (EIP-4844)
# - Blob gas is ~100x cheaper than calldata gas
# - Typical blob base fee: 1-10 wei vs execution base fee: 0.01-0.1 Gwei
# - Each blob: 128KB data at minimal cost
# - L2s use blobs to post transaction data to L1 cheaply
#
# Gas pricing simulation:
# - Execution base fee: 0.01 Gwei (10M wei) - for smart contract execution
# - Blob base fee: 1 wei - for data availability (EIP-4844)
# - This mimics real Arbitrum/Optimism post-Dencun economics

exec anvil \
  --host 0.0.0.0 \
  --port 8545 \
  --chain-id 412346 \
  --hardfork cancun \
  --block-time 1 \
  --accounts 30 \
  --balance 10000 \
  --gas-limit 1125899906842624 \
  --block-base-fee-per-gas 10000000 \
  --code-size-limit 131072
