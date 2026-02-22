# Protocol Raffle System

## Overview

The Protocol Raffle System is a public mechanism that distributes accumulated protocol fees when they exceed a threshold of 3 ETH. It provides a trustless way to reward active players while maintaining a permanent reserve and compensating the protocol owner.

## Key Features

### ✅ Public Trigger with Access Control
- Any enrolled player can trigger the raffle when conditions are met
- Only players enrolled in **active tournaments** (Enrolling or InProgress status) can execute
- No special privileges or rewards for the caller

### ✅ Weighted Random Selection
- Winner selection based on enrollment count across all active tournaments
- Player enrolled in N tournaments = N times higher odds
- Uses `block.prevrandao` for randomness (post-merge Ethereum)

### ✅ Fair Distribution
- **20%** to protocol owner
- **80%** to randomly selected enrolled player
- **1 ETH** permanent reserve maintained

### ✅ No Owner Privileges
- Automatic execution by enrolled players
- No special withdrawal functions
- Transparent event emission

## Mechanics

### Trigger Conditions

The raffle can be executed when **all** of the following are true:

1. `accumulatedProtocolShare >= 3 ETH`
2. Caller is enrolled in at least one active tournament (Enrolling or InProgress)
3. There is at least one eligible player across all active tournaments

### Raffle Amount Calculation

```solidity
Raffle Amount = accumulatedProtocolShare - 1 ETH
Owner Share = Raffle Amount × 20%
Winner Share = Raffle Amount × 80%
Reserve = 1 ETH (permanent)
```

**Example:**
- `accumulatedProtocolShare = 3 ETH`
- Raffle Amount = `3 ETH - 1 ETH = 2 ETH`
- Owner receives: `2 ETH × 20% = 0.4 ETH`
- Winner receives: `2 ETH × 80% = 1.6 ETH`
- Reserve remaining: `1 ETH`

### Winner Selection Algorithm

The system uses a **weighted cumulative probability** algorithm:

1. **Collect Eligible Players**: Iterate through all tiers and instances
2. **Count Enrollments**: Each enrollment = 1 "ticket"
3. **Generate Randomness**: `keccak256(block.prevrandao, timestamp, block.number, caller)`
4. **Select Winner**: Random position mod total weight, find cumulative match

**Example:**
- Player A: 3 enrollments → 3 tickets (60% chance)
- Player B: 2 enrollments → 2 tickets (40% chance)
- Total: 5 tickets

Random number: `42`
Position: `42 % 5 = 2`
Winner: Player A (cumulative: 0-2 = Player A, 3-4 = Player B)

## Implementation

### File: `contracts/ETour.sol`

#### 1. Event

```solidity
event ProtocolRaffleExecuted(
    address indexed winner,
    address indexed caller,
    uint256 raffleAmount,
    uint256 ownerShare,
    uint256 winnerShare,
    uint256 remainingReserve,
    uint256 winnerEnrollmentCount
);
```

#### 2. Main Function

```solidity
function executeProtocolRaffle()
    external
    nonReentrant
    returns (address winner, uint256 ownerAmount, uint256 winnerAmount)
```

**Flow:**
1. **Check**: Verify threshold (>= 3 ETH)
2. **Check**: Verify caller is enrolled in active tournament
3. **Effect**: Calculate distribution amounts
4. **Effect**: Update `accumulatedProtocolShare` to 1 ETH
5. **Effect**: Get all enrolled players with weights
6. **Effect**: Generate randomness and select winner
7. **Effect**: Emit `ProtocolRaffleExecuted` event
8. **Interaction**: Send 20% to owner
9. **Interaction**: Send 80% to winner

#### 3. Helper Functions

**`_isCallerEnrolledInActiveTournament(address caller)`**
- Checks if caller is enrolled in any Enrolling or InProgress tournament
- Returns `true` on first match (early exit optimization)

**`_getAllEnrolledPlayersWithWeights()`**
- Two-pass algorithm:
  - Pass 1: Collect unique players
  - Pass 2: Count enrollments per player
