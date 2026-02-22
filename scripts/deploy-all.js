// scripts/deploy-all.js
// Master deployment script for all game contracts

import hre from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    console.log("Starting Full Platform Deployment...\n");

    // Get the deployer account
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
    console.log("Network:", hre.network.name);
    console.log("");

    // Create deployments directory if it doesn't exist
    const deploymentsDir = "./deployments";
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const timestamp = new Date().toISOString();
    const chainId = (await hre.ethers.provider.getNetwork()).chainId.toString();
    const contracts = {};

    // ===== Deploy TicTacChain =====
    console.log("=".repeat(60));
    console.log("1/3 Deploying TicTacChain...");
    console.log("=".repeat(60));
    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const ticTacChain = await TicTacChain.deploy();
    await ticTacChain.waitForDeployment();
    contracts.TicTacChain = await ticTacChain.getAddress();
    console.log("TicTacChain deployed to:", contracts.TicTacChain);
    console.log("");

    // Save TicTacChain ABI
    const ticTacChainArtifact = await hre.artifacts.readArtifact("TicTacChain");
    fs.writeFileSync(
        path.join(deploymentsDir, "TTTABI.json"),
        JSON.stringify({
            contractName: "TicTacChain",
            address: contracts.TicTacChain,
            network: hre.network.name,
            chainId: chainId,
            deployedAt: timestamp,
            abi: ticTacChainArtifact.abi
        }, null, 2)
    );

    // ===== Deploy ChessOnChain =====
    console.log("=".repeat(60));
    console.log("2/3 Deploying ChessOnChain...");
    console.log("=".repeat(60));
    const ChessOnChain = await hre.ethers.getContractFactory("ChessOnChain");
    const chessOnChain = await ChessOnChain.deploy();
    await chessOnChain.waitForDeployment();
    contracts.ChessOnChain = await chessOnChain.getAddress();
    console.log("ChessOnChain deployed to:", contracts.ChessOnChain);
    console.log("");

    // Save ChessOnChain ABI
    const chessOnChainArtifact = await hre.artifacts.readArtifact("ChessOnChain");
    fs.writeFileSync(
        path.join(deploymentsDir, "COCABI.json"),
        JSON.stringify({
            contractName: "ChessOnChain",
            address: contracts.ChessOnChain,
            network: hre.network.name,
            chainId: chainId,
            deployedAt: timestamp,
            abi: chessOnChainArtifact.abi
        }, null, 2)
    );

    // ===== Deploy ConnectFourOnChain =====
    console.log("=".repeat(60));
    console.log("3/3 Deploying ConnectFourOnChain...");
    console.log("=".repeat(60));
    const ConnectFourOnChain = await hre.ethers.getContractFactory("ConnectFourOnChain");
    const connectFourOnChain = await ConnectFourOnChain.deploy();
    await connectFourOnChain.waitForDeployment();
    contracts.ConnectFourOnChain = await connectFourOnChain.getAddress();
    console.log("ConnectFourOnChain deployed to:", contracts.ConnectFourOnChain);
    console.log("");

    // Save ConnectFourOnChain ABI
    const connectFourOnChainArtifact = await hre.artifacts.readArtifact("ConnectFourOnChain");
    fs.writeFileSync(
        path.join(deploymentsDir, "CFOCABI.json"),
        JSON.stringify({
            contractName: "ConnectFourOnChain",
            address: contracts.ConnectFourOnChain,
            network: hre.network.name,
            chainId: chainId,
            deployedAt: timestamp,
            abi: connectFourOnChainArtifact.abi
        }, null, 2)
    );

    // Get final block number
    const blockNumber = await hre.ethers.provider.getBlockNumber();

    // Save unified deployment info
    const networkDeployment = {
        network: hre.network.name,
        chainId: chainId,
        deployer: deployer.address,
        timestamp: timestamp,
        blockNumber: blockNumber,
        contracts: contracts
    };

    const networkFile = path.join(deploymentsDir, `${hre.network.name}.json`);
    fs.writeFileSync(networkFile, JSON.stringify(networkDeployment, null, 2));

    // Final summary
    console.log("=".repeat(60));
    console.log("DEPLOYMENT SUCCESSFUL!");
    console.log("=".repeat(60));
    console.log("");
    console.log("Deployment Summary:");
    console.log("  Network:", hre.network.name);
    console.log("  Chain ID:", chainId);
    console.log("  Block:", blockNumber);
    console.log("");
    console.log("Contract Addresses:");
    console.log("  TicTacChain:       ", contracts.TicTacChain);
    console.log("  ChessOnChain:      ", contracts.ChessOnChain);
    console.log("  ConnectFourOnChain:", contracts.ConnectFourOnChain);
    console.log("");
    console.log("Deployment Artifacts:");
    console.log("  -", networkFile);
    console.log("  -", path.join(deploymentsDir, "TTTABI.json"));
    console.log("  -", path.join(deploymentsDir, "COCABI.json"));
    console.log("  -", path.join(deploymentsDir, "CFOCABI.json"));
    console.log("");
    console.log("Next Steps:");
    console.log("  1. Run 'npm run sync:abis' to copy ABIs to frontend");
    console.log("  2. Update frontend .env with contract addresses");
    console.log("");
    console.log("Verification Commands:");
    console.log(`  npx hardhat verify --network ${hre.network.name} ${contracts.TicTacChain}`);
    console.log(`  npx hardhat verify --network ${hre.network.name} ${contracts.ChessOnChain}`);
    console.log(`  npx hardhat verify --network ${hre.network.name} ${contracts.ConnectFourOnChain}`);
    console.log("");
}

// Error handling
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Deployment failed:", error);
        process.exit(1);
    });
