# ETour.sol Dead Code Analysis Report

**Generated**: 2025-12-30
**Analyzer**: Claude Code (Systematic Code Analysis)
**Target**: `/Users/karim/Documents/workspace/zero-trust/e-tour/contracts/ETour.sol` (2,600 lines)

---

## Executive Summary

- **Total elements analyzed**: ~200
- **Confirmed dead code**: **5 items** (1 enum + 4 struct fields)
- **Potentially underutilized**: **3 state variables**
- **Active & preserved**: **190+ elements** (95%+)
- **Analysis methodology**: 4-tier search (ETour internal, game contracts, tests, indirect usage)

---

## Methodology

### Search Tiers Applied:
1. **Tier 1**: Internal references within ETour.sol (grep analysis)
2. **Tier 2**: Implementing contracts (TicTacChain, ChessOnChain, ConnectFourOnChain)
3. **Tier 3**: Test files (27 test files, 330 passing tests)
4. **Tier 4**: Indirect usage patterns (events, off-chain indexing)

### Classification Criteria:
- ✅ **KEEP**: External/public API, abstract functions, virtual hooks, active internal code
- ⚠️ **REVIEW**: Underutilized variables, test-only code
- ❌ **DEAD CODE**: Zero functional references (written but never read, or completely unused)

---

## CONFIRMED DEAD CODE (Recommended for Removal)

### 1. TournamentCompletionType Enum (DEAD)

**Location**: Line 52-56
**Type**: Enum definition
**Status**: ❌ **DEAD CODE**

```solidity
enum TournamentCompletionType {
    Regular,       // Never used
    PartialStart,  // Never used
    Abandoned      // Never used
}
```

**Evidence**:
- **ETour.sol references**: 1 (declaration only)
- **Game contracts**: 0 references
- **Test files**: 0 references
- **Enum value usage**: NONE (Regular, PartialStart, Abandoned never assigned or checked)

**Note**: The word "Abandoned" appears in function names (`claimAbandonedEnrollmentPool`) but NOT as the enum value `TournamentCompletionType.Abandoned`.

**Recommendation**: ❌ **SAFE TO REMOVE** - This enum was likely planned for tracking tournament end states but never implemented.

---

### 2. TournamentInstance Struct Fields (4 DEAD FIELDS)

**Location**: Line 88-108
**Type**: Struct fields
**Status**: ❌ **DEAD CODE** (4 fields)

#### 2.1 `forceStarter` (address)

**Line**: 106
**References**: 2 (written once, deleted once)
- **Written**: Line 601 (`tournament.forceStarter = msg.sender;`)
- **Deleted**: Line 2144 (`tournament.forceStarter = address(0);`)
- **Read**: NEVER

**Status**: ❌ **DEAD - Set but never read**

---

#### 2.2 `forceStartTimestamp` (uint256)

**Line**: 107
**References**: 2 (written once, deleted once)
- **Written**: Line 602 (`tournament.forceStartTimestamp = block.timestamp;`)
- **Deleted**: Line 2145 (`tournament.forceStartTimestamp = 0;`)
- **Read**: NEVER

**Status**: ❌ **DEAD - Set but never read**

---

#### 2.3 `firstEnroller` (address)

**Line**: 104
**References**: 2 (written once, deleted once)
- **Written**: Line 546 (`tournament.firstEnroller = msg.sender;`)
- **Deleted**: Line 2142 (`tournament.firstEnroller = address(0);`)
- **Read**: NEVER

**Status**: ❌ **DEAD - Set but never read**

---

#### 2.4 `firstEnrollmentTimestamp` (uint256)

**Line**: 105
**References**: 3 (written twice, deleted once)
- **Written**: Line 547 (`tournament.firstEnrollmentTimestamp = block.timestamp;`)
- **Written**: Line 668 (reset in `resetEnrollmentWindow`)
- **Deleted**: Line 2143 (`tournament.firstEnrollmentTimestamp = 0;`)
- **Read**: NEVER

**Status**: ❌ **DEAD - Set but never read**

---

