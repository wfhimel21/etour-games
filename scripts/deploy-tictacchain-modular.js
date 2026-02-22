// scripts/deploy-tictacchain-modular.js
// Deployment script for modular TicTacChain with ETour modules

import hre from "hardhat";
import fs from "fs";
import path from "path";
import { getOrDeployModules } from "./deploy-modules.js";

async function main() {
    console.log("🚀 Starting Modular TicTacChain Deployment...\n");

    // Get the deployer account
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
    console.log("Network:", hre.network.name);
    console.log("");

    // Get or deploy modules (reuses existing if available)
    const modules = await getOrDeployModules(true);

    // Deploy TicTacChain (ETour is inherited, not deployed separately)
    console.log("=" .repeat(60));
    console.log("Deploying TicTacChain...");
    console.log("=" .repeat(60));
    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const tictacchain = await TicTacChain.deploy(
        modules.core,
        modules.matches,
        modules.prizes,
        modules.raffle,
        modules.escalation
    );
    await tictacchain.waitForDeployment();
    const tttAddress = await tictacchain.getAddress();
    console.log("✅ TicTacChain deployed to:", tttAddress);
    console.log("");


    // Get current block number
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const timestamp = new Date().toISOString();

    // Create deployments directory if it doesn't exist
    const deploymentsDir = "./deployments";
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    // Save network deployment info
    console.log("=" .repeat(60));
    console.log("Saving Deployment Artifacts...");
    console.log("=" .repeat(60));

    const networkDeployment = {
        network: hre.network.name,
        chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
        deployer: deployer.address,
        timestamp: timestamp,
        blockNumber: blockNumber,
        modules: {
            ETour_Core: modules.core,
            ETour_Matches: modules.matches,
            ETour_Prizes: modules.prizes,
            ETour_Raffle: modules.raffle,
            ETour_Escalation: modules.escalation
        },
        contracts: {
            TicTacChain: tttAddress
        }
    };

    const networkFile = path.join(deploymentsDir, `${hre.network.name}-modular.json`);
    fs.writeFileSync(networkFile, JSON.stringify(networkDeployment, null, 2));
    console.log("✅ Network deployment info saved:", networkFile);

    // Compile and save full ABI as TTTABI.json
    console.log("");
    console.log("=" .repeat(60));
    console.log("Compiling Full ABI...");
    console.log("=" .repeat(60));

    const ticTacChainArtifact = await hre.artifacts.readArtifact("TicTacChain");

    const fullABI = {
        contractName: "TicTacChain",
        address: tttAddress,
        network: hre.network.name,
        chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
        deployedAt: timestamp,
        modules: modules,
        abi: ticTacChainArtifact.abi
    };

    const abiFile = path.join(deploymentsDir, "TTTABI-modular.json");
    fs.writeFileSync(abiFile, JSON.stringify(fullABI, null, 2));
    console.log("✅ Full ABI compiled and saved:", abiFile);
    console.log("");
    
    // Verification instructions
    console.log("=" .repeat(60));
    console.log("Contract Verification");
    console.log("=" .repeat(60));
    console.log("To verify on block explorers (Etherscan, Arbiscan, etc.), run:");
    console.log("");
    console.log("# Verify modules:");
    console.log(`npx hardhat verify --network ${hre.network.name} ${modules.core}`);
    console.log(`npx hardhat verify --network ${hre.network.name} ${modules.matches}`);
    console.log(`npx hardhat verify --network ${hre.network.name} ${modules.prizes}`);
    console.log(`npx hardhat verify --network ${hre.network.name} ${modules.raffle}`);
    console.log(`npx hardhat verify --network ${hre.network.name} ${modules.escalation}`);
    console.log("");
    console.log("# Verify TicTacChain:");
    console.log(`npx hardhat verify --network ${hre.network.name} ${tttAddress} ${modules.core} ${modules.matches} ${modules.prizes} ${modules.raffle} ${modules.escalation}`);
    console.log("");

    // Final summary
    console.log("=" .repeat(60));
    console.log("🎉 DEPLOYMENT SUCCESSFUL! 🎉");
    console.log("=" .repeat(60));
    console.log("");
    console.log("📋 Deployment Summary:");
    console.log("  Network:", hre.network.name);
    console.log("  Chain ID:", networkDeployment.chainId);
    console.log("  Block:", blockNumber);
    console.log("");
    console.log("📍 Module Addresses:");
    console.log("  ETour_Core:          ", modules.core);
    console.log("  ETour_Matches:       ", modules.matches);
    console.log("  ETour_Prizes:        ", modules.prizes);
    console.log("  ETour_Raffle:        ", modules.raffle);
    console.log("  ETour_Escalation:    ", modules.escalation);
    console.log("");
    console.log("📍 Contract Address:");
    console.log("  TicTacChain:", tttAddress);
    console.log("");
    console.log("📁 Deployment Artifacts:");
    console.log("  -", networkFile);
    console.log("  -", abiFile);
    console.log("");
    console.log("🔗 Frontend Integration:");
    console.log("  Update your client app with:");
    console.log(`  const TICTACCHAIN_ADDRESS = "${tttAddress}";`);
    console.log("  Import ABI from:", abiFile);
    console.log("");
    console.log("🚀 TicTacChain is live!");
    console.log("  ✅ ETour Modular Protocol - Reusable tournament infrastructure");
    console.log("  ✅ TicTacChain - Classic Tic-Tac-Toe tournament game");
    console.log("  📋 6 tiers, up to 128 players per tournament!");
    console.log("");
}

// Error handling
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Deployment failed:", error);
        process.exit(1);
    });
