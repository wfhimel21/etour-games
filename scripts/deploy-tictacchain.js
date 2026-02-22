// scripts/deploy-tictacchain.js
// Simplified deployment script for TicTacChain (includes ETour as inherited base)

import hre from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    console.log("🚀 Starting TicTacChain Deployment...\n");

    // Get the deployer account
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
    console.log("Network:", hre.network.name);
    console.log("");

    // Deploy TicTacChain (ETour is inherited, not deployed separately)
    console.log("=" .repeat(60));
    console.log("Deploying TicTacChain...");
    console.log("=" .repeat(60));
    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const ticTacChain = await TicTacChain.deploy();
    await ticTacChain.waitForDeployment();
    const ticTacChainAddress = await ticTacChain.getAddress();
    console.log("✅ TicTacChain deployed to:", ticTacChainAddress);
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
        contracts: {
            TicTacChain: ticTacChainAddress
        }
    };

    const networkFile = path.join(deploymentsDir, `${hre.network.name}.json`);
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
        address: ticTacChainAddress,
        network: hre.network.name,
        chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
        deployedAt: timestamp,
        abi: ticTacChainArtifact.abi
    };

    const abiFile = path.join(deploymentsDir, "TTTABI.json");
    fs.writeFileSync(abiFile, JSON.stringify(fullABI, null, 2));
    console.log("✅ Full ABI compiled and saved:", abiFile);
    console.log("");

    // Verification instructions
    console.log("=" .repeat(60));
    console.log("Contract Verification");
    console.log("=" .repeat(60));
    console.log("To verify on block explorers (Etherscan, Arbiscan, etc.), run:");
    console.log("");
    console.log(`npx hardhat verify --network ${hre.network.name} ${ticTacChainAddress}`);
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
    console.log("📍 Contract Address:");
    console.log("  TicTacChain:", ticTacChainAddress);
    console.log("");
    console.log("📁 Deployment Artifacts:");
    console.log("  -", networkFile);
    console.log("  -", abiFile);
    console.log("");
    console.log("🔗 Frontend Integration:");
    console.log("  Update your client app with:");
    console.log(`  const TICTACCHAIN_ADDRESS = "${ticTacChainAddress}";`);
    console.log("  Import ABI from:", abiFile);
    console.log("");
    console.log("🚀 TicTacChain is live!");
    console.log("  ✅ ETour Protocol - Inherited tournament infrastructure");
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
