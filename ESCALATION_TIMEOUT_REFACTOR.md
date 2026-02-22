# Escalation Timeout Standardization - Implementation Plan

## Overview
Make all escalation timeout windows configurable per tier and expose them via ABI so clients can accurately determine when escalation CTAs should appear.

## Current State
- Match time per player: Hardcoded in game contracts (2 min TicTacChain, 5 min Chess/C4)
- All escalation windows: Use single `enrollmentWindow` value
- Not all values exposed via ABI

## Proposed Changes

### 1. Add TimeoutConfig struct to ETour.sol

```solidity
/**
 * @dev Timeout configuration for escalation windows
 * All values in seconds
 */
struct TimeoutConfig {
    uint256 matchTimePerPlayer;           // Time each player gets for entire match (e.g., 60 = 1 minute)
    uint256 matchLevel2Delay;             // Delay after player timeout before L2 (advanced players) active
    uint256 matchLevel3Delay;             // Delay after player timeout before L3 (anyone) active
    uint256 enrollmentWindow;             // Time to wait for tournament to fill before L1
    uint256 enrollmentLevel2Delay;        // Delay after L1 before L2 (external claim) active
}
```

### 2. Update TierConfig to include TimeoutConfig

```solidity
struct TierConfig {
    uint8 playerCount;
    uint8 instanceCount;
    uint256 entryFee;
    Mode mode;
    TimeoutConfig timeouts;  // ← NEW: Nested timeout configuration
    uint8 totalRounds;
    bool initialized;
}
```

### 3. Update _registerTier() signature

```solidity
function _registerTier(
    uint8 tierId,
    uint8 playerCount,
    uint8 instanceCount,
    uint256 entryFee,
    Mode mode,
    TimeoutConfig memory timeouts,  // ← NEW parameter
    uint8[] memory prizeDistribution
) internal {
    // ... validation ...

    _tierConfigs[tierId] = TierConfig({
        playerCount: playerCount,
        instanceCount: instanceCount,
        entryFee: entryFee,
        mode: mode,
        timeouts: timeouts,  // ← Store timeout config
        totalRounds: _log2(playerCount),
        initialized: true
    });

    // ... rest of function ...
}
```

### 4. Update tierConfigs() public getter to expose all timeouts

```solidity
function tierConfigs(uint8 tierId) external view returns (
    uint8 playerCount,
    uint8 instanceCount,
    uint256 entryFee,
    uint8 totalRounds,
    TimeoutConfig memory timeouts  // ← Return entire timeout config
) {
    TierConfig storage config = _tierConfigs[tierId];
    return (
        config.playerCount,
        config.instanceCount,
        config.entryFee,
        config.totalRounds,
        config.timeouts
    );
}
```

### 5. Add convenience getter for timeout config only

```solidity
/**
 * @dev Get timeout configuration for a tier
 * Provides all escalation timing information to clients
 */
function getTimeoutConfig(uint8 tierId) external view returns (TimeoutConfig memory) {
    require(_tierConfigs[tierId].initialized, "Invalid tier");
    return _tierConfigs[tierId].timeouts;
}
```

### 6. Update _markMatchStalled() to use new config

```solidity
function _markMatchStalled(bytes32 matchId, uint8 tierId, uint256 timeoutOccurredAt) internal {
    MatchTimeoutState storage timeout = matchTimeouts[matchId];
    if (!timeout.isStalled) {
        timeout.isStalled = true;
        TierConfig storage config = _tierConfigs[tierId];

        uint256 baseTime = timeoutOccurredAt == 0 ? block.timestamp : timeoutOccurredAt;

        // Use tier-specific timeout configuration
        timeout.escalation1Start = baseTime + config.timeouts.matchLevel2Delay;
        timeout.escalation2Start = baseTime + config.timeouts.matchLevel3Delay;
        timeout.activeEscalation = EscalationLevel.None;
    }
}
```

### 7. Update enrollment timeout initialization

```solidity
// In enrollInTournament()
if (tournament.enrolledCount == 1) {
    tournament.firstEnroller = msg.sender;
    tournament.firstEnrollmentTimestamp = block.timestamp;

    TierConfig storage config = _tierConfigs[tierId];
    tournament.enrollmentTimeout.escalation1Start = block.timestamp + config.timeouts.enrollmentWindow;
    tournament.enrollmentTimeout.escalation2Start = tournament.enrollmentTimeout.escalation1Start + config.timeouts.enrollmentLevel2Delay;
    tournament.enrollmentTimeout.activeEscalation = EscalationLevel.None;
    tournament.enrollmentTimeout.forfeitPool = 0;
}
```

### 8. Remove _getMatchTimePerPlayer() abstract function

Since it's now in config, game contracts no longer need to implement it:

