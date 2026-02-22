// scripts/deploy-battleship.js
// Deployment script for EternalBattleship (includes ETour as inherited base)

import hre from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    console.log("🚀 Starting EternalBattleship Deployment...\n");

    // Get the deployer account
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
    console.log("Network:", hre.network.name);
    console.log("");

    // Deploy EternalBattleship (ETour is inherited, not deployed separately)
    console.log("=".repeat(60));
    console.log("Deploying EternalBattleship...");
    console.log("=".repeat(60));
    const EternalBattleship = await hre.ethers.getContractFactory("EternalBattleship");
    const eternalBattleship = await EternalBattleship.deploy();
    await eternalBattleship.waitForDeployment();
    const eternalBattleshipAddress = await eternalBattleship.getAddress();
    console.log("✅ EternalBattleship deployed to:", eternalBattleshipAddress);
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
    console.log("=".repeat(60));
    console.log("Saving Deployment Artifacts...");
    console.log("=".repeat(60));

    const networkDeployment = {
        network: hre.network.name,
        chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
        deployer: deployer.address,
        timestamp: timestamp,
        blockNumber: blockNumber,
        contracts: {
            EternalBattleship: eternalBattleshipAddress
        }
    };

    const networkFile = path.join(deploymentsDir, `${hre.network.name}-battleship.json`);
    fs.writeFileSync(networkFile, JSON.stringify(networkDeployment, null, 2));
    console.log("✅ Network deployment info saved:", networkFile);

    // Compile and save full ABI as EBSABI.json
    console.log("");
    console.log("=".repeat(60));
    console.log("Compiling Full ABI...");
    console.log("=".repeat(60));

    const eternalBattleshipArtifact = await hre.artifacts.readArtifact("EternalBattleship");

    const fullABI = {
        contractName: "EternalBattleship",
        address: eternalBattleshipAddress,
        network: hre.network.name,
        chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
        deployedAt: timestamp,
        abi: eternalBattleshipArtifact.abi
    };

    const abiFile = path.join(deploymentsDir, "EBSABI.json");
    fs.writeFileSync(abiFile, JSON.stringify(fullABI, null, 2));
    console.log("✅ Full ABI compiled and saved:", abiFile);
    console.log("");

    // Verification instructions
    console.log("=".repeat(60));
    console.log("Contract Verification");
    console.log("=".repeat(60));
    console.log("To verify on block explorers (Etherscan, Arbiscan, etc.), run:");
    console.log("");
    console.log(`npx hardhat verify --network ${hre.network.name} ${eternalBattleshipAddress}`);
    console.log("");

    // Final summary
    console.log("=".repeat(60));
    console.log("🎉 DEPLOYMENT SUCCESSFUL! 🎉");
    console.log("=".repeat(60));
    console.log("");
    console.log("📋 Deployment Summary:");
    console.log("  Network:", hre.network.name);
    console.log("  Chain ID:", networkDeployment.chainId);
    console.log("  Block:", blockNumber);
    console.log("");
    console.log("📍 Contract Address:");
    console.log("  EternalBattleship:", eternalBattleshipAddress);
    console.log("");
    console.log("📁 Deployment Artifacts:");
    console.log("  -", networkFile);
    console.log("  -", abiFile);
    console.log("");
    console.log("🔗 Frontend Integration:");
    console.log("  Update your client app with:");
    console.log(`  const ETERNAL_BATTLESHIP_ADDRESS = "${eternalBattleshipAddress}";`);
    console.log("  Import ABI from:", abiFile);
    console.log("");
    console.log("🚀 EternalBattleship is live!");
    console.log("  ✅ ETour Protocol - Inherited tournament infrastructure");
    console.log("  ✅ EternalBattleship - Hidden information battleship game");
    console.log("  🎯 Features: Direct board submission, fog-of-war via access control");
    console.log("  📋 3 tiers: 2-player (10), 4-player (5), 8-player (3) instances");
    console.log("");
}

// Error handling
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Deployment failed:", error);
        process.exit(1);
    });