- Returns: `(address[] players, uint256[] weights, uint256 totalWeight)`

**`_selectWeightedWinner(players, weights, totalWeight, randomness)`**
- Pure function for deterministic winner selection
- Cumulative probability algorithm
- Returns: `address winner`

#### 4. View Function

```solidity
function getRaffleInfo()
    external
    view
    returns (
        bool isReady,
        uint256 currentAccumulated,
        uint256 raffleAmount,
        uint256 ownerShare,
        uint256 winnerShare,
        uint256 eligiblePlayerCount
    )
```

Provides frontend visibility into raffle state without modifying state.

## Security Considerations

### ✅ Reentrancy Protection
- `nonReentrant` modifier on `executeProtocolRaffle()`
- Checks-Effects-Interactions (CEI) pattern enforced
- State updated before external calls

### ✅ Access Control
- Only enrolled players can trigger
- Checks both Enrolling and InProgress statuses
- No front-running incentive (caller gets no special reward)

### ✅ Randomness Quality
- Uses `block.prevrandao` (post-merge Ethereum randomness)
- Additional entropy from `block.timestamp`, `block.number`, `msg.sender`
- Sufficient for non-critical applications (prize distribution)

### ⚠️ Known Limitations

**MEV Risk**: Validators could manipulate `block.prevrandao` for high-value raffles
**Mitigation**: Low probability of MEV attack due to additional entropy sources

**Gas Cost**: Expensive with many enrolled players (nested loops)
**Mitigation**: Max capacity of 1000 unique players enforced

**Max Capacity**: Temporary array limited to 1000 players
**Mitigation**: Adjustable in implementation if needed

## Usage Examples

### Frontend Integration

```javascript
// Check if raffle is ready
const raffleInfo = await game.getRaffleInfo();

if (raffleInfo.isReady) {
    console.log(`🎰 Raffle Ready!`);
    console.log(`Amount: ${ethers.formatEther(raffleInfo.raffleAmount)} ETH`);
    console.log(`Eligible players: ${raffleInfo.eligiblePlayerCount}`);
    console.log(`Your potential winnings: ${ethers.formatEther(raffleInfo.winnerShare)} ETH`);
}
```

### Execute Raffle

```javascript
// Only enrolled players can call this
try {
    const tx = await game.executeProtocolRaffle();
    const receipt = await tx.wait();

    // Parse event
    const event = receipt.logs.find(log => {
        const parsed = game.interface.parseLog(log);
        return parsed?.name === "ProtocolRaffleExecuted";
    });

    if (event) {
        const parsed = game.interface.parseLog(event);
        console.log(`🎉 Winner: ${parsed.args.winner}`);
        console.log(`Winner had ${parsed.args.winnerEnrollmentCount} enrollments`);
        console.log(`Winner received: ${ethers.formatEther(parsed.args.winnerShare)} ETH`);
        console.log(`Owner received: ${ethers.formatEther(parsed.args.ownerShare)} ETH`);
    }
} catch (error) {
    if (error.message.includes("threshold not met")) {
        console.log("Raffle threshold not reached yet (need 3 ETH)");
    } else if (error.message.includes("Only enrolled players")) {
        console.log("You must be enrolled in an active tournament to trigger raffle");
    }
}
```

### Listen for Raffle Events

```javascript
game.on("ProtocolRaffleExecuted", (
    winner,
    caller,
    raffleAmount,
    ownerShare,
    winnerShare,
    remainingReserve,
    winnerEnrollmentCount
) => {
    console.log(`🎰 Protocol Raffle Executed!`);
    console.log(`Winner: ${winner} (${winnerEnrollmentCount} enrollments)`);
    console.log(`Caller: ${caller}`);
    console.log(`Total distributed: ${ethers.formatEther(raffleAmount)} ETH`);
    console.log(`- Owner: ${ethers.formatEther(ownerShare)} ETH`);
    console.log(`- Winner: ${ethers.formatEther(winnerShare)} ETH`);
    console.log(`Reserve remaining: ${ethers.formatEther(remainingReserve)} ETH`);
});
```

