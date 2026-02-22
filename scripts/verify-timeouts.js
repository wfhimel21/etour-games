import hre from "hardhat";

async function main() {
    const tttAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const game = TicTacChain.attach(tttAddress);

    console.log("\n=== TicTacChain Timeout Configuration ===\n");

    for (let tierId = 0; tierId < 3; tierId++) {
        const config = await game.tierConfigs(tierId);
        console.log(`Tier ${tierId}:`);
        console.log(`  Player Count: ${config.playerCount}`);
        console.log(`  Match Time Per Player: ${config.timeouts.matchTimePerPlayer}s`);
        console.log(`  L2 Delay: ${config.timeouts.matchLevel2Delay}s`);
        console.log(`  L3 Delay: ${config.timeouts.matchLevel3Delay}s`);
        console.log(`  Enrollment Window: ${config.timeouts.enrollmentWindow}s`);
        console.log(`  Enrollment L2 Delay: ${config.timeouts.enrollmentLevel2Delay}s`);

        // Verify L3 > L2
        if (config.timeouts.matchLevel3Delay <= config.timeouts.matchLevel2Delay) {
            console.log(`  ❌ ERROR: L3 delay (${config.timeouts.matchLevel3Delay}s) <= L2 delay (${config.timeouts.matchLevel2Delay}s)`);
        } else {
            console.log(`  ✓ L3 delay > L2 delay (correct)`);
        }
        console.log();
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
