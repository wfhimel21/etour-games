// scripts/sync-abis.js
// Syncs deployment ABIs to the frontend project

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const FRONTEND_PATH = path.resolve(__dirname, "../../tic-tac-react/src");
const DEPLOYMENTS_PATH = path.resolve(__dirname, "../deployments");

// ABI mapping: source -> destination
const ABI_MAP = {
    "TTTABI.json": "TicTacChainABI.json",
    "COCABI.json": "COCABI.json",
    "CFOCABI.json": "CFOCABI.json"
};

function main() {
    console.log("Syncing ABIs to frontend...\n");

    // Check if deployments directory exists
    if (!fs.existsSync(DEPLOYMENTS_PATH)) {
        console.error("Error: Deployments directory not found at", DEPLOYMENTS_PATH);
        console.error("Run 'npm run deploy:all' first to generate deployment artifacts.");
        process.exit(1);
    }

    // Check if frontend directory exists
    if (!fs.existsSync(FRONTEND_PATH)) {
        console.error("Error: Frontend src directory not found at", FRONTEND_PATH);
        process.exit(1);
    }

    let successCount = 0;
    let errorCount = 0;

    for (const [source, dest] of Object.entries(ABI_MAP)) {
        const sourcePath = path.join(DEPLOYMENTS_PATH, source);
        const destPath = path.join(FRONTEND_PATH, dest);

        if (!fs.existsSync(sourcePath)) {
            console.warn(`Warning: ${source} not found, skipping...`);
            errorCount++;
            continue;
        }

        try {
            fs.copyFileSync(sourcePath, destPath);
            console.log(`Copied: ${source} -> ${dest}`);
            successCount++;
        } catch (error) {
            console.error(`Error copying ${source}: ${error.message}`);
            errorCount++;
        }
    }

    console.log("");
    console.log("=".repeat(40));
    console.log(`Sync complete: ${successCount} succeeded, ${errorCount} failed`);
    console.log("=".repeat(40));

    if (successCount > 0) {
        console.log("");
        console.log("Frontend ABI files updated:");
        for (const dest of Object.values(ABI_MAP)) {
            const destPath = path.join(FRONTEND_PATH, dest);
            if (fs.existsSync(destPath)) {
                console.log(`  - ${destPath}`);
            }
        }
        console.log("");
        console.log("Remember to update your .env with the new contract addresses!");
    }

    process.exit(errorCount > 0 ? 1 : 0);
}

main();
