// Quick debug script to check initialization state
import hre from "hardhat";
import { readFileSync } from "fs";

async function main() {
    const deployment = JSON.parse(readFileSync("./deployments/localhost-chess-modular.json", "utf-8"));
    const chess = await hre.ethers.getContractAt("ChessOnChain", deployment.contracts.ChessOnChain);

    console.log("=== Initialization Status ===");
    console.log("allInstancesInitialized:", await chess.allInstancesInitialized());
    console.log("tierCount:", await chess.tierCount());

    // Check tier configs
    for (let tierId = 0; tierId < 2; tierId++) {
        try {
            const config = await chess.getTierConfig(tierId);
            console.log(`\nTier ${tierId}:`);
            console.log("  - playerCount:", config.playerCount.toString());
            console.log("  - instanceCount:", config.instanceCount.toString());
            console.log("  - entryFee:", hre.ethers.formatEther(config.entryFee), "ETH");
            console.log("  - initialized:", config.initialized);
        } catch (e) {
            console.log(`Tier ${tierId}: Error -`, e.message);
        }
    }

    // Check first few tournament instances
    console.log("\n=== Sample Tournament Instances ===");
    for (let tierId = 0; tierId < 2; tierId++) {
        for (let instanceId = 0; instanceId < 3; instanceId++) {
            const tournament = await chess.tournaments(tierId, instanceId);
            console.log(`Tournament [${tierId}][${instanceId}]:`, {
                status: tournament.status,
                enrolledCount: tournament.enrolledCount.toString(),
                startTime: tournament.startTime.toString()
            });
        }
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