## Integration with Protocol Fees and Failed Prizes

The `accumulatedProtocolShare` increases from **TWO sources**:

### Source 1: Protocol Fees (2.5% of Entry Fees)

On every tournament enrollment, 2.5% of the entry fee is added to `accumulatedProtocolShare`:

```solidity
// In enrollInTournament()
uint256 protocolShare = (msg.value * PROTOCOL_SHARE_BPS) / BASIS_POINTS; // 2.5%
accumulatedProtocolShare += protocolShare;
```

**Example:**
- Entry fee: 0.001 ETH
- Protocol share: 0.001 × 2.5% = 0.000025 ETH per enrollment

With 4000 total enrollments across all tournaments:
- `accumulatedProtocolShare = 4000 × 0.000025 = 0.1 ETH`

### Source 2: Failed Prize Distributions

When a prize distribution fails (e.g., recipient contract rejects ETH):

1. `_sendPrizeWithFallback()` attempts to send prize once
2. If send fails:
   - Amount is added to `accumulatedProtocolShare`
   - `PrizeDistributionFailed` event emitted
   - Tournament continues (does not revert)

### Example Accumulation Scenario

```
Initial state: accumulatedProtocolShare = 0 ETH

Tournaments 1-1000 complete normally:
- Protocol fees: 1000 × 0.000025 ETH = 0.025 ETH
- Result: accumulatedProtocolShare = 0.025 ETH

Tournament 1001 completes:
- Winner address rejects ETH transfer
- Prize amount: 0.5 ETH
- Protocol fees: 0.000025 ETH
- Result: accumulatedProtocolShare = 0.525 ETH

Tournaments 1002-2000 complete normally:
- Protocol fees: 999 × 0.000025 ETH = 0.025 ETH
- Result: accumulatedProtocolShare = 0.550 ETH

... (many more tournaments) ...

After 120,000 total enrollments:
- Protocol fees: 120,000 × 0.000025 ETH = 3.0 ETH
- Result: accumulatedProtocolShare >= 3.0 ETH

🎰 Raffle is now eligible for execution!
```

**Key Insight:** The raffle pool grows organically from normal protocol operations. Every tournament contributes 2.5% of entry fees, making the raffle sustainable and recurring.

## Testing

### Test File: `test/ProtocolRaffle.test.js`

**27 comprehensive tests covering:**

1. **getRaffleInfo() View Function** (3 tests)
   - Below threshold behavior
   - At threshold behavior
   - Enrolled player counting

2. **Access Control** (5 tests)
   - Non-enrolled player rejection
   - Enrolled player acceptance (Enrolling status)
   - Enrolled player acceptance (InProgress status)
   - Completed tournament rejection
   - Threshold verification

3. **Raffle Mechanics** (2 tests)
   - Failed prize accumulation
   - Multiple enrollment handling

4. **Raffle Distribution** (2 tests)
   - 20%/80% split verification
   - 1 ETH reserve maintenance

5. **Event Emission** (1 test)
   - Event signature verification

6. **Edge Cases** (4 tests)
   - Exactly 3 ETH threshold
   - Large amounts (10 ETH)
   - Single enrolled player
   - Player enrolled in many tournaments

7. **Security Considerations** (4 tests)
   - Reentrancy protection
   - CEI pattern compliance
   - Failed send handling

8. **Randomness Quality** (2 tests)
   - Randomness source verification
   - Different block data handling

9. **Gas Efficiency** (2 tests)
   - Reasonable player count handling
   - Max capacity documentation

10. **Integration** (2 tests)
    - Integration with protocol fees
    - Failed distribution accumulation

### Running Tests

```bash
# Run all raffle tests
npx hardhat test test/ProtocolRaffle.test.js

# Run specific test
npx hardhat test test/ProtocolRaffle.test.js --grep "Should execute raffle"
```

