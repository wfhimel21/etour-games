import hre from "hardhat";

async function main() {
    const contracts = [
        { name: "TicTacChain", address: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9" },
        { name: "ChessOnChain", address: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9" },
        { name: "ConnectFourOnChain", address: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707" }
    ];

    for (const contract of contracts) {
        console.log(`\n=== ${contract.name} Timeout Configuration ===\n`);
        
        const Contract = await hre.ethers.getContractFactory(contract.name);
        const game = Contract.attach(contract.address);

        for (let tierId = 0; tierId < 3; tierId++) {
            try {
                const config = await game.tierConfigs(tierId);
                console.log(`Tier ${tierId}:`);
                console.log(`  Players: ${config.playerCount}`);
                console.log(`  Match Time: ${config.timeouts.matchTimePerPlayer}s`);
                console.log(`  L2: ${config.timeouts.matchLevel2Delay}s, L3: ${config.timeouts.matchLevel3Delay}s`);
                
                if (config.timeouts.matchLevel3Delay <= config.timeouts.matchLevel2Delay) {
                    console.log(`  ❌ ERROR: L3 <= L2`);
                } else {
                    console.log(`  ✓ Correct`);
                }
            } catch (e) {
                break; // No more tiers
            }
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
