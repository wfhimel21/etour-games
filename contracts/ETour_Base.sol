// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ETour_Base
 * @dev Abstract base contract defining ALL storage layout and core functionality for ETour protocol
 *
 * CRITICAL: Storage layout must remain IDENTICAL to original ETour.sol
 * - Game contracts inherit this to define their storage
 * - Modules execute via delegatecall and access this storage
 * - NEVER reorder variables or add variables between existing ones
 *
 * Part of the modular ETour architecture where:
 * - This contract: Defines storage layout and shared logic
 * - Module contracts: Pure logic (no storage)
 * - Game contracts: Own storage + delegate to modules
 */
abstract contract ETour_Base is ReentrancyGuard {

    // ============ Module Addresses (Immutable) ============

    address public immutable MODULE_CORE;
    address public immutable MODULE_MATCHES;
    address public immutable MODULE_PRIZES;
    address public immutable MODULE_RAFFLE;
    address public immutable MODULE_ESCALATION;

    // ============ Delegatecall Protection ============

    /// @dev Stores the address of this contract for delegatecall detection
    /// Used by modules to ensure they're only called via delegatecall
    address private immutable _self;

    // ============ Constants & Immutables ============

    address public immutable owner;

    // Fee distribution constants (in basis points, 10000 = 100%)
    uint256 public constant PARTICIPANTS_SHARE_BPS = 9000;  // 90% to prize pool
    uint256 public constant OWNER_SHARE_BPS = 750;          // 7.5% to owner
    uint256 public constant PROTOCOL_SHARE_BPS = 250;       // 2.5% to protocol
    uint256 public constant BASIS_POINTS = 10000;           // 100%

    // Sentinel values
    uint8 public constant NO_ROUND = 255;

    // ============ Enums ============

    enum TournamentStatus { Enrolling, InProgress, Completed }
    enum MatchStatus { NotStarted, InProgress, Completed }
    // REMOVED: Mode enum - not used for any logic

    enum EscalationLevel {
        None,
        Escalation1_OpponentClaim,
        Escalation2_AdvancedPlayers,
        Escalation3_ExternalPlayers
    }

    enum CompletionReason {
        NormalWin,                  // 0: Normal gameplay win
        Timeout,                    // 1: Win by opponent timeout (ML1)
        Draw,                       // 2: Match/finals ended in a draw
        ForceElimination,           // 3: ML2 - Advanced players force eliminated both players
        Replacement,                // 4: ML3 - External player replaced stalled players
        AllDrawScenario,            // 5: All matches in a round resulted in draws (tournament only)
        SoloEnrollForceStart,       // 6: Solo enroller force started tournament (EL1)
        AbandonedTournamentClaimed  // 7: Abandoned tournament claimed by external player (EL2)
    }

    // ============ Configuration Structs ============

    /**
     * @dev Timeout configuration for escalation windows
     * All values in seconds
     */
    struct TimeoutConfig {
        uint256 matchTimePerPlayer;           // Time each player gets for entire match (e.g., 60 = 1 minute)
        uint256 timeIncrementPerMove;         // Fischer increment: bonus time added after each move
        uint256 matchLevel2Delay;             // Delay after player timeout before L2 (advanced players) active
        uint256 matchLevel3Delay;             // Delay after player timeout before L3 (anyone) active
        uint256 enrollmentWindow;             // Time to wait for tournament to fill before L1
        uint256 enrollmentLevel2Delay;        // Delay after L1 before L2 (external claim) active
    }

    /**
     * @dev Configuration for a single tournament tier
     * Provided by implementing contract via _registerTier()
     */
    struct TierConfig {
        uint8 playerCount;          // Number of players in tournament (must be power of 2 for brackets)
        uint8 instanceCount;        // How many concurrent instances of this tier
        uint256 entryFee;           // Entry fee in wei
        TimeoutConfig timeouts;     // Timeout configuration for escalation windows
        uint8 totalRounds;          // Calculated: log2(playerCount)
        bool initialized;           // Whether this tier has been configured
    }

    // ============ Tournament Structs ============

    struct TournamentInstance {
        uint8 tierId;
        uint8 instanceId;
        TournamentStatus status;
        uint8 currentRound;
        uint8 enrolledCount;
        uint256 prizePool;
        uint256 startTime;
        address winner;
        bool finalsWasDraw;
        bool allDrawResolution;
        uint8 allDrawRound;
        CompletionReason completionReason;
        EnrollmentTimeoutState enrollmentTimeout;
        uint8 actualTotalRounds;  // Actual rounds based on enrolled players (not tier max)
    }

    struct Round {
        uint8 totalMatches;
        uint8 completedMatches;
        bool initialized;
        uint8 drawCount;
        uint8 playerCount;  // Number of players entering this round (including bye players)
    }

    struct EnrollmentTimeoutState {
        uint256 escalation1Start;
        uint256 escalation2Start;
        EscalationLevel activeEscalation;
        uint256 forfeitPool;
    }

    /**
     * @dev Match-level timeout state for anti-stalling escalation
     * Tracks when a match becomes stalled and enables progressive intervention
     */
    struct MatchTimeoutState {
        uint256 escalation1Start;      // When Level 2 (advanced players) can act
        uint256 escalation2Start;      // When Level 3 (external players) can act
        EscalationLevel activeEscalation;
        bool isStalled;                // Set to true when a player runs out of time
    }

    /**
     * @dev Standardized match structure shared across all games
     * All games use this same structure for consistency
     * Game-specific fields (packedState, moves) may be unused in some games
     */
    struct Match {
        address player1;              // First player (White in Chess, X in TicTacToe, Red in ConnectFour)
        address player2;              // Second player (Black in Chess, O in TicTacToe, Yellow in ConnectFour)
        address winner;               // Winner address (address(0) if not determined)
        address currentTurn;          // Whose turn it is
        address firstPlayer;          // Who made the first move
        MatchStatus status;           // Current match status
        bool isDraw;                  // Whether match ended in a draw
        uint256 packedBoard;          // Packed board representation (game-specific encoding)
        uint256 packedState;          // Additional packed state (Chess-specific: castling rights, en passant, etc.)
        uint256 startTime;            // When the match started
        uint256 lastMoveTime;         // Timestamp of the last move
        uint256 player1TimeRemaining; // Time bank for player1
        uint256 player2TimeRemaining; // Time bank for player2
        string moves;                 // Move history (encoded representation of all moves for match replay)
    }

    /**
     * @dev Minimal tournament reference for player tracking
     * Gas-optimized: 2 bytes total (tierId + instanceId)
     */
    struct TournamentRef {
        uint8 tierId;
        uint8 instanceId;
    }

    /**
     * @dev Leaderboard entry for player earnings display
     * Used by getLeaderboard() view function
     */
    struct LeaderboardEntry {
        address player;
        int256 earnings;
    }

    /**
     * @dev Common match data shared across all game implementations
     * Used by standardized getMatch() function with automatic cache fallback
     */
    struct CommonMatchData {
        // Player Information
        address player1;
        address player2;
        address winner;
        address loser;          // Derived: (winner == player1) ? player2 : player1

        // Match State
        MatchStatus status;
        bool isDraw;

        // Timing
        uint256 startTime;
        uint256 lastMoveTime;

        // Tournament Context
        uint8 tierId;
        uint8 instanceId;
        uint8 roundNumber;
        uint8 matchNumber;

        // Data Source Indicator
        bool isCached;          // true = from cache, false = from active storage
    }

    /**
     * @dev Complete record of a finished match
     * Stores all essential data for a completed match including move history
     * Added to both players' match history arrays when match completes
     * Note: Draw status can be determined by checking if winner == address(0)
     */
    struct MatchRecord {
        // Tournament context
        uint8 tierId;
        uint8 instanceId;
        uint8 roundNumber;
        uint8 matchNumber;

        // Player info
        address player1;
        address player2;
        address winner;
        address firstPlayer;

        // Match state (at completion)
        MatchStatus status;         // Should always be Completed
        uint256 packedBoard;        // Final board state

        // Timing
        uint256 startTime;
        uint256 endTime;            // When match completed

        // Completion details
        CompletionReason completionReason;

        // Move history (encoded representation of all MoveMade events)
        string moves;
    }

    /**
     * @dev Complete record of a finished tournament
     * Stores all essential data for a completed tournament instance
     * Stored permanently in recentInstances[tierId][instanceId]
     * Note: tierId/instanceId are implicit from mapping keys
     */
    struct TournamentRecord {
        address[] players;              // Full list of enrolled players
        uint256 endTime;                // When tournament completed
        uint256 prizePool;
        address winner;
        CompletionReason completionReason;
    }

    /**
     * @dev Historic data for a single raffle execution
     * Stores minimal information - client can derive winnerPrize/protocolReserve/ownerShare from rafflePot
     */
    struct RaffleResult {
        address executor;               // Who called executeProtocolRaffle
        uint64 timestamp;               // When the raffle was executed (64-bit timestamp good until year 2554)
        uint256 rafflePot;              // Total raffle pot in wei (must support large ETH values)
        address[] participants;         // All addresses considered in the raffle
        uint16[] weights;               // Each address's enrollment count (max 65k enrollments per player)
        address winner;                 // The randomly selected winner
    }

    // ============ State Variables ============

    // Tier configuration - set by implementing contract
    uint8 public tierCount;
    mapping(uint8 => TierConfig) internal _tierConfigs;

    // Accumulated protocol share from failed prize distributions
    uint256 public accumulatedProtocolShare;

    // Raffle tracking
    uint256[] internal raffleThresholds;  // Configured thresholds (last element repeats for all future raffles)
    RaffleResult[] public raffleResults;  // Historic raffle execution data (array auto-provides length)

    // Tournament state
    mapping(uint8 => mapping(uint8 => TournamentInstance)) public tournaments;
    mapping(uint8 => mapping(uint8 => address[])) public enrolledPlayers;
    mapping(uint8 => mapping(uint8 => mapping(address => bool))) public isEnrolled;
    mapping(uint8 => mapping(uint8 => mapping(uint8 => Round))) public rounds;

    // Player data
    // Removed: playerRanking (no longer needed with winner-takes-all distribution)
    mapping(uint8 => mapping(uint8 => mapping(address => uint256))) public playerPrizes;
    mapping(uint8 => mapping(uint8 => mapping(uint8 => mapping(uint8 => mapping(address => bool))))) public drawParticipants;

    // Player earnings tracking (total winnings from prizes)
    mapping(address => int256) public playerEarnings;
    address[] internal _leaderboardPlayers;
    mapping(address => bool) internal _isOnLeaderboard;

    // Match-level timeout tracking for anti-stalling escalation
    mapping(bytes32 => MatchTimeoutState) public matchTimeouts;

    // Match data shared across all games
    mapping(bytes32 => Match) public matches;

    // Player match history - complete records of all finished matches
    // Internal to avoid stack depth issues with auto-generated getter
    // Access via events or client-side indexing
    mapping(address => MatchRecord[]) internal playerMatches;

    // Tournament history - most recent completed tournament per tier/instance
    // Stores permanent record of last tournament completion with full player list
    mapping(uint8 => mapping(uint8 => TournamentRecord)) public recentInstances;

    // ============ Events ============

    event TournamentEnrolled(address indexed player, uint8 tierId, uint8 instanceId);

    /**
     * @dev Emitted when a prize is distributed to a player
     * Mimics the Transfer event for better wallet display
     * @param from The game contract address distributing the prize
     * @param to The player receiving the prize
     * @param value The prize amount in wei
     */
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    // ============ Constructor ============

    constructor(
        address _moduleCoreAddress,
        address _moduleMatchesAddress,
        address _modulePrizesAddress,
        address _moduleRaffleAddress,
        address _moduleEscalationAddress
    ) {
        owner = msg.sender;
        MODULE_CORE = _moduleCoreAddress;
        MODULE_MATCHES = _moduleMatchesAddress;
        MODULE_PRIZES = _modulePrizesAddress;
        MODULE_RAFFLE = _moduleRaffleAddress;
        MODULE_ESCALATION = _moduleEscalationAddress;
        _self = address(this);
    }

    // ============ Modifiers ============

    /**
     * @dev Ensures function is only called via delegatecall from main contract
     * When called via delegatecall: address(this) = main contract, _self = module address ✓
     * When called directly: address(this) = module address, _self = module address ✗
     *
     * This prevents accidental or malicious direct calls to module functions
     * that should only be executed in the context of the main contract.
     */
    modifier onlyDelegateCall() {
        require(address(this) != _self, "Function must be called via delegatecall");
        _;
    }

    // ============ Helper Functions (Shared across modules) ============

    /**
     * @dev Generate unique match identifier
     * @param tierId Tournament tier
     * @param instanceId Instance within tier
     * @param roundNumber Round number
     * @param matchNumber Match number within round
     * @return Unique match ID
     */
    function _getMatchId(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tierId, instanceId, roundNumber, matchNumber));
    }

    /**
     * @dev Calculate log2 of a number (for bracket math)
     * @param x Input number
     * @return Log2 of x
     */
    function _log2(uint8 x) internal pure returns (uint8) {
        uint8 result = 0;
        while (x > 1) {
            x /= 2;
            result++;
        }
        return result;
    }

    /**
     * @dev Translate internal round number to actual bracket round
     * When a tournament is force-started with fewer players than configured,
     * the internal round numbers start at 0, but should be recorded as the
     * appropriate finals/semifinals round in the full bracket structure.
     *
     * Examples:
     * - 4-player tournament with 2 enrolled: internal round 0 → bracket round 1 (finals)
     * - 8-player tournament with 4 enrolled: internal round 0 → bracket round 1 (semifinals)
     * - 8-player tournament with 2 enrolled: internal round 0 → bracket round 2 (finals)
     * - Full tournament: internal round 0 → bracket round 0 (no translation needed)
     *
     * @param tierId Tournament tier
     * @param instanceId Instance within tier
     * @param internalRound The internal round number (starts at 0)
     * @return Actual bracket round number for historical records
     */
    function _translateToBracketRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 internalRound
    ) internal view returns (uint8) {
        TierConfig storage config = _tierConfigs[tierId];
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // If tournament is fully enrolled, no translation needed
        if (tournament.enrolledCount == config.playerCount) {
            return internalRound;
        }

        // Calculate the offset: how many rounds were skipped
        // Formula: totalRounds - log2(enrolledCount)
        uint8 enrolledLog = _log2(tournament.enrolledCount);
        uint8 roundOffset = config.totalRounds - enrolledLog;

        // Add the offset to get the actual bracket round
        return internalRound + roundOffset;
    }

    // Note: _getRaffleThreshold() and _countCompletedRaffles() removed
    // Logic inlined directly in getRaffleInfo() and executeProtocolRaffle()

    function _populateMatchRecord(
        MatchRecord storage r,
        Match storage m,
        uint8 t,
        uint8 i,
        uint8 rn,
        uint8 mn,
        CompletionReason cr
    ) internal {
        r.tierId = t;
        r.instanceId = i;
        // Translate internal round to actual bracket round for historical accuracy
        r.roundNumber = _translateToBracketRound(t, i, rn);
        r.matchNumber = mn;
        r.player1 = m.player1;
        r.player2 = m.player2;
        r.winner = m.winner;
        r.firstPlayer = m.firstPlayer;
        r.status = m.status;
        r.packedBoard = m.packedBoard;
        r.startTime = m.startTime;
        r.endTime = block.timestamp;
        r.completionReason = cr;
        r.moves = m.moves;
    }

    // Wrapper to add match record (simplifies 2-step push/populate pattern)
    function _addMatchRecord(
        address player,
        Match storage m,
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        CompletionReason reason
    ) internal {
        playerMatches[player].push();
        _populateMatchRecord(
            playerMatches[player][playerMatches[player].length - 1],
            m, tierId, instanceId, roundNumber, matchNumber, reason
        );
    }

    // Internal match completion handler
    function _completeMatchInternal(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address winner,
        bool isDraw,
        CompletionReason reason
    ) internal {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];

        // Set winner BEFORE populating records so MatchRecord captures correct winner
        // For draws, winner should always be address(0)
        m.winner = isDraw ? address(0) : winner;
        m.isDraw = isDraw;
        m.status = MatchStatus.Completed;

        // Record match in both players' history
        _addMatchRecord(m.player1, m, tierId, instanceId, roundNumber, matchNumber, reason);
        _addMatchRecord(m.player2, m, tierId, instanceId, roundNumber, matchNumber, reason);

        // Mark match as complete in game-specific storage (calls internal game-specific function)
        _completeMatchGameSpecific(tierId, instanceId, roundNumber, matchNumber, winner, isDraw);

        // Clear any escalation state - inlined for gas efficiency
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        timeout.isStalled = false;
        timeout.escalation1Start = 0;
        timeout.escalation2Start = 0;
        timeout.activeEscalation = EscalationLevel.None;

        // Save enrolled players before delegatecall (in case tournament completes and resets)
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        // Delegate to Matches module for advancement logic
        (bool completeSuccess, ) = MODULE_MATCHES.delegatecall(
            abi.encodeWithSignature(
                "completeMatch(uint8,uint8,uint8,uint8,address,bool,uint8)",
                tierId, instanceId, roundNumber, matchNumber, winner, isDraw, reason
            )
        );
        require(completeSuccess, "CM");

        // Check if tournament completed and handle prize distribution/reset
        _handleTournamentCompletion(tierId, instanceId, enrolledPlayersCopy);
    }

    // Handle tournament completion: prizes, events, reset
    function _handleTournamentCompletion(
        uint8 tierId,
        uint8 instanceId,
        address[] memory enrolledPlayersCopy
    ) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Only proceed if tournament is actually completed
        if (tournament.status != TournamentStatus.Completed || enrolledPlayersCopy.length == 0) {
            return;
        }

        address tournamentWinner = tournament.winner;
        uint256 winnersPot = tournament.prizePool;

        // Distribute prizes based on completion type
        address[] memory winners;
        uint256[] memory prizes;

        if (tournament.allDrawResolution) {
            // All-draw: distribute equal prizes to all remaining players
            (bool distributeSuccess, bytes memory returnData) = MODULE_PRIZES.delegatecall(
                abi.encodeWithSignature("distributeEqualPrizes(uint8,uint8,address[],uint256,string)",
                    tierId, instanceId, enrolledPlayersCopy, winnersPot, "")
            );
            require(distributeSuccess, "DP");
            (winners, prizes) = abi.decode(returnData, (address[], uint256[]));
        } else if (tournament.finalsWasDraw) {
            // Finals draw: split prize equally between 2 finalists
            TierConfig storage config = _tierConfigs[tierId];
            bytes32 finalMatchId = _getMatchId(tierId, instanceId, config.totalRounds - 1, 0);
            Match storage finalMatch = matches[finalMatchId];
            address[] memory finalists = new address[](2);
            finalists[0] = finalMatch.player1;
            finalists[1] = finalMatch.player2;
            (bool distributeSuccess, bytes memory returnData) = MODULE_PRIZES.delegatecall(
                abi.encodeWithSignature("distributeEqualPrizes(uint8,uint8,address[],uint256,string)",
                    tierId, instanceId, finalists, winnersPot, "")
            );
            require(distributeSuccess, "DP");
            (winners, prizes) = abi.decode(returnData, (address[], uint256[]));
        } else {
            // Normal completion: winner-takes-all
            (bool distributeSuccess, bytes memory returnData) = MODULE_PRIZES.delegatecall(
                abi.encodeWithSignature("distributePrizes(uint8,uint8,uint256,string)",
                    tierId, instanceId, winnersPot, "")
            );
            require(distributeSuccess, "DP");
            (winners, prizes) = abi.decode(returnData, (address[], uint256[]));
        }

        // Emit Transfer events for each winner (only if prize was successfully sent)
        for (uint256 i = 0; i < winners.length; i++) {
            if (prizes[i] > 0) {
                emit Transfer(address(this), winners[i], prizes[i]);
            }
        }

        // Update earnings for all players (handles both single winner and all-draw scenarios)
        (bool earningsSuccess, ) = MODULE_PRIZES.delegatecall(
            abi.encodeWithSignature("updatePlayerEarnings(uint8,uint8,address)",
                tierId, instanceId, tournamentWinner)
        );
        require(earningsSuccess, "UE");

        // Call hook BEFORE reset (for ChessOnChain elite match archival)
        _onTournamentCompletedBeforeReset(tierId, instanceId);

        // Reset tournament state (MODULE_CORE records completion in recentInstances)
        (bool resetSuccess, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("resetTournamentAfterCompletion(uint8,uint8,address[])",
                tierId, instanceId, enrolledPlayersCopy)
        );
        require(resetSuccess, "RT");
    }

    // ============ Abstract Functions (Implemented by Game Contracts) ============

    /**
     * @dev Create a new match in game-specific storage
     * Called by Matches module when initializing matches
     * PUBLIC for module delegatecall access
     */
    function _createMatchGame(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address player1,
        address player2
    ) public virtual;

    /**
     * @dev Reset match game state
     * Called when match needs to be reset
     * PUBLIC for module delegatecall access
     */
    function _resetMatchGame(bytes32 matchId) public virtual;

    /**
     * @dev Get match result from game-specific storage
     * Called by Matches module to check if match is complete
     * PUBLIC for delegatecall access (view functions don't need onlyInternal)
     */
    function _getMatchResult(bytes32 matchId) public view virtual returns (address winner, bool isDraw, MatchStatus status);

    /**
     * @dev Get match players from game-specific storage
     * Called by modules to retrieve player addresses
     * PUBLIC for delegatecall access (view functions don't need onlyInternal)
     * Default implementation uses shared Match struct - override only if needed
     */
    function _getMatchPlayers(bytes32 matchId) public view virtual returns (address player1, address player2) {
        Match storage matchData = matches[matchId];
        return (matchData.player1, matchData.player2);
    }

    /**
     * @dev Set player in match slot
     * Called by Escalation module when replacing players
     * PUBLIC for module delegatecall access
     * Shared implementation for all games
     */
    function _setMatchPlayer(bytes32 matchId, uint8 slot, address player) public virtual {
        Match storage matchData = matches[matchId];

        if (slot == 0) {
            matchData.player1 = player;
        } else {
            matchData.player2 = player;
        }
    }

    /**
     * @dev Initialize match for play
     * Called by Matches module after players are assigned
     * PUBLIC for module delegatecall access
     */
    function _initializeMatchForPlay(bytes32 matchId, uint8 tierId) public virtual;

    /**
     * @dev Complete match with result
     * Called by Matches module to mark match as complete
     * PUBLIC for module delegatecall access
     */
    function _completeMatchWithResult(bytes32 matchId, address winner, bool isDraw) public virtual;

    /**
     * @dev Get time increment per move
     * Called by Escalation module for timeout calculations
     * PUBLIC for delegatecall access (view functions don't need onlyInternal)
     */
    function _getTimeIncrement() public view virtual returns (uint256);

    /**
     * @dev Check if current player has timed out
     * Called by Escalation module to detect stalled matches
     * PUBLIC for delegatecall access (view functions don't need onlyInternal)
     */
    function _hasCurrentPlayerTimedOut(bytes32 matchId) public view virtual returns (bool);

    /**
     * @dev Check if match is active
     * Default implementation uses _getMatchPlayers and _getMatchResult
     * Override only if game needs custom logic
     */
    function _isMatchActive(bytes32 matchId) public view virtual returns (bool) {
        (address player1, ) = _getMatchPlayers(matchId);
        (, , MatchStatus status) = _getMatchResult(matchId);
        return player1 != address(0) && status != MatchStatus.Completed;
    }

    /**
     * @dev Get active match data
     * Called by modules to retrieve match information
     * PUBLIC for delegatecall access (view functions don't need onlyInternal)
     * Default implementation uses shared Match struct - override only if needed
     */
    function _getActiveMatchData(
        bytes32 matchId,
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) public view virtual returns (CommonMatchData memory) {
        Match storage matchData = matches[matchId];

        address loser = address(0);
        if (!matchData.isDraw && matchData.winner != address(0)) {
            loser = (matchData.winner == matchData.player1)
                ? matchData.player2
                : matchData.player1;
        }

        return CommonMatchData({
            player1: matchData.player1,
            player2: matchData.player2,
            winner: matchData.winner,
            loser: loser,
            status: matchData.status,
            isDraw: matchData.isDraw,
            startTime: matchData.startTime,
            lastMoveTime: matchData.lastMoveTime,
            tierId: tierId,
            instanceId: instanceId,
            roundNumber: roundNumber,
            matchNumber: matchNumber,
            isCached: false
        });
    }

    // ============ Hooks (Optional overrides by Game Contracts) ============

    /**
     * @dev Hook to mark match as complete in game-specific Match storage
     * MUST be overridden in each game contract to update game-specific Match struct
     * Default implementation reverts (modules don't use this)
     */
    function _completeMatchGameSpecific(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address winner,
        bool isDraw
    ) internal virtual {
        revert("ETour_Base: _completeMatchGameSpecific must be implemented by game contract");
    }

    /**
     * @dev Hook called BEFORE tournament reset (for ChessOnChain elite match archival)
     * Override in ChessOnChain to archive finals matches
     */
    function _onTournamentCompletedBeforeReset(
        uint8 tierId,
        uint8 instanceId
    ) internal virtual {}

    // Note: Helper functions removed to minimize stack depth

    // ============ Public Tournament Functions (Shared Across All Games) ============

    /**
     * @dev Enroll in tournament - delegates to Core module and handles hooks
     * Shared implementation for all games - override only if custom logic needed
     * IMPORTANT: Game contracts must mark this as payable and nonReentrant
     */
    function enrollInTournament(uint8 tierId, uint8 instanceId) external payable virtual {
        TournamentStatus oldStatus = tournaments[tierId][instanceId].status;

        (bool success, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("enrollInTournament(uint8,uint8)", tierId, instanceId)
        );
        require(success, "Enrollment failed");

        if (oldStatus == TournamentStatus.Enrolling && tournaments[tierId][instanceId].status == TournamentStatus.InProgress) {
            initializeRound(tierId, instanceId, 0);
        }
    }

    /**
     * @dev Force start tournament - delegates to Core module and handles hooks
     * Shared implementation for all games - override only if custom logic needed
     * IMPORTANT: Game contracts must mark this as nonReentrant
     */
    function forceStartTournament(uint8 tierId, uint8 instanceId) external virtual {
        TournamentStatus oldStatus = tournaments[tierId][instanceId].status;

        (bool success, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("forceStartTournament(uint8,uint8)", tierId, instanceId)
        );
        require(success, "Force start failed");

        TournamentStatus newStatus = tournaments[tierId][instanceId].status;

        if (oldStatus != TournamentStatus.Enrolling) return;

        if (newStatus == TournamentStatus.InProgress) {
            initializeRound(tierId, instanceId, 0);
            return;
        }

        if (newStatus == TournamentStatus.Completed) {
            _handleSinglePlayerCompletion(tierId, instanceId);
        }
    }

    /**
     * @dev Handle single-player tournament completion
     * Separate function to reduce stack depth
     */
    function _handleSinglePlayerCompletion(uint8 tierId, uint8 instanceId) private {
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        (bool success, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("resetTournamentAfterCompletion(uint8,uint8,address[])", tierId, instanceId, enrolledPlayersCopy)
        );
        require(success, "Reset failed");
    }

    /**
     * @dev Initialize round - must be implemented by game contract
     * Called after tournament starts or when round completes
     * PUBLIC for delegatecall access and for hooks
     */
    function initializeRound(uint8 tierId, uint8 instanceId, uint8 roundNumber) public virtual;

    // ============ Public View Functions (Shared Across All Games) ============

    /**
     * @dev Get tournament information
     * Shared implementation for all games
     */
    function getTournamentInfo(uint8 tierId, uint8 instanceId) external view returns (
        TournamentStatus status,
        uint8 currentRound,
        uint8 enrolledCount,
        uint256 prizePool,
        address winner
    ) {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        return (
            tournament.status,
            tournament.currentRound,
            tournament.enrolledCount,
            tournament.prizePool,
            tournament.winner
        );
    }

    /**
     * @dev Get round information
     * Shared implementation for all games
     */
    function getRoundInfo(uint8 tierId, uint8 instanceId, uint8 roundNumber) external view returns (
        uint8 totalMatches,
        uint8 completedMatches,
        bool initialized
    ) {
        Round storage round = rounds[tierId][instanceId][roundNumber];
        return (
            round.totalMatches,
            round.completedMatches,
            round.initialized
        );
    }

    /**
     * @dev Get leaderboard entries
     * Shared implementation for all games
     */
    function getLeaderboard() external view returns (LeaderboardEntry[] memory) {
        LeaderboardEntry[] memory entries = new LeaderboardEntry[](_leaderboardPlayers.length);
        for (uint256 i = 0; i < _leaderboardPlayers.length; i++) {
            entries[i] = LeaderboardEntry({
                player: _leaderboardPlayers[i],
                earnings: playerEarnings[_leaderboardPlayers[i]]
            });
        }
        return entries;
    }

    /**
     * @dev Get raffle information
     * Shared implementation for all games
     * Client can derive: reserve=5% of threshold, owner=5% of 95%, winner=90% of 95%
     */
    function getRaffleInfo() external view returns (
        uint64 raffleIndex,
        uint256 currentAccumulated,
        uint256 threshold,
        uint16 eligiblePlayerCount
    ) {
        raffleIndex = uint64(raffleResults.length);
        currentAccumulated = accumulatedProtocolShare;

        // Get threshold for next raffle
        uint256 nextIndex = raffleResults.length;
        threshold = (nextIndex < raffleThresholds.length)
            ? raffleThresholds[nextIndex]
            : raffleThresholds[raffleThresholds.length - 1];

        // Get eligible player count by counting unique enrolled players
        eligiblePlayerCount = uint16(_getEligiblePlayerCount());
    }

    // Note: raffleResults is public, so Solidity auto-generates raffleResults(uint256) getter
    // Clients can fetch individual raffles or use raffleResults.length for iteration
    // Removed getAllRaffleResults() to avoid expensive gas costs with many raffles

    /**
     * @dev Internal helper to count unique eligible players for raffle
     * Shared implementation for all games
     */
    function _getEligiblePlayerCount() internal view returns (uint256) {
        // Use temporary array to track unique players (max 1000)
        address[] memory tempPlayers = new address[](1000);
        uint256 uniqueCount = 0;

        // Iterate through all active tournaments
        for (uint8 tierId = 0; tierId < tierCount; tierId++) {
            TierConfig storage config = _tierConfigs[tierId];

            for (uint8 instanceId = 0; instanceId < config.instanceCount; instanceId++) {
                TournamentInstance storage tournament = tournaments[tierId][instanceId];

                // Only count Enrolling and InProgress tournaments
                if (tournament.status == TournamentStatus.Enrolling ||
                    tournament.status == TournamentStatus.InProgress) {

                    address[] storage enrolled = enrolledPlayers[tierId][instanceId];

                    for (uint256 i = 0; i < enrolled.length; i++) {
                        address player = enrolled[i];
                        bool found = false;

                        // Check if player already counted
                        for (uint256 j = 0; j < uniqueCount; j++) {
                            if (tempPlayers[j] == player) {
                                found = true;
                                break;
                            }
                        }

                        if (!found) {
                            tempPlayers[uniqueCount] = player;
                            uniqueCount++;
                        }
                    }
                }
            }
        }

        return uniqueCount;
    }

    /**
     * @dev Get player earnings (stats)
     * Shared implementation for all games
     */
    function getPlayerStats() external view returns (int256 totalEarnings) {
        return playerEarnings[msg.sender];
    }

    /**
     * @dev Get player's match history
     * Returns all completed matches for the calling player
     * Shared implementation for all games
     */
    function getPlayerMatches() external view returns (MatchRecord[] memory) {
        return playerMatches[msg.sender];
    }

    /**
     * @dev Get most recent completed tournament record with full player list
     * Required because auto-generated getter omits dynamic arrays
     * Shared implementation for all games
     */
    function getTournamentRecord(uint8 tierId, uint8 instanceId) external view returns (TournamentRecord memory) {
        return recentInstances[tierId][instanceId];
    }

    /**
     * @dev Check if Level 2 escalation is available for a stalled match
     * Level 2 allows advanced players (those in later rounds) to claim the match
     * Kept in ETour_Base to avoid stack depth issues with delegatecall
     */
    function isMatchEscL2Available(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external view virtual returns (bool) {
        // SECURITY: Tournament must be in progress for escalation
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        if (tournament.status != TournamentStatus.InProgress) {
            return false;
        }

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        // Check if match is active and in progress
        if (matchData.player1 == address(0) || matchData.status != MatchStatus.InProgress) {
            return false;
        }

        // Check if current player has timed out
        uint256 elapsed = block.timestamp - matchData.lastMoveTime;
        uint256 currentPlayerTime = (matchData.currentTurn == matchData.player1)
            ? matchData.player1TimeRemaining
            : matchData.player2TimeRemaining;

        if (elapsed < currentPlayerTime) {
            return false;
        }

        // Check timeout state
        MatchTimeoutState storage timeout = matchTimeouts[matchId];

        // If not marked as stalled yet, calculate when L2 would start
        if (!timeout.isStalled) {
            TierConfig storage config = _tierConfigs[tierId];
            uint256 timeoutOccurredAt = matchData.lastMoveTime + config.timeouts.matchTimePerPlayer;
            uint256 l2Start = timeoutOccurredAt + config.timeouts.matchLevel2Delay;
            return block.timestamp >= l2Start;
        }

        // If already marked as stalled, check if L2 window is active
        return block.timestamp >= timeout.escalation1Start;
    }

    /**
     * @dev Check if Level 3 escalation is available for a stalled match
     * Level 3 allows any external player to claim the match
     * Kept in ETour_Base to avoid stack depth issues with delegatecall
     */
    function isMatchEscL3Available(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external view virtual returns (bool) {
        // SECURITY: Tournament must be in progress for escalation
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        if (tournament.status != TournamentStatus.InProgress) {
            return false;
        }

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        // Check if match is active and in progress
        if (matchData.player1 == address(0) || matchData.status != MatchStatus.InProgress) {
            return false;
        }

        // Check if current player has timed out
        uint256 elapsed = block.timestamp - matchData.lastMoveTime;
        uint256 currentPlayerTime = (matchData.currentTurn == matchData.player1)
            ? matchData.player1TimeRemaining
            : matchData.player2TimeRemaining;

        if (elapsed < currentPlayerTime) {
            return false;
        }

        // Check timeout state
        MatchTimeoutState storage timeout = matchTimeouts[matchId];

        // If not marked as stalled yet, calculate when L3 would start
        if (!timeout.isStalled) {
            TierConfig storage config = _tierConfigs[tierId];
            uint256 timeoutOccurredAt = matchData.lastMoveTime + config.timeouts.matchTimePerPlayer;
            uint256 l3Start = timeoutOccurredAt + config.timeouts.matchLevel3Delay;
            return block.timestamp >= l3Start;
        }

        // If already marked as stalled, check if L3 window is active
        return block.timestamp >= timeout.escalation2Start;
    }

    /**
     * @dev Claim timeout win against stalled opponent
     * Non-active player can claim win if opponent's time has expired
     * Kept inline to preserve error messages and avoid stack depth issues
     */
    function claimTimeoutWin(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external nonReentrant {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        require(matchData.status == MatchStatus.InProgress, "MA");
        require(msg.sender == matchData.player1 || msg.sender == matchData.player2, "NP");
        require(msg.sender != matchData.currentTurn, "OT");

        // Check if current player has timed out
        uint256 elapsed = block.timestamp - matchData.lastMoveTime;
        uint256 opponentTimeRemaining = (matchData.currentTurn == matchData.player1)
            ? matchData.player1TimeRemaining
            : matchData.player2TimeRemaining;

        require(elapsed >= opponentTimeRemaining, "TO");

        // Mark match as stalled (enables L2/L3 escalation later if needed)
        (bool markSuccess, ) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature(
                "markMatchStalled(bytes32,uint8,uint256)",
                matchId, tierId, block.timestamp
            )
        );
        require(markSuccess, "MS");

        // Complete match with timeout winner
        _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, msg.sender, false, CompletionReason.Timeout);
    }

    /**
     * @dev Check if player has advanced past a given round
     * Used for ML2 escalation eligibility
     * Same implementation as _isPlayerInAdvancedRound in Escalation module
     */
    function isPlayerInAdvancedRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 stalledRoundNumber,
        address player
    ) external view virtual returns (bool hasAdvanced) {
        // Must be enrolled to be advanced
        if (!isEnrolled[tierId][instanceId][player]) {
            return false;
        }

        // Check 1: Has player won a match in any round up to and including the stalled round?
        for (uint8 r = 0; r <= stalledRoundNumber; r++) {
            Round storage round = rounds[tierId][instanceId][r];

            for (uint8 m = 0; m < round.totalMatches; m++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, r, m);
                (address winner, bool isDraw, MatchStatus status) = _getMatchResult(matchId);

                // Check if player won this match
                if (status == MatchStatus.Completed &&
                    winner == player &&
                    !isDraw) {
                    return true;
                }
            }
        }

        // Check 2: Is player assigned to a match in a round AFTER the stalled round?
        // This catches walkover/auto-advanced players
        TierConfig storage config = _tierConfigs[tierId];
        for (uint8 r = stalledRoundNumber + 1; r < config.totalRounds; r++) {
            Round storage round = rounds[tierId][instanceId][r];
            if (!round.initialized) continue;

            for (uint8 m = 0; m < round.totalMatches; m++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, r, m);
                (address player1, address player2) = _getMatchPlayers(matchId);

                if (player1 == player || player2 == player) {
                    return true;
                }
            }
        }

        return false;
    }

}
