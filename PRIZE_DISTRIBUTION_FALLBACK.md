# Prize Distribution Failure Fallback System

## Overview

This document describes the safeguard mechanism implemented to handle prize distribution failures without stalling tournaments or losing funds.

## Problem Statement

When a prize is distributed to a winner's address, the transfer could fail for several reasons:
- Recipient is a contract that rejects ETH transfers
- Recipient contract reverts in its `receive()` or `fallback()` function
- Recipient address is invalid or unreachable

Without proper handling, a failed prize transfer would cause the entire tournament to revert and become stuck in an unresolvable state.

## Solution: Single-Attempt with Fallback

### Implementation Details

**File:** `contracts/ETour.sol`

#### 1. State Variable
```solidity
uint256 public accumulatedProtocolShare;
```
Tracks the total amount of prizes that failed to be distributed, added to the protocol pool.

#### 2. Events
```solidity
event PrizeDistributed(uint8 indexed tierId, uint8 indexed instanceId, address indexed player, uint8 rank, uint256 amount);
event PrizeDistributionFailed(uint8 indexed tierId, uint8 indexed instanceId, address indexed player, uint256 amount, uint8 attemptsMade);
event PrizeFallbackToContract(address indexed player, uint256 amount);
```

- `PrizeDistributed`: Emitted when prize is successfully sent
- `PrizeDistributionFailed`: Emitted when prize send fails
- `PrizeFallbackToContract`: Emitted when failed amount is kept in contract

#### 3. Core Function: `_sendPrizeWithFallback()`

```solidity
function _sendPrizeWithFallback(
    address recipient,
    uint256 amount,
    uint8 tierId,
    uint8 instanceId
) internal returns (bool success)
```

**Behavior:**
1. Attempts to send prize **once** (no retries)
2. If successful: returns `true`
3. If failed:
   - Adds amount to `accumulatedProtocolShare`
   - Emits failure events
   - Returns `false`
   - **Tournament continues** (does not revert)

#### 4. Integration Points

The fallback mechanism is integrated at all prize distribution points:

**A. Regular Prize Distribution** (`_distributePrizes`)
```solidity
bool sent = _sendPrizeWithFallback(player, prizeAmount, tierId, instanceId);
if (sent) {
    emit PrizeDistributed(tierId, instanceId, player, ranking, prizeAmount);
}
```

**B. Equal Prize Distribution** (`_distributeEqualPrizes`)
```solidity
bool sent = _sendPrizeWithFallback(player, prizePerPlayer, tierId, instanceId);
if (sent) {
    emit PrizeDistributed(tierId, instanceId, player, 1, prizePerPlayer);
}
```

**C. Solo Winner Payout**
```solidity
bool sent = _sendPrizeWithFallback(soloWinner, winnersPot, tierId, instanceId);
if (sent) {
    emit PrizeDistributed(tierId, instanceId, soloWinner, 1, winnersPot);
}
```

## Key Features

### ✅ Tournament Continues
Even if prize distribution fails, the tournament completes successfully and resets for the next round.

### ✅ No Funds Lost
Failed prize amounts are tracked in `accumulatedProtocolShare` and remain in the contract balance.

### ✅ No Owner Privileges
There is **no special withdrawal function** for the owner. Failed prizes remain in the contract permanently, maintaining the principle of no special access.

### ✅ Full Transparency
All failed distributions are logged via events:
```javascript
// Example event data
PrizeDistributionFailed {
    tierId: 0,
    instanceId: 0,
    player: "0x123...",
    amount: "1000000000000000", // 0.001 ETH
    attemptsMade: 1
}

PrizeFallbackToContract {
    player: "0x123...",
    amount: "1000000000000000"
}
```

### ✅ Single Attempt
As requested, the system only attempts to send the prize **once**. No retry loops that could waste gas or complicate the logic.

## Testing

### Test File
`test/PrizeDistributionFailureFallback.test.js`

### Helper Contract
`contracts/test-helpers/RejectingReceiver.sol`

A contract that rejects all ETH transfers, used to simulate prize distribution failures in tests.

```solidity
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: I reject your ETH!");
    }
}
```

### Test Coverage

1. **Normal Prize Distribution**
   - Verify prizes are sent successfully to normal addresses
   - Confirm `PrizeDistributed` events are emitted

2. **Failed Prize Distribution**
   - Simulate rejecting recipient
   - Verify `PrizeDistributionFailed` and `PrizeFallbackToContract` events
   - Confirm `accumulatedProtocolShare` increases

