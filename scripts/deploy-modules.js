// scripts/deploy-modules.js
// Helper script to deploy ETour modules

import hre from "hardhat";
import fs from "fs";
import path from "path";

const MODULES_DEPLOYMENT_FILE = "./deployments/modules-shared.json";

/**
 * Load existing module addresses from deployment file
 * @returns {Object|null} Module addresses or null if not found
 */
export function loadExistingModules() {
    if (fs.existsSync(MODULES_DEPLOYMENT_FILE)) {
        const data = JSON.parse(fs.readFileSync(MODULES_DEPLOYMENT_FILE, "utf8"));
        // Verify it's for the current network
        if (data.network === hre.network.name) {
            console.log("📦 Found existing module deployment for network:", hre.network.name);
            return data.modules;
        }
    }
    return null;
}

/**
 * Save module addresses to deployment file
 * @param {Object} modules Module addresses
 */
export function saveModuleAddresses(modules) {
    const deploymentsDir = "./deployments";
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentData = {
        network: hre.network.name,
        chainId: null, // Will be set by caller if available
        timestamp: new Date().toISOString(),
        modules: modules
    };

    fs.writeFileSync(MODULES_DEPLOYMENT_FILE, JSON.stringify(deploymentData, null, 2));
    console.log("💾 Module addresses saved to:", MODULES_DEPLOYMENT_FILE);
}

/**
 * Get or deploy ETour modules
 * Checks if modules are already deployed for this network and reuses them
 * @param {boolean} forceDeploy Force new deployment even if modules exist
 * @returns {Promise<Object>} Object containing all module addresses
 */
export async function getOrDeployModules(forceDeploy = false) {
    // Try to load existing modules first
    if (!forceDeploy) {
        const existing = loadExistingModules();
        if (existing) {
            console.log("✅ Reusing existing module deployment");
            console.log("  ETour_Core:       ", existing.core);
            console.log("  ETour_Matches:    ", existing.matches);
            console.log("  ETour_Prizes:     ", existing.prizes);
            console.log("  ETour_Raffle:     ", existing.raffle);
            console.log("  ETour_Escalation: ", existing.escalation);
            console.log("");
            return existing;
        }
    }

    // Deploy new modules
    const modules = await deployModules();

    // Save for future use
    saveModuleAddresses(modules);

    return modules;
}

/**
 * Deploy all ETour modules and return their addresses
 * @returns {Promise<Object>} Object containing all module addresses
 */
export async function deployModules() {
    console.log("=" .repeat(60));
    console.log("Deploying ETour Modules...");
    console.log("=" .repeat(60));

    // Deploy ETour_Core
    console.log("Deploying ETour_Core...");
    const ETour_Core = await hre.ethers.getContractFactory("contracts/modules/ETour_Core.sol:ETour_Core");
    const moduleCore = await ETour_Core.deploy();
    await moduleCore.waitForDeployment();
    const moduleCoreAddress = await moduleCore.getAddress();
    console.log("✅ ETour_Core deployed to:", moduleCoreAddress);

    // Deploy ETour_Matches
    console.log("Deploying ETour_Matches...");
    const ETour_Matches = await hre.ethers.getContractFactory("contracts/modules/ETour_Matches.sol:ETour_Matches");
    const moduleMatches = await ETour_Matches.deploy();
    await moduleMatches.waitForDeployment();
    const moduleMatchesAddress = await moduleMatches.getAddress();
    console.log("✅ ETour_Matches deployed to:", moduleMatchesAddress);

    // Deploy ETour_Prizes
    console.log("Deploying ETour_Prizes...");
    const ETour_Prizes = await hre.ethers.getContractFactory("contracts/modules/ETour_Prizes.sol:ETour_Prizes");
    const modulePrizes = await ETour_Prizes.deploy();
    await modulePrizes.waitForDeployment();
    const modulePrizesAddress = await modulePrizes.getAddress();
    console.log("✅ ETour_Prizes deployed to:", modulePrizesAddress);

    // Deploy ETour_Raffle
    console.log("Deploying ETour_Raffle...");
    const ETour_Raffle = await hre.ethers.getContractFactory("contracts/modules/ETour_Raffle.sol:ETour_Raffle");
    const moduleRaffle = await ETour_Raffle.deploy();
    await moduleRaffle.waitForDeployment();
    const moduleRaffleAddress = await moduleRaffle.getAddress();
    console.log("✅ ETour_Raffle deployed to:", moduleRaffleAddress);

    // Deploy ETour_Escalation
    console.log("Deploying ETour_Escalation...");
    const ETour_Escalation = await hre.ethers.getContractFactory("contracts/modules/ETour_Escalation.sol:ETour_Escalation");
    const moduleEscalation = await ETour_Escalation.deploy();
    await moduleEscalation.waitForDeployment();
    const moduleEscalationAddress = await moduleEscalation.getAddress();
    console.log("✅ ETour_Escalation deployed to:", moduleEscalationAddress);

    console.log("");
    console.log("✅ All 5 core modules deployed successfully!");
    console.log("   (Player tracking is built-in, game logic is integrated)");
    console.log("");

    return {
        core: moduleCoreAddress,
        matches: moduleMatchesAddress,
        prizes: modulePrizesAddress,
        raffle: moduleRaffleAddress,
        escalation: moduleEscalationAddress
    };
}

// Allow running standalone
if (import.meta.url === `file://${process.argv[1]}`) {
    const forceDeploy = process.argv.includes("--force");

    getOrDeployModules(forceDeploy)
        .then((addresses) => {
            console.log("=" .repeat(60));
            console.log("Module Addresses:");
            console.log("=" .repeat(60));
            console.log("ETour_Core:       ", addresses.core);
            console.log("ETour_Matches:    ", addresses.matches);
            console.log("ETour_Prizes:     ", addresses.prizes);
            console.log("ETour_Raffle:     ", addresses.raffle);
            console.log("ETour_Escalation: ", addresses.escalation);
            console.log("");
            if (forceDeploy) {
                console.log("⚠️  Forced new deployment (--force flag used)");
            } else {
                console.log("💡 To force new deployment, run: node scripts/deploy-modules.js --force");
            }
            console.log("");
            process.exit(0);
        })
        .catch((error) => {
            console.error("❌ Module deployment failed:", error);
            process.exit(1);
        });
}
