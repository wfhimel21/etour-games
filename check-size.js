const artifact = require('./artifacts/contracts/ChessOnChain.sol/ChessOnChain.json');

console.log('Artifact keys:', Object.keys(artifact));

if (artifact.bytecode) {
    // Remove 0x prefix if present
    const bytecode = artifact.bytecode.startsWith('0x')
        ? artifact.bytecode.slice(2)
        : artifact.bytecode;
    const size = bytecode.length / 2;
    console.log('\nCreation bytecode size:', size, 'bytes');
    console.log('Contract size limit: 24576 bytes');
    console.log('Over limit?', size > 24576 ? 'YES by ' + (size - 24576) + ' bytes' : 'NO');
}

if (artifact.deployedBytecode) {
    const bytecode = artifact.deployedBytecode.startsWith('0x')
        ? artifact.deployedBytecode.slice(2)
        : artifact.deployedBytecode;
    const size = bytecode.length / 2;
    console.log('\nDeployed bytecode size:', size, 'bytes');
    console.log('Over limit?', size > 24576 ? 'YES by ' + (size - 24576) + ' bytes' : 'NO');
}