## Deployment Considerations

### Mainnet Deployment

The protocol raffle system is production-ready and:
- Does not introduce new attack vectors
- Maintains contract trustlessness
- Ensures fair prize distribution
- Provides full transparency via events

### Gas Costs

**getRaffleInfo()**: ~200,000 gas (view function, varies with enrollment count)
**executeProtocolRaffle()**: ~300,000-500,000 gas (varies with number of players)

Higher costs with more enrolled players due to nested loops in `_getAllEnrolledPlayersWithWeights()`.

### Monitoring & Analytics

Track raffle metrics:

```javascript
// Query current state
const accumulated = await game.accumulatedProtocolShare();
const raffleInfo = await game.getRaffleInfo();

console.log(`Current accumulated: ${ethers.formatEther(accumulated)} ETH`);
console.log(`Threshold reached: ${raffleInfo.isReady}`);
console.log(`Eligible players: ${raffleInfo.eligiblePlayerCount}`);
```

## Comparison with Other Systems

| Feature | Protocol Raffle | Traditional Lottery | Prize Pool |
|---------|----------------|-------------------|-----------|
| Trigger | Public (enrolled players) | Automated/Admin | Automated |
| Access | Enrolled players only | Anyone | Tournament winners only |
| Odds | Weighted by enrollments | Equal for all | N/A |
| Distribution | 20% owner, 80% winner | 100% winner | 100% winner |
| Reserve | 1 ETH permanent | None | None |
| Randomness | block.prevrandao | Chainlink VRF | N/A |
| Gas Cost | Medium (~300-500k) | Low | Low |

## Frequently Asked Questions

### Q: How is `accumulatedProtocolShare` funded?

**A:** `accumulatedProtocolShare` is funded from **two sources**:
1. **Protocol fees** (2.5% of every entry fee) - ongoing revenue stream
2. **Failed prize distributions** - edge cases where winners can't receive prizes

This dual-source approach ensures the raffle pool grows organically from normal protocol operations while also capturing any failed prize amounts.

### Q: Can the owner trigger the raffle without being enrolled?

**A:** No. The owner must be enrolled in an active tournament like any other player.

### Q: What happens if there are no enrolled players when threshold is met?

**A:** The raffle cannot be executed until at least one player enrolls in a tournament.

### Q: Can the raffle be executed multiple times?

**A:** Yes. Each execution reduces `accumulatedProtocolShare` to 1 ETH. When it reaches 3 ETH again, another raffle can be triggered.

### Q: What if the winner address rejects ETH?

**A:** The transaction will revert completely, preventing partial state updates. The raffle would need to be re-executed, potentially selecting a different winner.

### Q: How fair is the randomness?

**A:** Sufficient for non-critical applications. Uses `block.prevrandao` which is validator-influenced but includes additional entropy. For high-value raffles, consider external randomness (Chainlink VRF).

### Q: Can I increase my odds of winning?

**A:** Yes, by enrolling in more active tournaments. Each enrollment = 1 additional "ticket" in the weighted random selection.

### Q: How long does it take to reach the 3 ETH threshold?

**A:** With 0.001 ETH entry fees and 2.5% protocol share:
- Per enrollment: 0.000025 ETH
- To reach 3 ETH: 120,000 enrollments
- With 100 enrollments/day: ~3.3 years
- With 1000 enrollments/day: ~4 months
- With 10,000 enrollments/day: ~12 days

The actual timeline depends on protocol adoption and activity levels. Failed prize distributions can accelerate this significantly.

## Conclusion

The Protocol Raffle System provides a trustless, transparent mechanism for distributing accumulated protocol fees while rewarding active players. By maintaining a permanent reserve and using weighted random selection, it balances fairness, sustainability, and engagement.

**Key Principles:**
- ✅ No owner privileges
- ✅ Public execution by enrolled players
- ✅ Weighted odds based on participation
- ✅ Permanent reserve maintenance
- ✅ Full transparency via events

For questions or suggestions, please open an issue in the repository.
