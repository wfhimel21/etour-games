import hre from "hardhat";

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer:", deployer.address);
    
    // Just check owner after deployment
    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const ETour_Core = await hre.ethers.getContractFactory("contracts/modules/ETour_Core.sol:ETour_Core");
    
    const moduleCore = await ETour_Core.deploy();
    await moduleCore.waitForDeployment();
    
    const game = await TicTacChain.deploy(
        await moduleCore.getAddress(),
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress,
        hre.ethers.ZeroAddress
    );
    await game.waitForDeployment();
    
    const owner = await game.owner();
    console.log("Game owner:", owner);
    console.log("Match?", owner === deployer.address);
}

main().catch(console.error);
