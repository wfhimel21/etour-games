# ETour Modular Deployment Guide

This directory contains deployment scripts for the modular ETour architecture, where tournament logic is split into reusable modules.

## Architecture Overview

The modular architecture consists of:

### ETour Modules (Shared Libraries)
- **ETour_Core** - Tournament configuration and lifecycle management
- **ETour_Matches** - Match initialization and round management
- **ETour_Prizes** - Prize pool calculation and distribution
- **ETour_Raffle** - Raffle mechanism for unclaimed prizes
- **ETour_Escalation** - Timeout escalation and force-start logic

### Game Contracts
- **TicTacChain** - Tic-Tac-Toe tournament game
- **ChessOnChain** - Full-featured chess tournament game
- **ConnectFourOnChain** - Connect Four tournament game

Each game contract uses `delegatecall` to execute tournament logic from the shared modules, while maintaining its own storage and game-specific rules.

## Deployment Scripts

### Individual Game Deployments

Deploy modules and a single game:

```bash
# Deploy TicTacChain with modules
npx hardhat run scripts/deploy-tictacchain-modular.js --network localhost

# Deploy ChessOnChain with modules
npx hardhat run scripts/deploy-chessonchain-modular.js --network localhost

# Deploy ConnectFourOnChain with modules
npx hardhat run scripts/deploy-connectfour-modular.js --network localhost
```

### Deploy All Games (Recommended)

Deploy all games sharing the same modules (most gas-efficient):

```bash
npx hardhat run scripts/deploy-all-modular.js --network localhost
```

This approach:
- Deploys all 5 modules once
- Deploys all 3 games using the same module addresses
- Saves ~60% deployment gas compared to deploying separately
- Ensures all games use identical tournament logic

### Deploy Modules Only

Deploy just the modules for custom integration:

```bash
npx hardhat run scripts/deploy-modules.js --network localhost
```

## Network Support

Replace `localhost` with your target network:

```bash
# Local development
--network localhost

# Ethereum testnets
--network sepolia
--network goerli

# Arbitrum testnets
--network arbitrum-sepolia

# Mainnet deployments
--network mainnet
--network arbitrum
```

Make sure your `hardhat.config.js` has the appropriate network configurations.

## Deployment Artifacts

After deployment, artifacts are saved to the `./deployments` directory:

### Network Deployment Files
- `localhost-modular.json` - Single game deployment info
- `localhost-all-modular.json` - Complete deployment info (all games)
- Contains module addresses, contract addresses, deployer info, timestamps

### ABI Files
- `TTTABI-modular.json` - TicTacChain ABI and addresses
- `ChessOnChain-ABI-modular.json` - ChessOnChain ABI and addresses
- `ConnectFourOnChain-ABI-modular.json` - ConnectFourOnChain ABI and addresses
- `ETour-All-ABIs-modular.json` - All contracts' ABIs and addresses

## Contract Verification

After deployment, verify contracts on block explorers:

```bash
# Verify modules (do this once per module address)
npx hardhat verify --network <network> <module-address>

# Verify game contracts with constructor args
npx hardhat verify --network <network> <game-address> \
  <core-address> <matches-address> <prizes-address> \
  <raffle-address> <escalation-address>
```

The deployment scripts output the exact verification commands for your deployment.

## Frontend Integration

After deployment, integrate with your frontend:

1. Import the deployment artifact:
```javascript
import deployment from './deployments/localhost-all-modular.json';

const TICTACCHAIN_ADDRESS = deployment.contracts.TicTacChain;
const MODULE_CORE = deployment.modules.ETour_Core;
```

2. Import the ABIs:
```javascript
import { contracts } from './deployments/ETour-All-ABIs-modular.json';

const ticTacChainABI = contracts.TicTacChain.abi;
```

3. Initialize contracts:
```javascript
const ticTacChain = new ethers.Contract(
  TICTACCHAIN_ADDRESS,
  ticTacChainABI,
  signer
);
```

## Module Updates

To update module logic while preserving game contracts:

1. Deploy new module versions
2. Update game contracts to use new module addresses (requires upgrade mechanism)
3. Or deploy new game contracts with updated module addresses

Note: Current implementation uses immutable module addresses set at deployment. For upgradeability, consider using a proxy pattern or module registry.

## Gas Cost Comparison

Estimated deployment costs (at 20 gwei):

| Deployment Type | Gas Used | Cost (ETH) | Cost (USD @ $2000/ETH) |
|----------------|----------|------------|------------------------|
| Single game (old monolithic) | ~8M | ~0.16 | ~$320 |
| Modules + 1 game | ~10M | ~0.20 | ~$400 |
| Modules + 3 games | ~18M | ~0.36 | ~$720 |
| 3 games separately (old) | ~24M | ~0.48 | ~$960 |

**Savings: ~25% gas when deploying multiple games**

## Benefits of Modular Architecture

1. **Code Reusability** - ~3,000 lines of tournament logic shared across all games
2. **Gas Efficiency** - Significant savings when deploying multiple games
3. **Maintainability** - Update tournament logic without touching game-specific code
4. **Extensibility** - Easy to add new games using existing modules
5. **Security** - Tournament logic audited once, used by all games
6. **Smaller Contracts** - Game contracts focus only on game rules

## Testing Modular Contracts

The test suite automatically handles modular deployments:

```bash
npm test
```

The `test/setup.cjs` file intercepts contract deployments and automatically:
1. Deploys all 5 modules
2. Passes module addresses to game contract constructors
3. Zero modifications needed to existing test files

## Troubleshooting

### "Module not found" errors
Ensure all module contracts are compiled:
```bash
npx hardhat compile
```

### "Insufficient funds" errors
Check deployer account balance:
```bash
npx hardhat run scripts/check-balance.js --network <network>
```

### Contract size warnings
The optimizer is enabled in `hardhat.config.js`. If contracts exceed 24KB, consider:
- Increasing optimizer runs (for deployment cost)
- Decreasing optimizer runs (for contract size)
- Current setting: 200 runs (balanced)

### Module delegation failures
Ensure game contracts use the correct module addresses. Check deployment artifacts in `./deployments`.

## Support

For issues or questions:
- Check test results: `npm test`
- Review deployment logs in console output
- Verify contract addresses in `./deployments` directory
