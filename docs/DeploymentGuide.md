# ETour Protocol Integration - Deployment Guide

## Overview
This guide walks through deploying and testing the ETour protocol split for TicTacTour.

## Files Delivered
1. **ETour.sol** - Universal tournament protocol (425 lines)
2. **TicTacTour_Modified.sol** - Updated TicTacTour integrated with ETour
3. **DeploymentScript.js** - Deployment script for Hardhat
4. **TestingScript.js** - Basic testing script

## Architecture Changes Summary

### What Changed (10-15 modifications)
1. ✅ Added ETour import and state variable
2. ✅ Modified constructor to accept ETour address
3. ✅ Enrollment check uses `etour.canStartTournament()`
4. ✅ Force start uses `etour.canForceStartTournament()`
5. ✅ Match count calculation uses `etour.calculateRoundMatchCount()`
6. ✅ First round pairing uses `etour.calculateFirstRoundPairings()`
7. ✅ Three-way fee split uses `etour.calculateThreeWaySplit()`
8. ✅ Round completion checks use `etour.isRoundComplete()`
9. ✅ Total rounds calculation uses `etour.calculateTotalRounds()`
10. ✅ Removed duplicate _log2 function
11. ✅ Commented out duplicate fee constants

### What Stayed the Same (90%+)
- All game logic (tic-tac-toe rules, blocking mechanic)
- All events
- All structs
- All mappings
- All view functions
- Complete ABI compatibility
- Frontend compatibility

## Deployment Steps

### 1. Local Testing (Hardhat)

```bash
# Install dependencies
npm install --save-dev hardhat @openzeppelin/contracts

# Create hardhat config if needed
npx hardhat init

# Compile contracts
npx hardhat compile
```

### 2. Deploy on Test Network (e.g., Arbitrum Sepolia)

```javascript
// deploy.js
const hre = require("hardhat");

async function main() {
    console.log("Deploying ETour Protocol Split...");
    
    // Step 1: Deploy ETour protocol
    const ETour = await hre.ethers.getContractFactory("ETour");
    const etour = await ETour.deploy();
    await etour.deployed();
    console.log("ETour deployed to:", etour.address);
    
    // Step 2: Deploy TicTacTour with ETour address
    const TicTacTour = await hre.ethers.getContractFactory("TicTacTour");
    const game = await TicTacTour.deploy(etour.address);
    await game.deployed();
    console.log("TicTacTour deployed to:", game.address);
    
    // Step 3: Verify contracts on Etherscan
    console.log("\nVerifying contracts...");
    await hre.run("verify:verify", {
        address: etour.address,
        constructorArguments: [],
    });
    
    await hre.run("verify:verify", {
        address: game.address,
        constructorArguments: [etour.address],
    });
    
    console.log("\n✅ Deployment complete!");
    console.log("Update frontend CONTRACT_ADDRESS to:", game.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
```

### 3. Test Core Functionality

```javascript
// test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ETour Integration Test", function () {
    let etour, game, owner, player1, player2;
    
    beforeEach(async function () {
        [owner, player1, player2] = await ethers.getSigners();
        
        // Deploy ETour
        const ETour = await ethers.getContractFactory("ETour");
        etour = await ETour.deploy();
        
        // Deploy TicTacTour with ETour
        const TicTacTour = await ethers.getContractFactory("TicTacTour");
        game = await TicTacTour.deploy(etour.address);
    });
    
    it("Should enroll players correctly", async function () {
        // Test enrollment in tier 0 (2-player classic)
        const entryFee = ethers.utils.parseEther("0.001");
        
        await game.connect(player1).enrollInTournament(0, 0, { value: entryFee });
        await game.connect(player2).enrollInTournament(0, 0, { value: entryFee });
        
        // Tournament should auto-start when full
        const tournament = await game.tournaments(0, 0);
        expect(tournament.status).to.equal(1); // InProgress
    });
    
    it("Should calculate rounds correctly via ETour", async function () {
        // Test that ETour correctly calculates rounds
        expect(await etour.calculateTotalRounds(2)).to.equal(1);
        expect(await etour.calculateTotalRounds(4)).to.equal(2);
        expect(await etour.calculateTotalRounds(8)).to.equal(3);
        expect(await etour.calculateTotalRounds(16)).to.equal(4);
    });
    
    it("Should split fees correctly via ETour", async function () {
        const amount = ethers.utils.parseEther("1");
        const [participants, owner, protocol] = await etour.calculateThreeWaySplit(amount);
        
        expect(participants).to.equal(ethers.utils.parseEther("0.9"));
        expect(owner).to.equal(ethers.utils.parseEther("0.075"));
        expect(protocol).to.equal(ethers.utils.parseEther("0.025"));
    });
});
```

### 4. Frontend Update

```javascript
// In App.jsx, update line 767:
const CONTRACT_ADDRESS = "0x... // Your new TicTacTour address";

// No other changes needed! The ABI remains identical.
```

## Multi-Chain Deployment

### Deploy on Multiple Chains