```solidity
// REMOVE from ETour.sol:
function _getMatchTimePerPlayer() internal view virtual returns (uint256);

// REMOVE from all game contracts (TicTacChain, ChessOnChain, ConnectFourOnChain):
function _getMatchTimePerPlayer() internal pure override returns (uint256) {
    return X minutes;
}
```

### 9. Update game contracts to pass timeout config during tier registration

**TicTacChain.sol constructor:**

```solidity
constructor() {
    // 1 minute for all escalation windows
    TimeoutConfig memory timeouts = TimeoutConfig({
        matchTimePerPlayer: 1 minutes,      // 60 seconds per player
        matchLevel2Delay: 1 minutes,        // L2 starts 1 min after timeout
        matchLevel3Delay: 2 minutes,        // L3 starts 2 min after timeout (cumulative)
        enrollmentWindow: 1 minutes,        // 1 min to fill tournament
        enrollmentLevel2Delay: 1 minutes    // L2 starts 1 min after L1
    });

    _registerTier(
        0,                    // tierId
        2,                    // playerCount
        64,                   // instanceCount
        0.001 ether,          // entryFee
        Mode.Demo,            // mode
        timeouts,             // ← NEW: Pass timeout config
        new uint8[](2)        // prizeDistribution
    );

    // ... register other tiers ...
}
```

### 10. Update _hasCurrentPlayerTimedOut() to use config

```solidity
function _hasCurrentPlayerTimedOut(bytes32 matchId, uint8 tierId) internal view returns (bool) {
    // Get match-specific data from game contract
    // ... existing logic to get currentPlayerTimeRemaining ...

    // No changes needed here - game contracts still track time banks
    // This function doesn't need the total match time
    return timeElapsed >= currentPlayerTimeRemaining;
}
```

### 11. Update _checkAndMarkStalled() to use config

```solidity
function _checkAndMarkStalled(
    bytes32 matchId,
    uint8 tierId,
    uint8 instanceId,
    uint8 roundNumber,
    uint8 matchNumber
) internal returns (bool) {
    // ... existing checks ...

    if (_hasCurrentPlayerTimedOut(matchId, tierId)) {
        CommonMatchData memory matchData = _getActiveMatchData(matchId, tierId, instanceId, roundNumber, matchNumber);
        TierConfig storage config = _tierConfigs[tierId];

        // Calculate when timeout occurred using tier config
        uint256 timeoutOccurredAt = matchData.lastMoveTime + config.timeouts.matchTimePerPlayer;

        _markMatchStalled(matchId, tierId, timeoutOccurredAt);
        return true;
    }

    return false;
}
```

## Client Usage Example

After these changes, clients can query all timing information:

```javascript
// Get timeout configuration for a tier
const timeoutConfig = await game.getTimeoutConfig(tierId);

console.log("Match time per player:", timeoutConfig.matchTimePerPlayer, "seconds");
console.log("Level 2 delay:", timeoutConfig.matchLevel2Delay, "seconds");
console.log("Level 3 delay:", timeoutConfig.matchLevel3Delay, "seconds");
console.log("Enrollment window:", timeoutConfig.enrollmentWindow, "seconds");
console.log("Enrollment L2 delay:", timeoutConfig.enrollmentLevel2Delay, "seconds");

// Calculate escalation availability
const match = await game.getMatch(tierId, instanceId, roundNumber, matchNumber);
const now = Math.floor(Date.now() / 1000);

// When does current player timeout?
const currentPlayerTime = (match.currentTurn === match.common.player1)
    ? match.player1TimeRemaining
    : match.player2TimeRemaining;
const playerTimesOutAt = match.common.lastMoveTime + currentPlayerTime;

if (now >= playerTimesOutAt) {
    // Player has timed out
    const level2StartsAt = playerTimesOutAt + timeoutConfig.matchLevel2Delay;
    const level3StartsAt = playerTimesOutAt + timeoutConfig.matchLevel3Delay;

    if (now >= level3StartsAt) {
        showReplaceButton(); // Anyone can replace
    } else if (now >= level2StartsAt) {
        if (isAdvancedPlayer) {
            showForceEliminateButton(); // Advanced players only
        }
    } else {
        showClaimTimeoutButton(); // Opponent can claim
    }
}
```

## Migration Notes

1. **Breaking change**: Contract deployments must provide TimeoutConfig
2. **ABI change**: tierConfigs() return signature changes
3. **Gas impact**: Minimal - just storing additional config values
4. **Backward compatibility**: None - requires redeployment

## Benefits

1. ✅ All timeout values configurable per tier
2. ✅ All values exposed via ABI
3. ✅ Clients can accurately calculate escalation availability
4. ✅ Different tiers can have different timeout strategies
5. ✅ Centralizes all timeout logic in ETour
6. ✅ Removes hardcoded values from game contracts
