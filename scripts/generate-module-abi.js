import hre from "hardhat";
import fs from "fs";
import path from "path";

const moduleName = process.argv[2];
if (!moduleName) {
    console.error("Usage: node generate-module-abi.js <ModuleName>");
    process.exit(1);
}

async function main() {
    const artifact = await hre.artifacts.readArtifact(moduleName);
    
    const abiData = {
        contractName: moduleName,
        abi: artifact.abi
    };
    
    const deploymentsDir = "./deployments";
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const abiFile = path.join(deploymentsDir, `${moduleName}-ABI.json`);
    fs.writeFileSync(abiFile, JSON.stringify(abiData, null, 2));
    console.log(`✅ ${moduleName} ABI saved: ${abiFile}`);
}

main().catch(error => {
    console.error(error);
    process.exit(1);
});