**Cumulative Impact of Dead Struct Fields**:
- **4 storage slots wasted per tournament instance**
- **Storage cost**: ~80,000 gas per tournament initialization (SSTORE from zero)
- **Cleanup cost**: ~15,000 gas per tournament reset (SSTORE to zero)
- **Recommendation**: ❌ **SAFE TO REMOVE ALL 4 FIELDS**

These fields represent abandoned tournament metadata tracking. They were likely intended for analytics or debugging but were never integrated into any query functions or business logic.

---

## POTENTIALLY UNDERUTILIZED CODE (Review Recommended)

### 3. State Variable: `_isOnLeaderboard`

**Location**: Line 203
**Type**: Internal mapping
**References**: 2 (minimal usage)

```solidity
mapping(address => bool) internal _isOnLeaderboard;
```

**Usage**:
- **Check**: Line 2115 (`if (!_isOnLeaderboard[player])`)
- **Set**: Line 2116 (`_isOnLeaderboard[player] = true;`)

**Status**: ⚠️ **POTENTIALLY REDUNDANT**

**Analysis**:
- Only used in `_trackOnLeaderboard()` to prevent duplicate entries in `_leaderboardPlayers` array
- This is a classic "guard mapping" pattern
- Alternative: Could check array membership directly or use different data structure

**Recommendation**: ⚠️ **REVIEW** - Not dead code, but could be refactored. The mapping is functional but adds storage overhead. Consider if the gas cost of checking array membership (linear scan) vs maintaining parallel mapping (constant check + extra storage) is worth the tradeoff given expected leaderboard sizes.

---

### 4. State Variable: `drawParticipants`

**Location**: Line 198
**Type**: 5-dimensional mapping
**References**: 4 (write-only)

```solidity
mapping(uint8 => mapping(uint8 => mapping(uint8 => mapping(uint8 => mapping(address => bool))))) public drawParticipants;
```

**Usage**:
- **Written**: Lines 965-966 (set to true for both players during draw)
- **Deleted**: Lines 2186, 2189 (cleanup during tournament reset)
- **Read**: NEVER queried in any logic

**Status**: ⚠️ **WRITE-ONLY - Query potential unused**

**Analysis**:
- This mapping tracks which players participated in draw matches
- It's set during match completion but never queried
- Only cleared during cleanup (to avoid storage bloat)
- Marked as `public` so technically queryable externally, but no internal logic uses it

**Recommendation**: ⚠️ **REVIEW** - Either:
1. **Keep as public API** for external indexers/analytics (current state)
2. **Remove entirely** if no off-chain systems rely on it
3. **Add query functions** if internal logic should use it

**Note**: As a public mapping, it's part of the contract's external interface. Removal would be a breaking change for any off-chain tools querying it.

---

### 5. State Variable: `currentRaffleIndex`

**Location**: Line 184
**Type**: uint256 public
**References**: 3 (minimal usage)

```solidity
uint256 public currentRaffleIndex;  // Starts at 0, increments when raffle executes
```

**Usage**:
- **Incremented**: Line 742 (`currentRaffleIndex++;`)
- **Emitted**: Line 784 (included in `ProtocolRaffleExecuted` event)
- **Read**: Line 2391 (returned in `getRaffleInfo()` view function)

**Status**: ⚠️ **MINIMAL USAGE - Counter for events**

**Analysis**:
- Primarily used as an event identifier for raffle tracking
- Not used in any core protocol logic or state transitions
- Useful for off-chain event indexing and analytics
- Low storage overhead (single uint256)

**Recommendation**: ⚠️ **KEEP** - While minimally used, it serves a clear purpose:
- Provides unique raffle execution identifiers
- Enables off-chain systems to track raffle history
- No significant gas or storage cost
- Removing it would break event indexing for analytics tools

---

## ACTIVE CODE (All Elements Confirmed in Use)

### Constants (5/5 items) ✅ ALL ACTIVE

