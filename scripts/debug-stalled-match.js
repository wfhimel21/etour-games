// Debug script to check why a stalled match can't be replaced
// Usage: node scripts/debug-stalled-match.js <tierId> <instanceId> <roundNumber> <matchNumber>

import hre from "hardhat";

async function main() {
    const args = process.argv.slice(2);

    if (args.length < 4) {
        console.log("Usage: npx hardhat run scripts/debug-stalled-match.js --network <network> -- <tierId> <instanceId> <roundNumber> <matchNumber>");
        console.log("Example: npx hardhat run scripts/debug-stalled-match.js --network localhost -- 0 0 0 0");
        process.exit(1);
    }

    const tierId = parseInt(args[0]);
    const instanceId = parseInt(args[1]);
    const roundNumber = parseInt(args[2]);
    const matchNumber = parseInt(args[3]);

    // Get contract address from deployments or user input
    const contractAddress = process.env.CONTRACT_ADDRESS || args[4];
    if (!contractAddress) {
        console.log("Please set CONTRACT_ADDRESS environment variable or pass as 5th argument");
        process.exit(1);
    }

    const TicTacChain = await hre.ethers.getContractFactory("TicTacChain");
    const game = TicTacChain.attach(contractAddress);

    console.log("\n=== Stalled Match Debugger ===\n");
    console.log(`Contract: ${contractAddress}`);
    console.log(`Match: Tier ${tierId}, Instance ${instanceId}, Round ${roundNumber}, Match ${matchNumber}\n`);

    // 1. Get match data
    const match = await game.getMatch(tierId, instanceId, roundNumber, matchNumber);
    console.log("--- Match State ---");
    console.log(`Player 1: ${match.common.player1}`);
    console.log(`Player 2: ${match.common.player2}`);
    console.log(`Current Turn: ${match.currentTurn}`);
    console.log(`Status: ${match.common.status} (0=NotStarted, 1=InProgress, 2=Completed)`);
    console.log(`Start Time: ${new Date(Number(match.common.startTime) * 1000).toISOString()}`);
    console.log(`Last Move Time: ${new Date(Number(match.common.lastMoveTime) * 1000).toISOString()}`);
    console.log(`Player 1 Time Remaining: ${match.player1TimeRemaining} seconds`);
    console.log(`Player 2 Time Remaining: ${match.player2TimeRemaining} seconds`);

    const now = Math.floor(Date.now() / 1000);
    const timeSinceLastMove = now - Number(match.common.lastMoveTime);
    console.log(`\nTime since last move: ${timeSinceLastMove} seconds (${Math.floor(timeSinceLastMove / 60)} minutes)`);

    // 2. Get tier config
    const tierConfig = await game.tierConfigs(tierId);
    console.log("\n--- Tier Config ---");
    console.log(`Player Count: ${tierConfig.playerCount}`);
    console.log(`Timeout Config:`);
    console.log(`  Match Time Per Player: ${tierConfig.timeouts.matchTimePerPlayer} seconds`);
    console.log(`  Match L2 Delay: ${tierConfig.timeouts.matchLevel2Delay} seconds`);
    console.log(`  Match L3 Delay: ${tierConfig.timeouts.matchLevel3Delay} seconds`);
    console.log(`  Enrollment Window: ${tierConfig.timeouts.enrollmentWindow} seconds`);
    console.log(`  Enrollment L2 Delay: ${tierConfig.timeouts.enrollmentLevel2Delay} seconds`);

    // 4. Calculate if player should be timed out
    let currentPlayerTimeRemaining;
    if (match.currentTurn === match.common.player1) {
        currentPlayerTimeRemaining = match.player1TimeRemaining;
        console.log(`Current player (Player 1) has ${currentPlayerTimeRemaining} seconds remaining`);
    } else {
        currentPlayerTimeRemaining = match.player2TimeRemaining;
        console.log(`Current player (Player 2) has ${currentPlayerTimeRemaining} seconds remaining`);
    }

    const hasTimedOut = timeSinceLastMove >= currentPlayerTimeRemaining;
    console.log(`Has current player timed out? ${hasTimedOut}`);

    if (hasTimedOut) {
        const timeoutOccurredAt = Number(match.common.lastMoveTime) + Number(currentPlayerTimeRemaining);
        const timeSinceTimeout = now - timeoutOccurredAt;
        console.log(`Timeout occurred at: ${new Date(timeoutOccurredAt * 1000).toISOString()}`);
        console.log(`Time since timeout: ${timeSinceTimeout} seconds (${Math.floor(timeSinceTimeout / 60)} minutes)`);

        const escalation1Start = timeoutOccurredAt + Number(tierConfig.timeouts.matchLevel2Delay);
        const escalation2Start = timeoutOccurredAt + Number(tierConfig.timeouts.matchLevel3Delay);

        console.log(`\n--- Escalation Timeline ---`);
        console.log(`Level 2 starts: ${new Date(escalation1Start * 1000).toISOString()} (${escalation1Start > now ? 'NOT YET' : 'ACTIVE'})`);
        console.log(`Level 3 starts: ${new Date(escalation2Start * 1000).toISOString()} (${escalation2Start > now ? 'NOT YET' : 'ACTIVE'})`);

        if (now >= escalation2Start) {
            console.log(`\n✅ Level 3 SHOULD be active - anyone can replace!`);
        } else if (now >= escalation1Start) {
            console.log(`\n⏳ Level 2 is active - advanced players can force eliminate`);
            console.log(`   Level 3 in ${escalation2Start - now} seconds`);
        } else {
            console.log(`\n⏳ Waiting for escalation...`);
            console.log(`   Level 2 in ${escalation1Start - now} seconds`);
        }
    } else {
        console.log(`\n⏳ Current player has NOT timed out yet`);
        console.log(`   Will timeout in ${Number(currentPlayerTimeRemaining) - timeSinceLastMove} seconds`);
    }

    // 5. Check timeout state
    const matchId = await game.getMatchId(tierId, instanceId, roundNumber, matchNumber);
    console.log(`\n--- Match Timeout State ---`);
    console.log(`Match ID: ${matchId}`);

    try {
        const timeoutState = await game.matchTimeouts(matchId);
        console.log(`Is Stalled: ${timeoutState.isStalled}`);
        console.log(`Escalation 1 Start: ${new Date(Number(timeoutState.escalation1Start) * 1000).toISOString()}`);
        console.log(`Escalation 2 Start: ${new Date(Number(timeoutState.escalation2Start) * 1000).toISOString()}`);
        console.log(`Active Escalation Level: ${timeoutState.activeEscalation}`);

        if (timeoutState.isStalled) {
            if (now >= Number(timeoutState.escalation2Start)) {
                console.log(`\n✅ Match IS marked as stalled and Level 3 IS active`);
                console.log(`   You should be able to call claimMatchSlotByReplacement()`);
            } else if (now >= Number(timeoutState.escalation1Start)) {
                console.log(`\n⚠️ Match IS stalled but only Level 2 is active`);
                console.log(`   Wait ${Number(timeoutState.escalation2Start) - now} more seconds for Level 3`);
            } else {
                console.log(`\n⚠️ Match IS stalled but escalation windows not reached yet`);
            }
        } else {
            console.log(`\n❌ Match is NOT marked as stalled yet`);
            console.log(`   The escalation functions will call _checkAndMarkStalled() automatically`);
            console.log(`   Try calling claimMatchSlotByReplacement() and it should auto-detect`);
        }
    } catch (error) {
        console.log(`Error reading timeout state: ${error.message}`);
    }

    // 6. Suggest action
    console.log("\n=== Recommendation ===");
    if (match.common.status !== 1) {
        console.log("❌ Match is not in progress - cannot be replaced");
    } else if (!hasTimedOut) {
        console.log("⏳ Wait for current player to timeout first");
    } else {
        const timeoutOccurredAt = Number(match.common.lastMoveTime) + Number(currentPlayerTimeRemaining);
        const escalation2Start = timeoutOccurredAt + Number(tierConfig.timeouts.matchLevel3Delay);

        if (now >= escalation2Start) {
            console.log("✅ Try calling: claimMatchSlotByReplacement(tierId, instanceId, roundNumber, matchNumber)");
            console.log("   This should work!");
        } else {
            const waitTime = escalation2Start - now;
            console.log(`⏳ Wait ${waitTime} seconds (${Math.floor(waitTime / 60)} minutes) before calling claimMatchSlotByReplacement()`);
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
