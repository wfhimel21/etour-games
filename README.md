# ETOUR.games
### Tournament Infrastructure for Skill-Based Competition

---

## Abstract

ETour is EVM freeware for on-chain competitive play. 

Every move is a transaction. Every outcome is immutable. The smart contract handles matchmaking, brackets, timeouts, and prize distribution. 

Developers inherit this infrastructure by implementing a simple abstract contract. Players just connect and compete.

<strong> ETH in ETH out. No servers, no admins to trust, no way to cheat.</strong>

---

This whitepaper explains ETour's philosophy and how it makes trustless competition possible. 

**It's intended for those who want to understand not just what ETour does but why it was built this way.**

---

<details>
<summary><strong>Table of Contents</strong></summary>

1. [Philosophy: Games First, Infrastructure Second](#1-philosophy-games-first-infrastructure-second)
   - [1.1 The Problem with Web3 Gaming](#11-the-problem-with-web3-gaming)
   - [1.2 What Players Actually Want](#12-what-players-actually-want)
   - [1.3 The ETour Approach](#13-the-etour-approach)

2. [The Three Flagship Games](#2-the-three-flagship-games)
   - [2.1 Selection Criteria](#21-selection-criteria)
   - [2.2 Eternal Tic-Tac-Toe](#22-eternal-tic-tac-toe)
   - [2.3 ChessOnChain](#23-chessonchain)
   - [2.4 Connect Four](#24-connect-four)
   - [2.5 Why Not Battleship?](#25-why-not-battleship)

3. [Protocol Architecture](#3-protocol-architecture)
   - [3.1 Separation of Concerns](#31-separation-of-concerns)
   - [3.2 The Abstract Contract Pattern](#32-the-abstract-contract-pattern)
   - [3.3 Game Implementation Requirements](#33-game-implementation-requirements)
   - [3.4 Shared Infrastructure Benefits](#34-shared-infrastructure-benefits)

4. [Tournament Mechanics](#4-tournament-mechanics)
   - [4.1 Tier System](#41-tier-system)
   - [4.2 Instance Management](#42-instance-management)
   - [4.3 Bracket Progression](#43-bracket-progression)
   - [4.4 Draw Handling](#44-draw-handling)
   - [4.5 Walkover and Consolidation Logic](#45-walkover-and-consolidation-logic)

5. [Economic Model](#5-economic-model)
   - [5.1 Fee Structure](#51-fee-structure)
   - [5.2 Prize Distribution](#52-prize-distribution)
   - [5.3 Self-Sustaining Operations](#53-self-sustaining-operations)
   - [5.4 No Token, No Speculation](#54-no-token-no-speculation)

6. [Anti-Griefing Systems](#6-anti-griefing-systems)
   - [6.1 The Stalling Problem](#61-the-stalling-problem)
   - [6.2 Enrollment Timeout Escalation](#62-enrollment-timeout-escalation)
   - [6.3 Match Timeout Escalation](#63-match-timeout-escalation)
   - [6.4 Economic Incentives for Resolution](#64-economic-incentives-for-resolution)

7. [Trust and Verification](#7-trust-and-verification)
   - [7.1 Fully On-Chain Execution](#71-fully-on-chain-execution)
   - [7.2 No Admin Override](#72-no-admin-override)
   - [7.3 Deterministic Outcomes](#73-deterministic-outcomes)
   - [7.4 Open Source Verification](#74-open-source-verification)

8. [RW3 Compliance](#8-rw3-compliance)
   - [8.1 The Five Principles](#81-the-five-principles)
   - [8.2 How ETour Meets Each Principle](#82-how-etour-meets-each-principle)

9. [Technical Specification](#9-technical-specification)
   - [9.1 Contract Structure](#91-contract-structure)
   - [9.2 Key Data Structures](#92-key-data-structures)
   - [9.3 Core Functions](#93-core-functions)
   - [9.4 Events](#94-events)
   - [9.5 Gas Optimization](#95-gas-optimization)

10. [Conclusion](#10-conclusion)

**Appendices:**
- [Appendix A: Complete Implementation Walkthrough](#appendix-a-complete-implementation-walkthrough)
   - [A.1 Prerequisites](#a1-prerequisites)
   - [A.2 Step 1: Define Your Game's Data Structures](#a2-step-1-define-your-games-data-structures)
   - [A.3 Step 2: Configure Tournament Tiers](#a3-step-2-configure-tournament-tiers)
   - [A.4 Step 3: Implement Abstract Functions](#a4-step-3-implement-abstract-functions)
   - [A.5 Step 4: Implement Game Logic](#a5-step-4-implement-game-logic)
   - [A.6 Step 5: Implement Timeout Claims](#a6-step-5-implement-timeout-claims)
   - [A.7 Step 6: Add View Functions](#a7-step-6-add-view-functions)
   - [A.8 Step 7: Deploy and Test](#a8-step-7-deploy-and-test)
   - [A.9 Frontend Integration](#a9-frontend-integration)
   - [A.10 Complete Implementation Checklist](#a10-complete-implementation-checklist)
- [Appendix B: Economic Projections](#appendix-b-economic-projections)

</details>

---

## 1. Philosophy: Games First, Infrastructure Second

### 1.1 The Problem with Web3 Gaming

Web3 gaming has a credibility problem. The phrase "play games and earn crypto" has been used so many times by scams, rugpulls, and tokenomics that don't work that it makes people doubt it, rightfully so. **Players have learned that "earn" usually means "lose money slowly while enriching early adopters."**

Most Web3 gaming projects make the same fundamental mistake: they lead with blockchain technology and financial incentives rather than compelling gameplay. They're selling infrastructure, tokens, and economic mechanisms to people who just want to play games.

This approach fails because:

- **Players don't care about infrastructure.** They care about fair competition and real outcomes.
- **"Earn" messaging attracts speculators, not gamers.** The community becomes focused on extraction rather than competition.
- **Technical complexity creates barriers.** Explaining on-chain verification to someone who wants to play chess is backwards.

### 1.2 What Players Actually Want

Competitive players want simple things:

1. **Fair games** — No hidden algorithms deciding outcomes
2. **Meaningful stakes** — Something real on the line
3. **Skill determines results** — Not luck, not who bought more tokens
4. **Instant resolution** — Win and get paid, no waiting periods

These desires exist independently of blockchain. Chess players have always wanted fair competition with meaningful stakes. The question is whether blockchain adds value to this experience and that value can manifest without drowning the player in technical jargon.

### 1.3 The ETour Approach

ETour turns the usual Web3 gaming pitch on its head:

#### **Traditional Web3 Gaming** 

> Here's our "revolutionary blockchain protocol". It has tokenomics, staking mechanisms, and governance.<br>Oh, and you can play games on it.

<br> 

#### **ETour** 

> Here are classic games you already know.<br>Play for real ETH stakes. The better player claims the pot.

The blockchain infrastructure exists to serve the games, not the other way around. ETour Protocol is the engine under the hood that makes this competition possible, but not the selling point.

**This whitepaper exists for those who want to look under the hood.** If you're a player who just wants to compete, the landing page tells you everything you need: pick a game, connect your wallet, prove you're good.

---

## 2. The Three Flagship Games

### 2.1 Selection Criteria

ETour's flagship games were chosen based on strict criteria that ensure full on-chain verifiability:

1. **Complete Information** — All game state must be visible to all players. No hidden hands, no fog of war.
2. **Deterministic Rules** — Given the same inputs, the same output must always result. No randomness mid-game.
3. **Discrete Turns** — Games must have clear turn boundaries suitable for blockchain transaction timing.
4. **Reasonable Complexity** — Game logic must be implementable within smart contract gas limits.
5. **Cultural Recognition** — Games should be widely known, requiring no rule explanation.

These criteria eliminate entire categories of games. Poker requires hidden cards. Real-time games can't wait for block confirmation. Complex simulations exceed gas limits. But within these constraints, several classic games fit perfectly.


### 2.2 Tic-Tac-Toe

**Entry Point: 0.001 ETH**

Tic-tac-toe serves as the accessible entry point to ETour. Everyone knows the rules. Games complete quickly. The low stakes allow new players to experience the platform mechanics without significant risk.

> But tic-tac-toe is solved, perfect play always draws.

Exactly! And that's the point. Tic-tac-toe's high draw rate makes it the perfect demonstration of ETour's draw economics. When a match ends in a draw, both players receive most of their entry fee back. On a $3 entry, approximately $2.50 returns to each player. The draw essentially costs each player $0.50, a fee for playing a fair, verified game.

This transforms tic-tac-toe's "flaw" into a feature:

- **Low-risk learning environment** — New players can experience the full platform flow (enroll, play, payout) with minimal downside
- **Draw mechanics demonstration** — Players see exactly how ETour handles non-decisive outcomes
- **Economic transparency** — The refund math is simple enough to verify immediately

Tic-tac-toe is the "Hello World" of ETour - not because it's competitive at the highest level, but because it proves the system works. Fair games, instant payouts, sensible draw handling. If you can trust ETour with tic-tac-toe, you can trust it with chess.

### 2.3 Chess

**Entry Point: 0.01 – 0.02 ETH**

Chess is ETour's flagship serious competition. 

Full chess rules: castling, en passant, pawn promotion, fifty-move rule, threefold repetition. **All verified on-chain.** 

Every move is permanently recorded, creating an immutable record of every game.

We chose chess because: 

- **Deep strategic complexity** that makes the stakes worth it
- **Established competitive culture** gives you an audience right away
- **Full information** is a perfect match for blockchain transparency 
- **Existing rating systems** give players benchmarks to prove

Chess on chain has something that no other centralized platform can offer serious chess players: 

**They are 100% sure that their opponent isn't using engine assistance (each move is a transaction from their wallet), and they will get paid if they win.** 

### 2.4 Connect Four

**Entry Point: 0.001 – 0.1 ETH**

Connect Four occupies the middle ground. More strategic depth than tic-tac-toe, faster than chess, familiar to most players. The vertical drop mechanic creates unique tactical situations while remaining simple to verify on-chain.

Connect Four was added because:

- **Deceptive strategic depth** — Simple rules hide complex tactics
- **Quick games** — Matches complete faster than chess, enabling higher tournament throughput
- **Complementary audience** — Appeals to players who want more than tic-tac-toe but less commitment than chess

### 2.5 Why Not Battleship?

Battleship was initially considered as the third flagship game. It was rejected because it fundamentally conflicts with blockchain's transparency properties.

Battleship requires **hidden information**—players place ships secretly, then guess opponent positions. To make this work on-chain, you have to make one of two compromises: 

1. **Commit-reveal schemes** —  Players agree to send their positions cryptographically, and they will be revealed after the game.

2. **Off-chain computation** — Ship positions stored off-chain, only results posted on-chain. This breaks the "fully on-chain" principle entirely.

Neither option aligns with ETour's principles. Hidden information games require trusting some mechanism beyond the blockchain itself. Rather than compromise, we replaced Battleship with Connect Four; a game that needs no hidden state and can be fully verified in a single transaction per move.

This decision exemplifies ETour's philosophy: **accept blockchain's constraints and build games that naturally fit, rather than forcing incompatible designs.**

---

## 3. Protocol Architecture

### 3.1 Separation of Concerns

ETour's architecture separates **universal tournament mechanics** from **game-specific logic**:

**ETour Protocol (Universal):**
- Tournament enrollment and matchmaking
- Bracket management and round progression
- Timeout detection and escalation
- Prize pool calculation and distribution
- Player statistics tracking
- Permanent earnings history and leaderboard

**Game Contracts (Specific):**
- Move validation rules
- Win/draw detection
- Board state representation
- Game-specific data structures

This separation means that once ETour's tournament logic is audited and battle-tested, new games can be added with confidence that the competitive infrastructure works correctly. Each new game only needs to implement its own rules correctly.

### 3.2 The Abstract Contract Pattern

ETour is implemented as an abstract Solidity contract. Game implementations inherit from ETour and override specific functions:

```solidity
abstract contract ETour is ReentrancyGuard {
    // Universal tournament mechanics implemented here
    
    // Game-specific functions to be implemented by child contracts
    function _createMatchGame(...) internal virtual;
    function _resetMatchGame(bytes32 matchId) internal virtual;
    function _getMatchResult(bytes32 matchId) internal view virtual 
        returns (address winner, bool isDraw, MatchStatus status);
    function _getMatchPlayers(bytes32 matchId) internal view virtual 
        returns (address player1, address player2);
    // ... additional abstract functions
}

contract ChessOnChain is ETour {
    // Chess-specific implementation of abstract functions
    // Plus chess rules, board state, move validation
}
```

This pattern provides compile-time guarantees that game implementations provide all required functions while inheriting all tournament functionality automatically.

### 3.3 Game Implementation Requirements

To build a game on ETour, developers implement these core functions:

| Function | Purpose |
|----------|---------|
| `_createMatchGame` | Initialize game state for a new match |
| `_resetMatchGame` | Clean up game state after match completion |
| `_getMatchResult` | Return winner, draw status, and match status |
| `_getMatchPlayers` | Return both players' addresses |
| `_initializeMatchForPlay` | Set up match for active gameplay |
| `_completeMatchWithResult` | Finalize match with outcome |
| `_setMatchPlayer` | Assign player to match slot |
| `_setMatchTimeoutState` | Update timeout tracking |
| `_getMatchTimeoutState` | Read timeout state |

Additionally, games define their tier structure in the constructor:

```solidity
constructor() {
    // Tier 0: 2-player, 0.001 ETH entry
    uint8[] memory tier0Prizes = new uint8[](2);
    tier0Prizes[0] = 100; // Winner takes all
    tier0Prizes[1] = 0;
    
    _registerTier(
        0,              // tierId
        2,              // playerCount
        10,             // instances
        0.001 ether,    // entryFee
        Mode.Classic,   // mode
        30 minutes,     // enrollmentWindow
        10 minutes,     // matchMoveTimeout
        1 hours,        // escalationInterval
        tier0Prizes     // prize distribution
    );
}
```

### 3.4 Shared Infrastructure Benefits

Games built on ETour inherit:

- **Proven tournament logic** — Bracket progression, round management, and advancement handling
- **Economic sustainability** — Fee splitting, prize distribution, forfeit handling
- **Anti-griefing protection** — Timeout escalation across enrollment and matches
- **Player statistics** — Cross-game win/loss tracking
- **Permanent earnings history** — Per-player prize records (`playerPrizes`) and net earnings (`playerEarnings`) stored permanently on-chain, enabling lifetime leaderboards
- **Security patterns** — ReentrancyGuard, access controls, prize isolation

This shared foundation means game developers focus purely on game rules, confident that the competitive infrastructure handles edge cases correctly.

---

## 4. Tournament Mechanics

### 4.1 Tier System

ETour supports configurable tournament tiers, each defining:

- **Player count** — Tournament size (powers of 2 for clean brackets, or any number with walkover handling)
- **Instance count** — Concurrent tournaments at this tier
- **Entry fee** — Stakes required to join
- **Mode** — Classic or Pro variations
- **Timeouts** — Enrollment window, move timeout, escalation intervals
- **Prize distribution** — Percentage allocation by final ranking

Example tier configuration:

| Tier | Players | Entry Fee | Prize Split |
|------|---------|-----------|-------------|
| 0 | 2 | 0.001 ETH | 100% / 0% |
| 1 | 4 | 0.005 ETH | 70% / 30% / 0% / 0% |
| 2 | 8 | 0.01 ETH | 50% / 25% / 15% / 10% / 0%... |
| 3 | 16 | 0.05 ETH | Custom distribution |

Higher tiers offer larger prize pools but require more opponents and longer tournament duration.

### 4.2 Instance Management

Each tier runs multiple concurrent instances. If Tier 2 has 4 instances, four separate 8-player tournaments can run simultaneously. When one completes, it automatically resets and begins accepting new enrollments.

This design ensures:

- **Availability** — Players can almost always find an enrolling tournament
- **Throughput** — Multiple tournaments process in parallel
- **Bounded state** — Fixed instance count prevents unbounded storage growth

### 4.3 Bracket Progression

Tournaments follow single-elimination bracket format:


1. Players sign up until the tier is full or the time runs out and the games start
2. Round 0 puts players together for their first matches
3. Winners move on to the next round. Losers are kicked out
4. This goes on until the finals decide the champion
5. Prizes distribute automatically upon completion
6. Tournament automatically resets for new enrollment

The protocol handles odd player counts through walkover advancement. One randomly selected player advances without playing, ensuring brackets remain functional.

### 4.4 Draw Handling

Some games (notably tic-tac-toe) can end in draws. ETour handles draws through several mechanisms:

**Single Match Draw:**
Both players are eliminated. Neither advances. This creates natural pressure to play for wins rather than safe draws.

**All-Draw Round:**
If every match in a round draws, the tournament cannot continue normally. ETour detects this condition and splits the remaining prize pool equally among all remaining players.

**Finals Draw:**
If the championship match draws, both finalists are declared co-winners and split the first-place prize.

### 4.5 Walkover and Consolidation Logic

When draws eliminate players without producing winners, bracket structures can become unbalanced. ETour's consolidation logic handles these edge cases:

- **Orphaned winners** — A player who won their match but has no opponent in the next round (because that opponent's match drew) advances automatically
- **Scattered players** — When odd numbers of players remain in a round, the protocol consolidates them into valid matchups
- **Solo survivor** — If only one player remains active, they're declared tournament winner regardless of round number

This logic ensures tournaments always reach resolution rather than getting stuck in unplayable states.

---

## 5. Economic Model

### 5.1 Fee Structure

Entry fees are split at enrollment time:

| Recipient | Share | Purpose |
|-----------|-------|---------|
| Prize Pool | 90% | Distributed to tournament winners |
| Owner | 7.5% | Operational sustainability |
| Protocol | 2.5% | Future development fund |

This split is hardcoded in the contract. No admin function can modify it once deployed and players know exactly where their entry fee goes.

### 5.2 Prize Distribution

Prize distribution is defined per-tier as percentage arrays. For an 8-player tournament:

```
[50, 25, 15, 10, 0, 0, 0, 0]
```

Meaning:
- 1st place: 50% of prize pool
- 2nd place: 25%
- 3rd-4th place (semifinal losers): Split 15% equally (7.5% each)
- 5th-8th place: 0%

Distributions must sum to 100%. Games can configure any distribution that incentivizes their competitive structure.

### 5.3 Self-Sustaining Operations

ETour requires no ongoing funding, token sales, or venture capital. The 10% operational fee (7.5% + 2.5%) from each entry fee funds:

- Server costs for frontend hosting (the only centralized component)
- Future development and audits
- Legal and operational overhead

Because the protocol runs entirely on-chain, these costs are minimal. Even with modest adoption, the fee structure generates sufficient revenue for indefinite operation.

### 5.4 No Token, No Speculation

ETour has no governance token, utility token, or any token at all. This is intentional:

- **No speculation** — Players can't "invest" in ETour; they can only compete
- **No regulatory ambiguity** — No securities law concerns
- **No extraction** — No early investors extracting value from later players
- **Simplicity** — ETH in, ETH out

This commitment means ETour will never have a "token launch," never offer staking rewards, never implement "play-to-earn" tokenomics. The only way to profit from ETour is to win games.

---

## 6. Anti-Griefing Systems

### 6.1 The Stalling Problem

Competitive systems with real stakes face a fundamental griefing vector: players can stall indefinitely to avoid losses. Without countermeasures:

- A losing player could simply stop making moves, hoping the opponent gives up
- Tournaments could stall at enrollment, never reaching required player counts
- Funds could be locked indefinitely in unresolvable states

Traditional platforms solve this with centralized intervention. Admins who adjudicate disputes. **ETour brings forth autonomous solutions.**

### 6.2 Enrollment Timeout Escalation

When a player enrolls in an unfilled tournament, a countdown begins. If the tournament doesn't fill naturally:

**Escalation 1 — Enroller Claim (Force Start):**
After the enrollment window expires, enrolled players can force-start the tournament with whatever players have joined, even if below capacity. If only one player has enrolled, they win immediately and receive the prize pool.

**Escalation 2 — Public Claim (Abandoned Pool):**
After an additional escalation interval, **anyone** (including non-enrolled players) can claim the abandoned enrollment pool. All enrolled players are marked as forfeited, and **the claimer receives the entire prize pool** (90% of all entry fees collected). This is not a small reward, **it's the full pot!**.

This creates a strong economic incentive for resolution. Rather than funds sitting locked forever, someone can always claim the either by playing a reduced tournament or by cleaning up an abandoned one and taking the entire pool.

### 6.3 Match Timeout Escalation

During active matches, each move must occur within the configured timeout. When a timeout occurs:

**Escalation 1 — Opponent Claim:**
The opponent can claim victory directly. They waited; they win. The stalling player forfeits and is eliminated.

**Escalation 2 — Advanced Players (Force Eliminate):**
Players in the same tournament who have already won a match (and thus "advanced") can force-eliminate the stalled match. **Both players in the stalled match are eliminated** and neither advances. The advanced player who triggers this receives no direct reward; their incentive is unblocking the tournament so they can continue competing for the prize pool.

**Escalation 3 — External Replacement:**
Anyone can claim the match slot by **replacing** both stalled players. The claimer does not receive a cash reward. Instead, **they become the match winner and advance to the next round** (or win the tournament if it's the finals). Both original players are eliminated and forfeit their entry fees. The replacement player is added to the tournament and can compete for the full prize pool.

Each escalation level expands who can resolve the situation, guaranteeing that no match stalls indefinitely. The incentives shift from "claim the stalled match" to "become a participant and compete for the prize."

### 6.4 Economic Incentives for Resolution

The escalation system transforms stalling from a grief vector into various opportunities. If someone stalls:

**During Enrollment:**
- Enrolled players can force-start with fewer players (competing for the existing prize pool)
- External observers can claim the **entire abandoned prize pool** for themselves

**During Matches:**
- The opponent benefits (free win and tournament advancement)
- Advanced players benefit (unblocking their path to the finals and prize pool)
- External observers benefit (**they can join the tournament mid-competition** and potentially win the entire prize)

The incentive structure is designed so that everyone except the staller has reason to resolve the situation. For enrollment timeouts, the reward is direct and substantial (the full pool). For match timeouts, the reward is participation. The chance to compete for prizes in a tournament you didn't have to pay to enter.

This alignment ensures rapid resolution without requiring centralized intervention.

---

## 7. Trust and Verification

### 7.1 Fully On-Chain Execution

Every piece of ETour logic executes on Arbitrum:

- Enrollment and matchmaking
- Move validation and game rules
- Win detection and tournament progression
- Prize calculation and distribution

No off-chain server decides outcomes. No oracle reports results. No backend can be compromised. The smart contract is the complete system.

### 7.2 No Admin Override

The owner address can withdraw accumulated operational fees. It cannot:

- Modify game rules mid-tournament
- Override match results
- Freeze player funds
- Change fee percentages
- Pause the protocol

Once deployed, the contract operates autonomously according to its code. Even the developer cannot intervene in active competitions.

### 7.3 Deterministic Outcomes

Given identical inputs, ETour always produces identical outputs. There is no:

- Random number generation affecting outcomes (games are skill-only)
- Oracle data influencing results
- External calls to other contracts that could fail
- Admin discretion in any decision

This determinism enables complete verification. Anyone can reconstruct a tournament's history from emitted events and transaction logs to confirm the outcome matches.

### 7.4 Open Source Verification

All contract code is verified on Arbiscan. Players can:

- Read the exact code governing their competition
- Verify fee percentages match documentation
- Confirm no hidden admin functions exist
- Audit game rules for fairness

No trust required. Verification is available to anyone willing to read Solidity.

---

## 8. RW3 Compliance

### 8.1 The Five Principles

ETour is built according to RW3 (Reclaim Web3) principles. A movement committed to rebuilding blockchain applications that deliver genuine utility without compromising decentralization:

1. **Real Utility** — Solve an actual problem, not a manufactured one
2. **Fully On-Chain** — Execute core logic on blockchain, not centralized servers
3. **Self-Sustaining** — Generate revenue from usage, not token speculation
4. **Fair Distribution** — No pre-mine, insider allocations, or VC extraction
5. **No Altcoins** — Use established currencies (ETH), don't create new tokens

### 8.2 How ETour Meets Each Principle

**Real Utility:**
ETour enables skill-based competition with guaranteed fair outcomes and instant payouts. Players get something that centralized platforms can't give them: absolute certainty that nobody can cheat, steal funds, or manipulate results.

**Fully On-Chain:**
All tournament logic, game rules, and financial operations execute via smart contract. The only off-chain component is this interface which is purely cosmetic. A different frontend, or direct contract interaction, produces exactly the same results.

**Self-Sustaining:**
The 10% operational fee funds ongoing development and hosting costs. No external funding required. No token sales. No investor extraction.

**Fair Distribution:**
There are no tokens to distribute. All ETH in prize pools comes from player entry fees in that specific tournament. No insiders. No early advantages.

**No Altcoins:**
ETour uses only ETH. No governance tokens. No utility tokens. No "reward tokens." Just the native currency of Arbitrum.

---

## 9. Technical Specification

### 9.1 Contract Structure

```
ETour.sol (abstract)
├── State Management
│   ├── Tier configuration
│   ├── Tournament instances
│   ├── Round tracking
│   └── Player statistics
├── Enrollment Logic
│   ├── Fee processing
│   ├── Player registration
│   └── Timeout escalation
├── Tournament Management
│   ├── Round initialization
│   ├── Match advancement
│   └── Winner determination
├── Prize Distribution
│   ├── Ranking calculation
│   ├── Prize calculation
│   └── Payout execution
└── Abstract Functions (game-specific)
    ├── _createMatchGame
    ├── _resetMatchGame
    ├── _getMatchResult
    └── ... (others)
```

### 9.2 Key Data Structures

**TierConfig:**
```solidity
struct TierConfig {
    uint8 playerCount;
    uint8 instanceCount;
    uint256 entryFee;
    Mode mode;
    uint256 enrollmentWindow;
    uint256 matchMoveTimeout;
    uint256 escalationInterval;
    uint8 totalRounds;
    bool initialized;
}
```

**TournamentInstance:**
```solidity
struct TournamentInstance {
    uint8 tierId;
    uint8 instanceId;
    TournamentStatus status;
    Mode mode;
    uint8 currentRound;
    uint8 enrolledCount;
    uint256 prizePool;
    uint256 startTime;
    address winner;
    address coWinner;
    bool finalsWasDraw;
    bool allDrawResolution;
    uint8 allDrawRound;
    EnrollmentTimeoutState enrollmentTimeout;
    bool hasStartedViaTimeout;
    // ... additional tracking fields
}
```

**PlayerStats:**
```solidity
struct PlayerStats {
    uint256 tournamentsWon;
    uint256 tournamentsPlayed;
    uint256 matchesWon;
    uint256 matchesPlayed;
}
```

**Permanent Earnings Tracking:**
```solidity
// Prize amount each player received per tournament (permanent, never deleted)
mapping(uint8 => mapping(uint8 => mapping(address => uint256))) public playerPrizes;

// Net earnings per player across ALL tournaments (prizes minus entry fees)
mapping(address => int256) public playerEarnings;

// All players who have ever participated (for leaderboard)
address[] internal _leaderboardPlayers;
```

**LeaderboardEntry:**
```solidity
struct LeaderboardEntry {
    address player;
    int256 earnings;  // Net profit/loss across all tournaments
}
```

### 9.3 Core Functions

**Enrollment:**
```solidity
function enrollInTournament(uint8 tierId, uint8 instanceId) external payable
```

**Force Start (after enrollment timeout):**
```solidity
function forceStartTournament(uint8 tierId, uint8 instanceId) external
```

**Claim Abandoned Enrollment:**
```solidity
function claimAbandonedEnrollmentPool(uint8 tierId, uint8 instanceId) external
```

**View Functions:**
```solidity
function getTournamentInfo(uint8 tierId, uint8 instanceId) external view 
    returns (TournamentStatus, Mode, uint8 currentRound, uint8 enrolledCount, uint256 prizePool, address winner)

function getPlayerStats(address player) external view 
    returns (uint256 tournamentsWon, uint256 tournamentsPlayed, uint256 matchesWon, uint256 matchesPlayed)

function getTierOverview(uint8 tierId) external view 
    returns (TournamentStatus[] memory, uint8[] memory enrolledCounts, uint256[] memory prizePools)
```

### 9.4 Events

ETour emits comprehensive events for frontend integration and historical analysis:

```solidity
event TierRegistered(uint8 indexed tierId, uint8 playerCount, uint8 instanceCount, uint256 entryFee);
event TournamentInitialized(uint8 indexed tierId, uint8 indexed instanceId);
event PlayerEnrolled(uint8 indexed tierId, uint8 indexed instanceId, address indexed player, uint8 enrolledCount);
event TournamentStarted(uint8 indexed tierId, uint8 indexed instanceId, uint8 playerCount);
event MatchStarted(uint8 indexed tierId, uint8 indexed instanceId, uint8 roundNumber, uint8 matchNumber, address player1, address player2);
event MatchCompleted(bytes32 indexed matchId, address winner, bool isDraw);
event RoundCompleted(uint8 indexed tierId, uint8 indexed instanceId, uint8 roundNumber);
event TournamentCompleted(uint8 indexed tierId, uint8 indexed instanceId, address winner, uint256 prizeAmount, bool finalsWasDraw, address coWinner);
event PrizeDistributed(uint8 indexed tierId, uint8 indexed instanceId, address indexed player, uint8 rank, uint256 amount);
event TimeoutVictoryClaimed(uint8 indexed tierId, uint8 indexed instanceId, uint8 roundNum, uint8 matchNum, address indexed winner, address loser);
event TournamentCached(uint8 indexed tierId, uint8 indexed instanceId, address winner);  // Emitted when earnings are recorded
event PlayerForfeited(uint8 indexed tierId, uint8 indexed instanceId, address indexed player, uint256 amount, string reason);
```

**Leaderboard View Functions:**
```solidity
function getLeaderboard() external view returns (LeaderboardEntry[] memory);
function getLeaderboardCount() external view returns (uint256);
```

### 9.5 Gas Optimization

ETour employs several gas optimization strategies:

- **Packed structs** — Related small values share storage slots
- **Minimal storage writes** — Derived values computed rather than stored
- **Efficient mappings** — Direct lookups rather than array iteration
- **Bounded loops** — All iterations have known maximum bounds
- **Selective permanent storage** — Only essential historical data (`playerPrizes`, `playerEarnings`) is stored permanently; detailed match history is reconstructable from events

Typical gas costs on Arbitrum:

| Operation | Gas Units | Cost @ 0.1 gwei |
|-----------|-----------|-----------------|
| Enroll | ~150,000 | ~0.000015 ETH |
| Make Move | ~80,000 | ~0.000008 ETH |
| Claim Timeout | ~120,000 | ~0.000012 ETH |

These costs are negligible relative to entry fees, ensuring game economics aren't dominated by transaction costs.

---

## 10. Conclusion

ETour Protocol demonstrates that blockchain gaming can focus on games rather than financial mechanisms. By accepting blockchain's constraints: transparency, determinism, discrete transactions, and building games that naturally fit within them. We've created infrastructure for genuine skill-based competition.

The three flagship games serve different audiences and skill levels:

- **Tic-Tac-Toe** welcomes newcomers with familiar rules and low stakes
- **Chess** provides serious competition for strategic players
- **Connect Four** offers tactical depth with faster resolution

All three share the same guarantees: fair play, instant payouts, no cheating possible.

For players, the message is simple: **Think you're good? Prove it.**

For developers, ETour offers battle-tested tournament infrastructure. Build your game's rules; we handle the rest.

For skeptics, all code is open source and verified. **Trust nothing. Verify everything.**

This is what Web3 gaming should have been from the start: technology enabling experiences that weren't possible before, rather than technology demanding attention for its own sake.

---

## Appendix A: Complete Implementation Walkthrough

This appendix provides a comprehensive, step-by-step guide to building a game on ETour, using **TicTacChain** (our production Tic-Tac-Toe implementation) as the reference example. By the end, you'll understand exactly how to take a game from idea to deployed smart contract.

### A.1 Prerequisites

Before starting, ensure you have:

- **Solidity ^0.8.20** development environment (Hardhat or Foundry)
- **OpenZeppelin Contracts** for ReentrancyGuard
- **ETour.sol** abstract contract
- Basic understanding of smart contract development

### A.2 Step 1: Define Your Game's Data Structures

First, define the structures that represent your game's state. For TicTacChain:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ETour.sol";

contract TicTacChain is ETour {

    // ============ Game-Specific Constants ============
    uint8 public constant NO_CELL = 255;

    // ============ Game-Specific Enums ============
    enum Cell { Empty, X, O }

    // ============ Game-Specific Structs ============
    struct Match {
        address player1;
        address player2;
        address currentTurn;
        address winner;
        Cell[9] board;              // 3x3 board as flat array
        MatchStatus status;         // From ETour
        uint256 lastMoveTime;
        uint256 startTime;
        address firstPlayer;
        bool isDraw;
        MatchTimeoutState timeoutState;  // From ETour
        bool isTimedOut;
        address timeoutClaimant;
    }

    // ============ Game-Specific State ============
    mapping(bytes32 => Match) public matches;
```

**Key Design Decisions:**
- Use `bytes32` match IDs (generated by ETour's `_getMatchId()`)
- Include all ETour-required fields: `player1`, `player2`, `winner`, `status`, `isDraw`, `timeoutState`
- Add game-specific fields: `board`, `currentTurn`, `firstPlayer`

### A.3 Step 2: Configure Tournament Tiers

In your constructor, register the tournament tiers your game will support. This is where you define entry fees, player counts, prize distributions, and timeout configurations:

```solidity
constructor() ETour() {
    _registerTicTacChainTiers();
}

function _registerTicTacChainTiers() internal {
    // ============ Tier 0: 2-Player (Entry Level) ============
    // Simple head-to-head, winner takes all
    uint8[] memory tier0Prizes = new uint8[](2);
    tier0Prizes[0] = 100;  // 1st place: 100%
    tier0Prizes[1] = 0;    // 2nd place: 0%

    _registerTier(
        0,                      // tierId
        2,                      // playerCount
        64,                     // instanceCount (64 concurrent tournaments)
        0.001 ether,            // entryFee
        Mode.Classic,           // mode
        2 minutes,              // enrollmentWindow
        1 minutes,              // matchMoveTimeout
        1 minutes,              // escalationInterval
        tier0Prizes             // prizeDistribution
    );

    // ============ Tier 1: 4-Player ============
    // Semi-final + Final bracket
    uint8[] memory tier1Prizes = new uint8[](4);
    tier1Prizes[0] = 60;   // 1st: 60%
    tier1Prizes[1] = 30;   // 2nd: 30%
    tier1Prizes[2] = 10;   // 3rd: 10%
    tier1Prizes[3] = 0;    // 4th: 0%

    _registerTier(
        1,                      // tierId
        4,                      // playerCount
        10,                     // instanceCount
        0.002 ether,            // entryFee
        Mode.Classic,
        2 minutes,
        1 minutes,
        1 minutes,
        tier1Prizes
    );

    // ============ Tier 2: 8-Player ============
    uint8[] memory tier2Prizes = new uint8[](8);
    tier2Prizes[0] = 50;   // 1st
    tier2Prizes[1] = 25;   // 2nd
    tier2Prizes[2] = 15;   // 3rd
    tier2Prizes[3] = 10;   // 4th
    tier2Prizes[4] = 0;    // 5th-8th
    tier2Prizes[5] = 0;
    tier2Prizes[6] = 0;
    tier2Prizes[7] = 0;

    _registerTier(
        2,                      // tierId
        8,                      // playerCount
        16,                     // instanceCount
        0.004 ether,            // entryFee
        Mode.Classic,
        2 minutes,
        1 minutes,
        1 minutes,
        tier2Prizes
    );
}
```

**Tier Configuration Parameters Explained:**
| Parameter | Description |
|-----------|-------------|
| `tierId` | Unique identifier (0, 1, 2, ...) |
| `playerCount` | Players per tournament (should be power of 2) |
| `instanceCount` | Concurrent tournaments at this tier |
| `entryFee` | Cost to enter in wei |
| `mode` | `Mode.Classic` or `Mode.Pro` |
| `enrollmentWindow` | Time before force-start becomes available |
| `matchMoveTimeout` | Time per move before opponent can claim timeout |
| `escalationInterval` | Time between escalation levels |
| `prizeDistribution` | Array of percentages (must sum to 100) |

### A.4 Step 3: Implement Abstract Functions

ETour requires you to implement several abstract functions that bridge the protocol's tournament mechanics with your game's logic:

#### A.4.1 `_createMatchGame` — Initialize a New Match

Called by ETour when two players are paired for a match:

```solidity
function _createMatchGame(
    uint8 tierId,
    uint8 instanceId,
    uint8 roundNumber,
    uint8 matchNumber,
    address player1,
    address player2
) internal override {
    require(player1 != player2, "Cannot match player against themselves");
    require(player1 != address(0) && player2 != address(0), "Invalid player");

    bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
    Match storage matchData = matches[matchId];

    // Set players
    matchData.player1 = player1;
    matchData.player2 = player2;
    matchData.status = MatchStatus.InProgress;
    matchData.lastMoveTime = block.timestamp;
    matchData.startTime = block.timestamp;
    matchData.isDraw = false;

    // Randomly determine who goes first
    uint256 randomness = uint256(keccak256(abi.encodePacked(
        block.prevrandao,
        block.timestamp,
        player1,
        player2,
        matchId
    )));
    matchData.currentTurn = (randomness % 2 == 0) ? player1 : player2;
    matchData.firstPlayer = matchData.currentTurn;

    // Initialize empty board
    for (uint8 i = 0; i < 9; i++) {
        matchData.board[i] = Cell.Empty;
    }

    // Initialize timeout state (ETour helper)
    _initializeMatchTimeoutState(matchId, tierId);

    emit MatchStarted(tierId, instanceId, roundNumber, matchNumber, player1, player2);
}
```

#### A.4.2 `_resetMatchGame` — Clean Up After Match

Called when a tournament resets to prepare for new enrollment:

```solidity
function _resetMatchGame(bytes32 matchId) internal override {
    Match storage matchData = matches[matchId];

    matchData.player1 = address(0);
    matchData.player2 = address(0);
    matchData.currentTurn = address(0);
    matchData.winner = address(0);
    matchData.status = MatchStatus.NotStarted;
    matchData.lastMoveTime = 0;
    matchData.startTime = 0;
    matchData.firstPlayer = address(0);
    matchData.isDraw = false;
    matchData.isTimedOut = false;
    matchData.timeoutClaimant = address(0);

    // Reset timeout state
    matchData.timeoutState.escalation1Start = 0;
    matchData.timeoutState.escalation2Start = 0;
    matchData.timeoutState.escalation3Start = 0;
    matchData.timeoutState.activeEscalation = EscalationLevel.None;
    matchData.timeoutState.timeoutActive = false;

    // Clear board
    for (uint8 i = 0; i < 9; i++) {
        matchData.board[i] = Cell.Empty;
    }
}
```

#### A.4.3 `_getMatchResult` — Return Match Outcome

ETour calls this to determine match results for bracket progression:

```solidity
function _getMatchResult(bytes32 matchId)
    internal view override
    returns (address winner, bool isDraw, MatchStatus status)
{
    Match storage matchData = matches[matchId];
    return (matchData.winner, matchData.isDraw, matchData.status);
}
```

#### A.4.4 `_getMatchPlayers` — Return Player Addresses

```solidity
function _getMatchPlayers(bytes32 matchId)
    internal view override
    returns (address player1, address player2)
{
    Match storage matchData = matches[matchId];
    return (matchData.player1, matchData.player2);
}
```

#### A.4.5 `_completeMatchWithResult` — Finalize Match

Called when match ends (win, draw, or timeout):

```solidity
function _completeMatchWithResult(bytes32 matchId, address winner, bool isDraw)
    internal override
{
    Match storage matchData = matches[matchId];
    matchData.status = MatchStatus.Completed;
    matchData.winner = winner;
    matchData.isDraw = isDraw;
}
```

#### A.4.6 Timeout State Management

These functions integrate with ETour's anti-stalling system:

```solidity
function _setMatchTimeoutState(bytes32 matchId, MatchTimeoutState memory state)
    internal override
{
    matches[matchId].timeoutState = state;
}

function _getMatchTimeoutState(bytes32 matchId)
    internal view override
    returns (MatchTimeoutState memory)
{
    return matches[matchId].timeoutState;
}

function _setMatchTimedOut(bytes32 matchId, address claimant, EscalationLevel level)
    internal override
{
    Match storage matchData = matches[matchId];
    matchData.isTimedOut = true;
    matchData.timeoutClaimant = claimant;
    matchData.timeoutState.activeEscalation = level;
    matchData.timeoutState.timeoutActive = true;
}

function _setMatchPlayer(bytes32 matchId, uint8 slot, address player)
    internal override
{
    Match storage matchData = matches[matchId];
    if (slot == 0) {
        matchData.player1 = player;
    } else {
        matchData.player2 = player;
    }
}

function _initializeMatchForPlay(bytes32 matchId, uint8 tierId) internal override {
    Match storage matchData = matches[matchId];
    matchData.status = MatchStatus.InProgress;
    matchData.lastMoveTime = block.timestamp;
    matchData.startTime = block.timestamp;

    // Random first player
    uint256 randomness = uint256(keccak256(abi.encodePacked(
        block.prevrandao, block.timestamp, matchData.player1, matchData.player2, matchId
    )));
    matchData.firstPlayer = (randomness % 2 == 0) ? matchData.player1 : matchData.player2;
    matchData.currentTurn = matchData.firstPlayer;

    // Clear board
    for (uint8 i = 0; i < 9; i++) {
        matchData.board[i] = Cell.Empty;
    }

    _initializeMatchTimeoutState(matchId, tierId);
}
```

### A.5 Step 4: Implement Game Logic

Now implement your game's core mechanics. For Tic-Tac-Toe:

#### A.5.1 The Move Function

```solidity
event MoveMade(bytes32 indexed matchId, address indexed player, uint8 cellIndex);

function makeMove(
    uint8 tierId,
    uint8 instanceId,
    uint8 roundNumber,
    uint8 matchNumber,
    uint8 cellIndex
) external nonReentrant {
    bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
    Match storage matchData = matches[matchId];

    // Validation
    require(matchData.status == MatchStatus.InProgress, "Match not active");
    require(msg.sender == matchData.player1 || msg.sender == matchData.player2, "Not a player");
    require(msg.sender == matchData.currentTurn, "Not your turn");
    require(cellIndex < 9, "Invalid cell index");
    require(matchData.board[cellIndex] == Cell.Empty, "Cell occupied");

    // Make the move
    matchData.board[cellIndex] = (msg.sender == matchData.player1) ? Cell.X : Cell.O;
    matchData.lastMoveTime = block.timestamp;

    // Reset timeout timer
    _initializeMatchTimeoutState(matchId, tierId);

    emit MoveMade(matchId, msg.sender, cellIndex);

    // Check for win
    if (_checkWin(matchData.board)) {
        _completeMatch(tierId, instanceId, roundNumber, matchNumber, msg.sender, false);
        return;
    }

    // Check for draw
    if (_checkDraw(matchData.board)) {
        _completeMatch(tierId, instanceId, roundNumber, matchNumber, address(0), true);
        return;
    }

    // Switch turns
    matchData.currentTurn = (matchData.currentTurn == matchData.player1)
        ? matchData.player2
        : matchData.player1;
}
```

#### A.5.2 Win Detection

```solidity
function _checkWin(Cell[9] memory board) internal pure returns (bool) {
    // All winning lines: rows, columns, diagonals
    uint8[3][8] memory lines = [
        [uint8(0), 1, 2], [3, 4, 5], [6, 7, 8],  // Rows
        [uint8(0), 3, 6], [1, 4, 7], [2, 5, 8],  // Columns
        [uint8(0), 4, 8], [2, 4, 6]              // Diagonals
    ];

    for (uint256 i = 0; i < 8; i++) {
        uint8 a = lines[i][0];
        uint8 b = lines[i][1];
        uint8 c = lines[i][2];

        if (board[a] != Cell.Empty && board[a] == board[b] && board[b] == board[c]) {
            return true;
        }
    }
    return false;
}

function _checkDraw(Cell[9] memory board) internal pure returns (bool) {
    for (uint256 i = 0; i < 9; i++) {
        if (board[i] == Cell.Empty) return false;
    }
    return true;
}
```

### A.6 Step 5: Implement Timeout Claims

Allow players to claim victory when opponent times out:

```solidity
function claimTimeoutWin(
    uint8 tierId,
    uint8 instanceId,
    uint8 roundNumber,
    uint8 matchNumber
) external nonReentrant {
    bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
    Match storage matchData = matches[matchId];

    require(matchData.status == MatchStatus.InProgress, "Match not active");
    require(msg.sender == matchData.player1 || msg.sender == matchData.player2, "Not a player");
    require(msg.sender != matchData.currentTurn, "Cannot claim on your turn");
    require(block.timestamp >= matchData.timeoutState.escalation1Start, "Timeout not reached");

    matchData.isTimedOut = true;
    matchData.timeoutClaimant = msg.sender;
    matchData.timeoutState.activeEscalation = EscalationLevel.Escalation1_OpponentClaim;

    address loser = (msg.sender == matchData.player1) ? matchData.player2 : matchData.player1;

    emit TimeoutVictoryClaimed(tierId, instanceId, roundNumber, matchNumber, msg.sender, loser);

    _completeMatch(tierId, instanceId, roundNumber, matchNumber, msg.sender, false);
}
```

### A.7 Step 6: Add View Functions

Provide functions for frontends to read game state:

```solidity
function getMatch(
    uint8 tierId,
    uint8 instanceId,
    uint8 roundNumber,
    uint8 matchNumber
) external view returns (
    address player1,
    address player2,
    address currentTurn,
    address winner,
    Cell[9] memory board,
    MatchStatus status,
    bool isDraw,
    uint256 startTime,
    uint256 lastMoveTime,
    address firstPlayer
) {
    bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
    Match storage matchData = matches[matchId];
    return (
        matchData.player1,
        matchData.player2,
        matchData.currentTurn,
        matchData.winner,
        matchData.board,
        matchData.status,
        matchData.isDraw,
        matchData.startTime,
        matchData.lastMoveTime,
        matchData.firstPlayer
    );
}
```

### A.8 Step 7: Deploy and Test

#### A.8.1 Deployment Script (Hardhat)

```javascript
const { ethers } = require("hardhat");

async function main() {
    const TicTacChain = await ethers.getContractFactory("TicTacChain");
    const contract = await TicTacChain.deploy();
    await contract.waitForDeployment();

    console.log("TicTacChain deployed to:", await contract.getAddress());
}

main().catch(console.error);
```

#### A.8.2 Testing Flow

```javascript
// 1. Player A enrolls
await contract.connect(playerA).enrollInTournament(0, 0, { value: ethers.parseEther("0.001") });

// 2. Player B enrolls (tournament auto-starts with 2 players)
await contract.connect(playerB).enrollInTournament(0, 0, { value: ethers.parseEther("0.001") });

// 3. Get match info
const match = await contract.getMatch(0, 0, 0, 0);
console.log("Current turn:", match.currentTurn);

// 4. Players make moves
await contract.connect(playerA).makeMove(0, 0, 0, 0, 4); // Center
await contract.connect(playerB).makeMove(0, 0, 0, 0, 0); // Corner
await contract.connect(playerA).makeMove(0, 0, 0, 0, 1); // Top middle
await contract.connect(playerB).makeMove(0, 0, 0, 0, 7); // Block
await contract.connect(playerA).makeMove(0, 0, 0, 0, 2); // Win (if available)

// 5. Check result
const result = await contract.getMatch(0, 0, 0, 0);
console.log("Winner:", result.winner);
```

### A.9 Frontend Integration

The frontend connects to your deployed contract using ethers.js:

```javascript
import { ethers } from 'ethers';
import CONTRACT_ABI from './TicTacChainABI.json';

const CONTRACT_ADDRESS = "0x..."; // Your deployed address

// Connect wallet
const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

// Enroll in tournament
const entryFee = ethers.parseEther("0.001");
const tx = await contract.enrollInTournament(0, 0, { value: entryFee });
await tx.wait();

// Make a move
const moveTx = await contract.makeMove(0, 0, 0, 0, 4); // Center cell
await moveTx.wait();

// Read match state
const match = await contract.getMatch(0, 0, 0, 0);
console.log("Board:", match.board);
console.log("Current turn:", match.currentTurn);
```

### A.10 Complete Implementation Checklist

Use this checklist when building your ETour game:

- [ ] **Contract Setup**
  - [ ] Import ETour.sol
  - [ ] Inherit from ETour
  - [ ] Define game-specific enums and structs

- [ ] **Tier Configuration**
  - [ ] Define prize distributions (must sum to 100)
  - [ ] Choose appropriate timeouts for your game
  - [ ] Register all tiers in constructor

- [ ] **Abstract Functions**
  - [ ] `_createMatchGame` — Initialize game state
  - [ ] `_resetMatchGame` — Clean up match data
  - [ ] `_getMatchResult` — Return winner/draw/status
  - [ ] `_getMatchPlayers` — Return player addresses
  - [ ] `_completeMatchWithResult` — Finalize match
  - [ ] `_setMatchTimeoutState` — Update timeout state
  - [ ] `_getMatchTimeoutState` — Read timeout state
  - [ ] `_setMatchTimedOut` — Mark match as timed out
  - [ ] `_setMatchPlayer` — Assign player to slot
  - [ ] `_initializeMatchForPlay` — Prepare for active play
  - [ ] `_addToMatchCacheGame` — Optional: cache match for history

- [ ] **Game Logic**
  - [ ] Move validation function
  - [ ] Win condition detection
  - [ ] Draw condition detection
  - [ ] Turn management

- [ ] **Timeout Integration**
  - [ ] Call `_initializeMatchTimeoutState` after each move
  - [ ] Implement `claimTimeoutWin` function

- [ ] **View Functions**
  - [ ] Match state getter
  - [ ] Board/game state getter

- [ ] **Events**
  - [ ] MoveMade event
  - [ ] Game-specific events as needed

- [ ] **Testing**
  - [ ] Full game flow (enroll → play → win)
  - [ ] Draw scenario
  - [ ] Timeout scenario
  - [ ] Multi-round tournament

- [ ] **Deployment**
  - [ ] Deploy to testnet
  - [ ] Verify contract on explorer
  - [ ] Deploy to mainnet (Arbitrum One)

---

## Appendix B: Economic Projections

Conservative scenario (1,000 daily active players):

| Metric | Daily | Monthly | Yearly |
|--------|-------|---------|--------|
| Tournaments | 300 | 9,000 | 108,000 |
| Entry Volume | 3 ETH | 90 ETH | 1,080 ETH |
| Prize Pools | 2.7 ETH | 81 ETH | 972 ETH |
| Operational Revenue | 0.3 ETH | 9 ETH | 108 ETH |

At ETH = $2,000, this yields ~$216,000/year operational revenue. It's more than sufficient for hosting, development, and maintenance.

Growth scenario (10,000 daily active players):

| Metric | Daily | Monthly | Yearly |
|--------|-------|---------|--------|
| Tournaments | 3,000 | 90,000 | 1,080,000 |
| Entry Volume | 30 ETH | 900 ETH | 10,800 ETH |
| Prize Pools | 27 ETH | 810 ETH | 9,720 ETH |
| Operational Revenue | 3 ETH | 90 ETH | 1,080 ETH |

At scale, operational revenue provides significant runway for development, audits, and ecosystem growth—all funded by actual usage rather than speculation.

---

**Contract Addresses:** [To be added upon deployment]  
**Source Code:** [GitHub repository]  
**Frontend:** [etour.games]  
**RW3 Manifesto:** [reclaimweb3.com]

---

*This whitepaper describes ETour Protocol as designed for deployment on Arbitrum One. The protocol operates autonomously according to its smart contract code. This document is for informational purposes and does not constitute financial advice.*


------ 

pkill -f anvil || true

./start-anvil.sh

npx hardhat compile

npx hardhat clean && npx hardhat compile

npx hardhat run scripts/deploy-modules.js --network localhost
npx hardhat run scripts/deploy-tictacchain-modular.js --network localhost
npx hardhat run scripts/deploy-chessonchain-modular.js --network localhost
npx hardhat run scripts/deploy-connectfour-modular.js --network localhost

ngrok http 8545


-----

Step 1: Nuke Anvil
pkill -9 anvil
./start-anvil.sh

Step 2: Clean Everything
rm -rf artifacts/ && rm -rf cache/ && rm -f deployments/*.json

Step 3: Fresh Compilation
npx hardhat clean && npx hardhat compile

Step 4: Deploy Modules + ChessOnChain
npx hardhat run scripts/deploy-tictacchain-modular.js --network localhost
npx hardhat run scripts/deploy-chessonchain-modular.js --network localhost
npx hardhat run scripts/deploy-connectfour-modular.js --network localhost



-----


npx hardhat verify --network arbitrum  

npx hardhat verify --network arbitrum 0x05fF11E8440ffD9309724514eCa424B94c889Fff && npx hardhat verify --network arbitrum 0x9a67220ea3F428d318A3403157D7c31C8dBcee8E && npx hardhat verify --network arbitrum 0x54D7051DaFD5F5ec9FFe9b61131518ccC5eb774B && npx hardhat verify --network arbitrum 0xc98E58D53C998648D8CF176938cc77fb9C6a7Bc5 && npx hardhat verify --network arbitrum 0x24B9Cdf557731a3EF154E212C9ead42A15647708 && npx hardhat verify --network arbitrum 0x092a20D91Af8BEcA18BA195b112401Be267A175a

npx hardhat verify --network arbitrum 0xf8797f178130AD4125fD054C0621c809de178644 "0x05fF11E8440ffD9309724514eCa424B94c889Fff" "0x9a67220ea3F428d318A3403157D7c31C8dBcee8E" "0x54D7051DaFD5F5ec9FFe9b61131518ccC5eb774B" "0xc98E58D53C998648D8CF176938cc77fb9C6a7Bc5" "0x24B9Cdf557731a3EF154E212C9ead42A15647708" 
                                                                                                    
npx hardhat verify --network arbitrum 0x870ac029D3951359B4faA7a20A54a9397335639B "0x05fF11E8440ffD9309724514eCa424B94c889Fff" "0x9a67220ea3F428d318A3403157D7c31C8dBcee8E" "0x54D7051DaFD5F5ec9FFe9b61131518ccC5eb774B" "0xc98E58D53C998648D8CF176938cc77fb9C6a7Bc5" "0x24B9Cdf557731a3EF154E212C9ead42A15647708" "0x092a20D91Af8BEcA18BA195b112401Be267A175a"


npx hardhat verify --network arbitrum 0xb39e8f27D522C8AB4f9105123D1519a142598CA0 "0x05fF11E8440ffD9309724514eCa424B94c889Fff" "0x9a67220ea3F428d318A3403157D7c31C8dBcee8E" "0x54D7051DaFD5F5ec9FFe9b61131518ccC5eb774B" "0xc98E58D53C998648D8CF176938cc77fb9C6a7Bc5" "0x24B9Cdf557731a3EF154E212C9ead42A15647708" 