| Constant | Value | References | Usage |
|----------|-------|-----------|-------|
| `PARTICIPANTS_SHARE_BPS` | 9000 | 2 | Fee distribution (90% to prize pool) |
| `OWNER_SHARE_BPS` | 750 | 2 | Fee distribution (7.5% to owner) |
| `PROTOCOL_SHARE_BPS` | 250 | 2 | Fee distribution (2.5% to protocol) |
| `BASIS_POINTS` | 10000 | 4 | Denominator for basis point calculations |
| `NO_ROUND` | 255 | 4 | Sentinel value for "no round assigned" |

**Status**: ✅ All constants actively used in core fee distribution logic

---

### Enums (4/5 types active, 1 dead) ✅ 80% ACTIVE

| Enum | Values | References | Status |
|------|--------|-----------|--------|
| `TournamentStatus` | 3 values | 21 | ✅ ACTIVE |
| `MatchStatus` | 3 values | 48 | ✅ ACTIVE |
| `Mode` | 2 values | 10 | ✅ ACTIVE |
| `EscalationLevel` | 4 values | 10 | ✅ ACTIVE |
| **`TournamentCompletionType`** | 3 values | 1 | ❌ **DEAD** |

---

### Events (22/22) ✅ ALL ACTIVE

All 22 events are emitted at least once:
- `TierRegistered` ✅
- `TournamentInitialized` ✅
- `PlayerEnrolled` ✅
- `TournamentStarted` ✅
- `PlayerAutoAdvancedWalkover` ✅
- `RoundInitialized` ✅
- `MatchStarted` ✅ (3 emit sites)
- `PlayersConsolidated` ✅
- `MatchCompleted` ✅ (3 emit sites)
- `RoundCompleted` ✅
- `TournamentCompleted` ✅ (2 emit sites)
- `AllDrawRoundDetected` ✅
- `TournamentCompletedAllDraw` ✅
- `TournamentReset` ✅
- `OwnerFeePaid` ✅
- `ProtocolFeePaid` ✅
- `PrizeDistributed` ✅ (3 emit sites)
- `PrizeDistributionFailed` ✅ (2 emit sites)
- `PrizeFallbackToContract` ✅
- `TournamentCached` ✅ (2 emit sites)
- `TournamentForceStarted` ✅
- `EnrollmentPoolClaimed` ✅
- `EnrollmentWindowReset` ✅
- `PlayerForfeited` ✅
- `TimeoutVictoryClaimed` ✅ (emitted in game contracts)
- `ProtocolRaffleExecuted` ✅

---

### State Variables (20/20) ✅ ALL FUNCTIONAL

| Variable | Type | References | Status |
|----------|------|-----------|--------|
| `owner` | immutable address | 15 | ✅ ACTIVE |
| `tierCount` | uint8 | 5 | ✅ ACTIVE |
| `accumulatedProtocolShare` | uint256 | 11 | ✅ ACTIVE |
| `currentRaffleIndex` | uint256 | 3 | ⚠️ MINIMAL (event tracking) |
| `tournaments` | mapping | 21 | ✅ ACTIVE |
| `enrolledPlayers` | mapping | 13 | ✅ ACTIVE |
| `isEnrolled` | mapping | 10 | ✅ ACTIVE |
| `rounds` | mapping | 16 | ✅ ACTIVE |
| `playerStats` | mapping | 17 | ✅ ACTIVE |
| `playerActiveMatches` | mapping | 11 | ✅ ACTIVE |
| `playerMatchIndex` | mapping | 4 | ✅ ACTIVE |
| `playerRanking` | mapping | 10 | ✅ ACTIVE |
| `playerPrizes` | mapping | 5 | ✅ ACTIVE |
| `drawParticipants` | mapping | 4 | ⚠️ WRITE-ONLY (public query) |
| `playerEarnings` | mapping | 3 | ⚠️ MINIMAL (leaderboard only) |
| `_leaderboardPlayers` | array | 6 | ✅ ACTIVE |
| `_isOnLeaderboard` | mapping | 2 | ⚠️ POTENTIALLY REDUNDANT |
| `matchTimeouts` | mapping | 7 | ✅ ACTIVE |
| `_tierConfigs` | mapping | 33 | ✅ ACTIVE (heavily used) |
| `_tierPrizeDistribution` | mapping | 4 | ✅ ACTIVE |

---

### Functions Analysis

