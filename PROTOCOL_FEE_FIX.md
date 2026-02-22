# Critical Fix: Protocol Fee Accumulation

## Issue Identified

The initial implementation had a critical flaw where the 2.5% protocol fee from entry fees was being sent directly to the owner instead of accumulating in `accumulatedProtocolShare`.

### Before (Incorrect)

```solidity
// In enrollInTournament() - Line 542
(bool protocolSuccess, ) = payable(owner).call{value: protocolShare}("");
require(protocolSuccess, "Protocol fee transfer failed");
emit ProtocolFeePaid(owner, protocolShare);
```

**Problem:** Protocol fees were sent to owner immediately, never accumulating for the raffle system.

### After (Correct)

```solidity
// In enrollInTournament() - Line 542-544
// Add protocol share to accumulated pool for raffle system
accumulatedProtocolShare += protocolShare;
emit ProtocolFeePaid(address(this), protocolShare);
```

**Solution:** Protocol fees now accumulate in the contract for the raffle system.

## Corrected Behavior

`accumulatedProtocolShare` now increases from **TWO sources**:

### 1. Protocol Fees (Primary Source)
- **Amount**: 2.5% of every entry fee
- **Frequency**: Every tournament enrollment
- **Purpose**: Ongoing revenue stream for raffle pool

**Example:**
```
Entry fee: 0.001 ETH
Protocol share per enrollment: 0.000025 ETH

After 1,000 enrollments: 0.025 ETH
After 10,000 enrollments: 0.25 ETH
After 120,000 enrollments: 3.0 ETH ← Raffle threshold reached!
```

### 2. Failed Prize Distributions (Edge Cases)
- **Amount**: Full prize amount when distribution fails
- **Frequency**: Rare (only when recipient rejects ETH)
- **Purpose**: Prevents tournament stalling while preserving funds

**Example:**
```
Tournament completes with 0.9 ETH prize pool
Winner contract rejects ETH transfer
→ 0.9 ETH added to accumulatedProtocolShare
```

## Impact on Raffle Timeline

### Original (Incorrect) Implementation
- Only failed prizes accumulated
- Would take indefinitely long to reach 3 ETH threshold
- Raffle system would be effectively non-functional

### Corrected Implementation
- Protocol fees accumulate consistently
- Predictable timeline based on activity:
  - 100 enrollments/day → 3.3 years to 3 ETH
  - 1,000 enrollments/day → 4 months to 3 ETH
  - 10,000 enrollments/day → 12 days to 3 ETH

## Fee Distribution Breakdown

For each 0.001 ETH entry fee:

| Component | Percentage | Amount | Destination |
|-----------|-----------|--------|-------------|
| Prize Pool | 90.0% | 0.0009 ETH | Tournament prizes |
| Owner Fee | 7.5% | 0.000075 ETH | Owner (immediate) |
| Protocol Fee | 2.5% | 0.000025 ETH | `accumulatedProtocolShare` |
| **Total** | **100%** | **0.001 ETH** | |

## Raffle Mechanism

Once `accumulatedProtocolShare >= 3 ETH`:

1. Any enrolled player can trigger `executeProtocolRaffle()`
2. Raffle amount = `accumulatedProtocolShare - 1 ETH` (keep reserve)
3. Distribution:
   - Owner: 20% of raffle amount
   - Random enrolled player: 80% of raffle amount
4. Winner selection weighted by enrollment count
5. Reserve: 1 ETH permanently maintained

**Example:**
```
accumulatedProtocolShare = 3.0 ETH
Raffle amount = 3.0 - 1.0 = 2.0 ETH

Owner receives: 2.0 × 20% = 0.4 ETH
Winner receives: 2.0 × 80% = 1.6 ETH
Reserve remaining: 1.0 ETH
```

## Testing Updates

Updated tests to verify correct protocol fee accumulation:

### Test: "Should accumulate protocol share from entry fees (2.5%)"
```javascript
await game.connect(player1).enrollInTournament(tierId, instanceId, { value: TIER_0_FEE });
await game.connect(player2).enrollInTournament(tierId, instanceId, { value: TIER_0_FEE });

// PROTOCOL_SHARE_BPS = 250 basis points = 2.5%
const expectedProtocolShare = (TIER_0_FEE * 2n * 250n) / 10000n;

const accumulated = await game.accumulatedProtocolShare();
expect(accumulated).to.equal(expectedProtocolShare); // ✓ Passes
```

**Result:** All 27 raffle tests passing

## Documentation Updates

Updated files to reflect corrected behavior:
- ✅ `PROTOCOL_RAFFLE.md` - Updated accumulation mechanics
- ✅ `test/ProtocolRaffle.test.js` - Fixed calculations and expectations
- ✅ `contracts/ETour.sol` - Fixed protocol fee routing

## Summary

**Before:** Protocol fees sent to owner → Raffle pool never grows → System non-functional

**After:** Protocol fees accumulate in contract → Raffle pool grows with activity → System sustainable

This fix ensures the Protocol Raffle System works as intended, creating a sustainable mechanism for distributing protocol revenue while rewarding active players.