3. **Tournament Completion**
   - Verify tournament completes even with failed prizes
   - Confirm tournament resets for next round
   - Check contract balance remains correct

4. **Multi-Player Scenarios**
   - Test 4-player tournaments with mixed outcomes
   - Verify partial failures don't affect successful distributions

## Example Scenarios

### Scenario 1: Normal Operation
```
Tournament completes
├─ Winner gets 0.0018 ETH ✓
├─ Prize sent successfully ✓
├─ PrizeDistributed event emitted ✓
└─ accumulatedProtocolShare = 0
```

### Scenario 2: Failed Distribution
```
Tournament completes
├─ Winner is rejecting contract
├─ Prize send fails ✗
├─ Amount added to accumulatedProtocolShare ✓
├─ PrizeDistributionFailed event emitted ✓
├─ PrizeFallbackToContract event emitted ✓
└─ Tournament completes anyway ✓
```

### Scenario 3: Mixed Results (4-player)
```
Tournament completes
├─ 1st place (0.0012 ETH) → Sent successfully ✓
├─ 2nd place (0.0006 ETH) → Failed, added to fees ✗
├─ 3rd place (0.0000 ETH) → No prize
├─ 4th place (0.0000 ETH) → No prize
└─ Tournament completes and resets ✓
```

## Security Considerations

### ✅ No Reentrancy Risk
- Uses `call{value:}` with no gas stipulation
- Tournament state is finalized before prize distribution
- ReentrancyGuard on external functions

### ✅ CEI Pattern
The Checks-Effects-Interactions pattern is maintained:
1. **Check**: Validate amount > 0
2. **Effect**: Add to `accumulatedProtocolShare` if failed
3. **Interaction**: Attempt to send prize

### ✅ No Owner Privileges
- No special withdrawal function
- Failed prizes remain in contract permanently
- Maintains trustless design

### ✅ Gas Efficiency
- Single attempt (no retry loops)
- Minimal gas overhead for fallback
- Events provide full audit trail

## Contract Balance Accounting

The contract balance consists of:
1. **In-flight tournament prize pools** (awaiting completion)
2. **Accumulated failed prizes** (`accumulatedProtocolShare`)

Formula:
```
Contract Balance = Active Prize Pools + accumulatedProtocolShare
```

## Monitoring & Analytics

### Query Accumulated Fees
```javascript
const accumulated = await game.accumulatedProtocolShare();
console.log(`Failed prizes: ${ethers.formatEther(accumulated)} ETH`);
```

### Listen for Failed Distributions
```javascript
game.on("PrizeDistributionFailed", (tierId, instanceId, player, amount, attempts) => {
    console.log(`Prize distribution failed!`);
    console.log(`Player: ${player}`);
    console.log(`Amount: ${ethers.formatEther(amount)} ETH`);
    console.log(`Tier/Instance: ${tierId}/${instanceId}`);
});
```

### Track Fallback Events
```javascript
game.on("PrizeFallbackToContract", (player, amount) => {
    console.log(`Prize kept in contract for ${player}: ${ethers.formatEther(amount)} ETH`);
});
```

## Deployment Considerations

### Mainnet Deployment
The fallback mechanism is production-ready and:
- Does not introduce new attack vectors
- Maintains contract trustlessness
- Ensures tournament continuity
- Provides full transparency via events

### Gas Costs
The fallback adds minimal gas overhead:
- **Successful send**: No additional cost
- **Failed send**: ~20,000 gas (SSTORE for `accumulatedProtocolShare` + events)

This is negligible compared to the overall tournament completion gas cost.

## Migration Notes

### Existing Contracts
If upgrading from a previous version:
1. The new `accumulatedProtocolShare` variable initializes to 0
2. No migration required for existing tournaments
3. All new prize distributions will use the fallback mechanism

### Breaking Changes
None. The changes are backward compatible:
- New internal function (`_sendPrizeWithFallback`)
- New events (optional to listen to)
- New state variable (defaults to 0)

## Conclusion

The prize distribution fallback system provides a robust solution to handle edge cases where recipients cannot or will not accept prizes. By keeping failed prizes in the contract without owner privileges, the system maintains its trustless nature while ensuring tournaments never get stuck in an unresolvable state.

**Key Principle:** Tournament continuity takes priority over guaranteed prize delivery, with full transparency via events and permanent fund preservation in the contract.