#### External Functions (12 total) ✅ ALL PRESERVED

**Status**: All external functions are preserved as they form the public API. Even if minimally used in tests, they may be called by external integrations.

- `enrollInTournament()` ✅ (core enrollment)
- `forceStartTournament()` ✅ (L1 timeout escalation)
- `claimAbandonedEnrollmentPool()` ✅ (L2 enrollment escalation)
- `resetEnrollmentWindow()` ✅ (solo player extension)
- `executeProtocolRaffle()` ✅ (raffle execution)
- `forceEliminateStalledMatch()` ✅ (L2 match escalation)
- `claimMatchSlotByReplacement()` ✅ (L3 match escalation)
- `tierConfigs()` ✅ (getter)
- `getTimeoutConfig()` ✅ (getter)
- `ENTRY_FEES()` ✅ (ABI compatibility)
- `INSTANCE_COUNTS()` ✅ (ABI compatibility)
- `TIER_SIZES()` ✅ (ABI compatibility)
- `canResetEnrollmentWindow()` ✅ (checker)
- `getTournamentInfo()` ✅ (getter)
- `getPlayerActiveMatches()` ✅ (getter)
- `getEnrolledPlayers()` ✅ (getter)
- `getRoundInfo()` ✅ (getter)
- `getPlayerStats()` ✅ (getter)
- `getTierOverview()` ✅ (getter)
- `getLeaderboard()` ✅ (getter)
- `getLeaderboardCount()` ✅ (getter)
- `getRaffleInfo()` ✅ (getter)
- `isMatchEscL1Available()` ✅ (escalation checker)
- `isMatchEscL2Available()` ✅ (escalation checker)
- `isMatchEscL3Available()` ✅ (escalation checker)
- `isPlayerInAdvancedRound()` ✅ (escalation helper)

#### Public Functions (5 total) ✅ ALL PRESERVED

- `getMatchTimePerPlayer()` ✅
- `getTimeIncrement()` ✅
- `getMatchId()` ✅
- `getPrizePercentage()` ✅
- `declareRW3()` ✅

#### Internal Functions (17 analyzed) ✅ ALL ACTIVE

All 17 critical internal functions analyzed are actively called:

- `_log2()` ✅ (1 call)
- `_hasOrphanedWinners()` ✅ (3 calls)
- `_processOrphanedWinners()` ✅ (3 calls)
- `_getRemainingPlayers()` ✅ (1 call)
- `_checkForSoleWinnerCompletion()` ✅ (3 calls)
- `_consolidateScatteredPlayers()` ✅ (1 call)
- `_markMatchStalled()` ✅ (2 calls)
- `_clearEscalationState()` ✅ (3 calls)
- `_checkAndMarkStalled()` ✅ (2 calls)
- `_completeMatchDoubleElimination()` ✅ (1 call)
- `_completeMatchByReplacement()` ✅ (1 call)
- `_updatePlayerEarnings()` ✅ (3 calls)
- `_updateAbandonedEarnings()` ✅ (1 call)
- `_trackOnLeaderboard()` ✅ (3 calls)
- `_isCallerEnrolledInActiveTournament()` ✅ (1 call)
- `_getAllEnrolledPlayersWithWeights()` ✅ (2 calls)
- `_selectWeightedWinner()` ✅ (1 call)

#### Abstract Functions (12 total) ✅ ALL PRESERVED

**Status**: All abstract functions must be preserved - they define the required interface that game contracts must implement.

- `_createMatchGame()` ✅
- `_resetMatchGame()` ✅
- `_getMatchResult()` ✅
- `_addToMatchCacheGame()` ✅
- `_getMatchPlayers()` ✅
- `_setMatchPlayer()` ✅
- `_initializeMatchForPlay()` ✅
- `_completeMatchWithResult()` ✅
- `_getTimeIncrement()` ✅
- `_hasCurrentPlayerTimedOut()` ✅
- `_isMatchActive()` ✅
- `_getActiveMatchData()` ✅
- `_getMatchFromCache()` ✅

#### Virtual Hooks (7 total) ✅ ALL PRESERVED

**Status**: All virtual hooks are preserved as they're part of the extensibility design pattern.

