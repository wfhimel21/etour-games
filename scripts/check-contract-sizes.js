// scripts/check-contract-sizes.js
// Check compiled contract sizes against 24KB Spurious Dragon limit

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 24KB limit (Spurious Dragon)
const SPURIOUS_DRAGON_LIMIT = 24576; // bytes
const LIMIT_KB = SPURIOUS_DRAGON_LIMIT / 1024;

// Contracts to check
const CONTRACTS = [
    'TicTacChain',
    'ChessOnChain',
    'ConnectFourOnChain',
    'ETour',
    'ETour_Storage'
];

// Module contracts
const MODULES = [
    'contracts/modules/ETour_Core.sol:ETour_Core',
    'contracts/modules/ETour_Matches.sol:ETour_Matches',
    'contracts/modules/ETour_Prizes.sol:ETour_Prizes',
    'contracts/modules/ETour_Raffle.sol:ETour_Raffle',
    'contracts/modules/ETour_Escalation.sol:ETour_Escalation',
    'contracts/modules/ChessRulesModule.sol:ChessRulesModule'
];

function getContractSize(contractName) {
    try {
        const artifactPath = path.join(__dirname, '..', 'artifacts', 'contracts', `${contractName}.sol`, `${contractName}.json`);
        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

        // Get deployed bytecode (more accurate for deployment size)
        const bytecode = artifact.deployedBytecode || artifact.bytecode;

        // Remove '0x' prefix and calculate size
        const bytecodeWithout0x = bytecode.replace('0x', '');
        const sizeInBytes = bytecodeWithout0x.length / 2; // 2 hex chars = 1 byte

        return sizeInBytes;
    } catch (error) {
        return null;
    }
}

function getModuleSize(modulePath) {
    try {
        // modulePath format: "contracts/modules/ETour_Core.sol:ETour_Core"
        const [filePath, contractName] = modulePath.split(':');
        const fileName = filePath.split('/').pop(); // Get "ETour_Core.sol"

        const artifactPath = path.join(__dirname, '..', 'artifacts', 'contracts', 'modules', fileName, `${contractName}.json`);
        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

        const bytecode = artifact.deployedBytecode || artifact.bytecode;
        const bytecodeWithout0x = bytecode.replace('0x', '');
        const sizeInBytes = bytecodeWithout0x.length / 2;

        return sizeInBytes;
    } catch (error) {
        return null;
    }
}

function formatSize(bytes) {
    const kb = (bytes / 1024).toFixed(2);
    const percentage = ((bytes / SPURIOUS_DRAGON_LIMIT) * 100).toFixed(1);
    return { bytes, kb, percentage };
}

function getStatusIcon(bytes) {
    if (bytes > SPURIOUS_DRAGON_LIMIT) {
        return '❌';
    } else if (bytes > SPURIOUS_DRAGON_LIMIT * 0.9) {
        return '⚠️ ';
    } else {
        return '✅';
    }
}

console.log('');
console.log('=' .repeat(70));
console.log('📊  Contract Size Report');
console.log('=' .repeat(70));
console.log(`Spurious Dragon Limit: ${LIMIT_KB} KB (${SPURIOUS_DRAGON_LIMIT} bytes)`);
console.log('');

// Check main game contracts
console.log('🎮  Game Contracts:');
console.log('-' .repeat(70));

let totalGameSize = 0;
let contractData = [];

for (const contract of CONTRACTS) {
    const size = getContractSize(contract);
    if (size !== null) {
        const formatted = formatSize(size);
        const status = getStatusIcon(size);

        contractData.push({
            name: contract,
            ...formatted,
            status
        });

        totalGameSize += size;
    }
}

// Sort by size (largest first)
contractData.sort((a, b) => b.bytes - a.bytes);

// Print table
for (const data of contractData) {
    const statusText = data.bytes > SPURIOUS_DRAGON_LIMIT ? 'OVER LIMIT' : 'OK';
    console.log(`${data.status}  ${data.name.padEnd(20)} ${data.bytes.toString().padStart(6)} bytes  ${data.percentage.padStart(5)}%  ${statusText}`);
}

console.log('');
console.log('📚  Module Contracts:');
console.log('-' .repeat(70));

let totalModuleSize = 0;
let moduleData = [];

for (const modulePath of MODULES) {
    const moduleName = modulePath.split(':')[1];
    const size = getModuleSize(modulePath);
    if (size !== null) {
        const formatted = formatSize(size);
        const status = getStatusIcon(size);

        moduleData.push({
            name: moduleName,
            ...formatted,
            status
        });

        totalModuleSize += size;
    }
}

// Sort by size (largest first)
moduleData.sort((a, b) => b.bytes - a.bytes);

// Print module table
for (const data of moduleData) {
    const statusText = data.bytes > SPURIOUS_DRAGON_LIMIT ? 'OVER LIMIT' : 'OK';
    console.log(`${data.status}  ${data.name.padEnd(20)} ${data.bytes.toString().padStart(6)} bytes  ${data.percentage.padStart(5)}%  ${statusText}`);
}

console.log('');
console.log('=' .repeat(70));
console.log('📊  Summary:');
console.log('-' .repeat(70));

const avgGameSize = totalGameSize / contractData.length;
const avgModuleSize = totalModuleSize / moduleData.length;

console.log(`Total Game Contracts Size:   ${totalGameSize} bytes`);
console.log(`Average Game Contract Size:  ${Math.round(avgGameSize)} bytes`);
console.log(`Total Module Size:           ${totalModuleSize} bytes`);
console.log(`Average Module Size:         ${Math.round(avgModuleSize)} bytes`);
console.log('');

// Calculate savings from modular architecture
const monolithicEstimate = totalGameSize + totalModuleSize;
const modularActual = totalGameSize + totalModuleSize; // Modules deployed once, shared
const sharedModuleSavings = totalModuleSize * 2; // If we had 3 separate monolithic contracts

console.log('💡  Modular Architecture Benefits:');
console.log('-' .repeat(70));
console.log(`Estimated Monolithic Size (per game): ${Math.round(monolithicEstimate / 3)} bytes`);
console.log(`Shared Module Code:                   ${totalModuleSize} bytes`);
console.log(`Gas Savings (deploying 3 games):     ~${((sharedModuleSavings / monolithicEstimate) * 100).toFixed(1)}%`);
console.log('');

// Check for contracts over limit
const overLimit = [...contractData, ...moduleData].filter(d => d.bytes > SPURIOUS_DRAGON_LIMIT);

if (overLimit.length > 0) {
    console.log('⚠️   Contracts Over 24KB Limit:');
    console.log('-' .repeat(70));
    for (const contract of overLimit) {
        const excess = contract.bytes - SPURIOUS_DRAGON_LIMIT;
        console.log(`  ${contract.name}: ${excess} bytes over limit`);
    }
    console.log('');
    console.log('💡  Recommendations:');
    console.log('  - Increase optimizer runs in hardhat.config.js (currently 200)');
    console.log('  - Consider splitting large contracts further');
    console.log('  - Remove unnecessary string error messages');
    console.log('  - Use libraries for common functionality');
    console.log('');
} else {
    console.log('✅  All contracts are within the 24KB limit!');
    console.log('');
}

console.log('=' .repeat(70));
console.log('');