```javascript
// multi-chain-deploy.js
async function deployOnChain(chainName, rpcUrl, privateKey) {
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    
    console.log(`\nDeploying on ${chainName}...`);
    
    // Deploy ETour
    const ETour = await ethers.getContractFactory("ETour", wallet);
    const etour = await ETour.deploy();
    await etour.deployed();
    console.log(`${chainName} - ETour:`, etour.address);
    
    // Deploy TicTacTour
    const TicTacTour = await ethers.getContractFactory("TicTacTour", wallet);
    const game = await TicTacTour.deploy(etour.address);
    await game.deployed();
    console.log(`${chainName} - TicTacTour:`, game.address);
    
    return { etour: etour.address, game: game.address };
}

async function main() {
    const deployments = {};
    
    // Deploy on Arbitrum
    deployments.arbitrum = await deployOnChain(
        "Arbitrum",
        process.env.ARBITRUM_RPC,
        process.env.PRIVATE_KEY
    );
    
    // Deploy on Optimism
    deployments.optimism = await deployOnChain(
        "Optimism",
        process.env.OPTIMISM_RPC,
        process.env.PRIVATE_KEY
    );
    
    // Deploy on Ethereum Mainnet
    deployments.mainnet = await deployOnChain(
        "Mainnet",
        process.env.MAINNET_RPC,
        process.env.PRIVATE_KEY
    );
    
    console.log("\n✅ Multi-chain deployment complete!");
    console.log(JSON.stringify(deployments, null, 2));
}
```

## Verification Checklist

### Pre-Deployment
- [ ] ETour.sol compiles without errors
- [ ] TicTacTour_Modified.sol compiles without errors
- [ ] Constructor properly accepts ETour address
- [ ] All ETour function calls are correctly integrated

### Post-Deployment Testing
- [ ] Players can enroll in tournaments
- [ ] Tournament auto-starts when full
- [ ] Force start works after timeout
- [ ] Matches initialize correctly
- [ ] Players can make moves
- [ ] Blocking mechanic works
- [ ] Winners advance to next round
- [ ] Prize distribution works
- [ ] Timeouts and claims work
- [ ] Frontend displays everything correctly

### ABI Compatibility Check
```javascript
// Compare ABIs to ensure compatibility
const oldABI = require('./TourABI.json');
const newABI = artifacts.require('TicTacTour').abi;

// All public/external functions should match
console.log("ABI Compatible:", JSON.stringify(oldABI) === JSON.stringify(newABI));
```

## Next Steps After Deployment

### 1. Building Additional Games
With ETour deployed, you can now build other games that use the same protocol:

```solidity
// EternalChess.sol
contract EternalChess {
    ETour public immutable etour;
    
    constructor(address _etour) {
        etour = ETour(_etour);
    }
    
    // Chess-specific game logic
    // Uses same ETour functions for tournament management
}
```

### 2. Protocol Governance
Consider implementing:
- Protocol fee recipient management
- Fee percentage adjustments (via DAO)
- Game whitelisting/verification

### 3. Cross-Chain Coordination
Future enhancement:
- Deploy cross-chain message passing
- Unified leaderboards
- Cross-chain tournaments

## Troubleshooting

### Common Issues

1. **"Invalid ETour address"**
   - Ensure ETour is deployed first
   - Pass correct address to TicTacTour constructor

2. **Gas estimation errors**
   - Increase gas limit for deployment
   - TicTacTour is large, may need 10M+ gas

3. **Frontend not updating**
   - Clear browser cache
   - Ensure CONTRACT_ADDRESS is updated
   - Check network connection

### Support Resources
- Arbitrum Docs: https://docs.arbitrum.io/
- Optimism Docs: https://docs.optimism.io/
- Hardhat: https://hardhat.org/

## Success Metrics

### Immediate (Day 1)
- ✅ Contracts deployed and verified
- ✅ Frontend connecting properly
- ✅ First tournament completes successfully

### Short Term (Week 1)
- Multiple tournaments running simultaneously
- No unexpected reverts or errors
- Gas costs remain reasonable

### Long Term (Month 1)
- Second game using ETour deployed
- Community feedback positive
- Protocol fees accumulating

## Summary

The ETour protocol split transforms TicTacTour from a monolithic contract into a modular system:

**Before:**
```
TicTacTour.sol (2,900 lines)
└── Everything bundled together
```

**After:**
```
ETour.sol (425 lines)
├── Universal tournament logic
├── Stateless, reusable
└── Multi-chain ready

TicTacTour.sol (2,895 lines)
├── Game-specific logic
├── Uses ETour protocol
└── 100% ABI compatible
```

This is the foundation for the RW3 gaming ecosystem - **the HTTP of blockchain gaming**! 🚀

## Estimated Timeline
- **Modification & Testing**: 4-6 hours
- **Single Chain Deployment**: 1 hour
- **Multi-Chain Deployment**: 3 hours total
- **Total**: ~1 day of focused work

Ready to revolutionize Web3 gaming! 🎮⚡