- `_onPlayerEnrolled()` ✅
- `_onTournamentStarted()` ✅
- `_onPlayerEliminatedFromTournament()` ✅
- `_onExternalPlayerReplacement()` ✅
- `_onTournamentCompleted()` ✅
- `_getRaffleThreshold()` ✅
- `_getRaffleReserve()` ✅

---

## Summary Tables

### Dead Code Candidates (Recommended for Removal)

| Element | Type | Location | Reason | Gas Savings |
|---------|------|----------|--------|-------------|
| `TournamentCompletionType` | Enum | Line 52-56 | Never used (0 references) | ~200 gas (bytecode reduction) |
| `forceStarter` | Struct field | Line 106 | Set but never read | ~20,000 gas per tournament |
| `forceStartTimestamp` | Struct field | Line 107 | Set but never read | ~20,000 gas per tournament |
| `firstEnroller` | Struct field | Line 104 | Set but never read | ~20,000 gas per tournament |
| `firstEnrollmentTimestamp` | Struct field | Line 105 | Set but never read | ~20,000 gas per tournament |

**Total Estimated Savings**: ~80,000 gas per tournament initialization + ~15,000 gas per tournament reset

---

### Potentially Underutilized (Review Recommended)

| Element | Type | Location | Issue | Action |
|---------|------|----------|-------|--------|
| `_isOnLeaderboard` | Mapping | Line 203 | Guard mapping with 2 references | Consider refactoring |
| `drawParticipants` | Mapping | Line 198 | Write-only (never queried internally) | Keep as public API or remove |
| `currentRaffleIndex` | uint256 | Line 184 | Minimal use (event tracking only) | Keep (useful for indexing) |

---

### Preserved Elements (Intentionally Unused)

| Element | Type | Reason for Preservation |
|---------|------|------------------------|
| All external/public functions | Functions | Public API - external integrations |
| All abstract functions | Functions | Required interface contract |
| All virtual hooks | Functions | Extensibility pattern |
| All events | Events | Off-chain indexing |

---

## Gas Optimization Potential

### Removal Impact:

**Per Tournament Lifecycle:**
- Initialization: ~80,000 gas saved (4 × SSTORE from zero)
- Reset/Cleanup: ~15,000 gas saved (4 × SSTORE to zero)
- **Total per tournament**: ~95,000 gas saved

**Annual Savings** (estimated 1000 tournaments/year):
- ~95,000,000 gas saved per year
- At 1 gwei gas price: ~0.095 ETH saved per year
- At 10 gwei gas price: ~0.95 ETH saved per year

