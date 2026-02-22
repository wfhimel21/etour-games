import hre from "hardhat";

async function main() {
    console.log("\n=== Checking Storage Layouts ===\n");
    
    // Get TicTacChain storage layout
    const ticTacBuildInfo = await hre.artifacts.getBuildInfo("contracts/TicTacChain.sol:TicTacChain");
    const ticTacStorage = ticTacBuildInfo.output.contracts["contracts/TicTacChain.sol"]["TicTacChain"].storageLayout;
    
    // Get PlayerTrackingModule storage layout
    const moduleBuildInfo = await hre.artifacts.getBuildInfo("contracts/modules/PlayerTrackingModule.sol:PlayerTrackingModule");
    const moduleStorage = moduleBuildInfo.output.contracts["contracts/modules/PlayerTrackingModule.sol"]["PlayerTrackingModule"].storageLayout;
    
    // Find player tracking variables
    const vars = ["playerEnrollingTournaments", "playerEnrollingIndex", "playerActiveTournaments", "playerActiveIndex"];
    
    console.log("Variable positions in TicTacChain:");
    vars.forEach(v => {
        const entry = ticTacStorage.storage.find(s => s.label === v);
        if (entry) {
            console.log(`  ${v}: slot ${entry.slot}, offset ${entry.offset}`);
        } else {
            console.log(`  ${v}: NOT FOUND`);
        }
    });
    
    console.log("\nVariable positions in PlayerTrackingModule:");
    vars.forEach(v => {
        const entry = moduleStorage.storage.find(s => s.label === v);
        if (entry) {
            console.log(`  ${v}: slot ${entry.slot}, offset ${entry.offset}`);
        } else {
            console.log(`  ${v}: NOT FOUND`);
        }
    });
}

main().catch(console.error);