**Bytecode Reduction:**
- Removing enum: ~200 bytes
- Removing 4 struct fields: negligible (struct layout doesn't affect bytecode significantly)
- **Deployment savings**: ~40,000 gas (one-time)

---

## Implementation Plan

### Phase 1: Dead Code Removal (SAFE)

**Priority 1 - Remove Enum:**
```solidity
// DELETE LINES 52-56
enum TournamentCompletionType {
    Regular,
    PartialStart,
    Abandoned
}
```

**Priority 2 - Remove Struct Fields:**
```solidity
// In TournamentInstance struct (lines 88-108)
// DELETE these 4 lines:
address firstEnroller;              // Line 104 - DELETE
uint256 firstEnrollmentTimestamp;  // Line 105 - DELETE
address forceStarter;              // Line 106 - DELETE
uint256 forceStartTimestamp;       // Line 107 - DELETE
```

**Required Code Changes:**
1. Remove assignments: Lines 546, 547, 601, 602, 668
2. Remove cleanup: Lines 2142, 2143, 2144, 2145
3. Update struct documentation

**Testing Requirements:**
- Run full test suite (expect 330 passing, 5 failing as baseline)
- Verify no storage layout issues
- Check gas benchmarks for savings

---

### Phase 2: Optimization Review (OPTIONAL)

**Option A - Refactor `_isOnLeaderboard`:**
- Evaluate gas cost of array membership check vs mapping overhead
- Consider expected leaderboard size (if < 100 players, array scan may be cheaper)
- Implementation: Remove mapping, add `contains()` helper for array

**Option B - Review `drawParticipants`:**
- Survey off-chain tools: Does anything query this mapping?
- If no external dependencies: Consider removal
- If used externally: Keep as-is

**Option C - Keep `currentRaffleIndex`:**
- Low overhead, clear purpose
- No changes recommended

---

## Next Steps

1. **Review this report** with the development team
2. **Verify storage layout implications** for TournamentInstance struct changes
3. **Create removal branch**: `refactor/dead-code-cleanup-phase1`
4. **Implement Phase 1 removals** (enum + 4 struct fields)
5. **Run full test suite** and verify 330 tests still pass
6. **Measure gas savings** using before/after benchmarks
7. **Consider Phase 2 optimizations** after Phase 1 is validated

---

## Risk Assessment

### Low Risk (Phase 1 Removals):
- ✅ No public API changes (all dead code is internal)
- ✅ No breaking changes for external integrations
- ✅ No test changes expected (code was never used)
- ✅ Storage layout change is safe (only removing unused fields)

### Medium Risk (Phase 2 Optimizations):
- ⚠️ `drawParticipants` removal could break off-chain indexers
- ⚠️ `_isOnLeaderboard` refactoring requires careful gas analysis

---

## Appendix

### A. Search Commands Used

```bash
# Constants analysis
grep -n "PARTICIPANTS_SHARE_BPS" contracts/ETour.sol
grep -n "OWNER_SHARE_BPS" contracts/ETour.sol
grep -n "PROTOCOL_SHARE_BPS" contracts/ETour.sol
grep -n "BASIS_POINTS" contracts/ETour.sol
grep -n "NO_ROUND" contracts/ETour.sol

# Enum usage
grep -c "TournamentStatus\." contracts/
grep -c "MatchStatus\." contracts/
grep -c "Mode\." contracts/
grep -c "EscalationLevel\." contracts/
grep -r "TournamentCompletionType" contracts/ test/

# Events emitted
grep -r "emit " contracts/ETour.sol

# State variable references
grep -o "tierCount" contracts/ETour.sol | wc -l
grep -o "accumulatedProtocolShare" contracts/ETour.sol | wc -l
# ... (see background agent output for full list)

# Function call analysis
grep -n "_log2\\(" contracts/ETour.sol
grep -n "_hasOrphanedWinners\\(" contracts/ETour.sol
# ... (see background agent output for full list)
```

### B. Test Coverage Reference

- Test report: `/Users/karim/Documents/workspace/zero-trust/e-tour/test-report.html`
- Passing tests: 330
- Failing tests: 5 (Chess 50-move rule, fee distribution)
- Test files analyzed: 27 files

### C. Storage Layout Considerations

**TournamentInstance Storage Slots (Before):**
```
Slot 0: tierId, instanceId, status, mode, currentRound, enrolledCount
Slot 1: prizePool
Slot 2: startTime
Slot 3: winner
Slot 4: coWinner
Slot 5: finalsWasDraw, allDrawResolution, allDrawRound
Slot 6-9: enrollmentTimeout (4 fields)
Slot 10: hasStartedViaTimeout
Slot 11: firstEnroller              // ← REMOVE
Slot 12: firstEnrollmentTimestamp   // ← REMOVE
Slot 13: forceStarter               // ← REMOVE
Slot 14: forceStartTimestamp        // ← REMOVE
```

**TournamentInstance Storage Slots (After):**
```
Slots 0-10: Same as before
Slots 11-14: Removed (4 slots freed)
```

**Impact**: Removing the 4 trailing fields is safe - no other fields are affected. Storage layout for existing fields remains unchanged.

---

## Conclusion

The ETour protocol is well-designed with minimal dead code. Only 5 elements (2% of total) are confirmed dead:
- 1 completely unused enum
- 4 struct fields that track metadata but are never queried

All other code (constants, events, state variables, functions) is actively used and serves clear purposes. The identified dead code represents abandoned analytics/tracking features that were never fully integrated.

**Recommendation**: Proceed with Phase 1 dead code removal to save ~95,000 gas per tournament and improve code maintainability.
