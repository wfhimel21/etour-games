// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ETour_Base.sol";

/**
 * @title ETour_Core
 * @dev Stateless module for tier management, enrollment, and tournament initialization
 *
 * This module handles:
 * - Tier registration and configuration
 * - Player enrollment with fee distribution
 * - Tournament force start and abandonment logic
 * - Tournament initialization and solo winner handling
 *
 * CRITICAL - DELEGATECALL SEMANTICS:
 * When game contract calls this module via delegatecall:
 * - This code executes AS IF it's part of the game contract
 * - Can directly access storage variables (tournaments, enrolledPlayers, etc.)
 * - address(this) = game contract address
 * - msg.sender = original caller
 * - msg.value = value sent
 *
 * STATELESS: This contract declares NO storage variables of its own.
 * All storage access is to the game contract's storage via delegatecall context.
 */
contract ETour_Core is ETour_Base {

    // Constructor - modules need to set module addresses even though they're stateless
    // This is a bit of a hack - modules inherit ETour_Base for type definitions
    // but their storage is never used (delegatecall uses game contract's storage)
    constructor() ETour_Base(address(0), address(0), address(0), address(0), address(0)) {}

    // ============ Abstract Function Stubs (Never Called - Modules call directly via inheritance) ============
    function _createMatchGame(uint8, uint8, uint8, uint8, address, address) public override { revert("Module: Call directly"); }
    function _resetMatchGame(bytes32) public override { revert("Module: Call directly"); }
    function _getMatchResult(bytes32) public view override returns (address, bool, MatchStatus) { revert("Module: Call directly"); }
    function _initializeMatchForPlay(bytes32, uint8) public override { revert("Module: Call directly"); }
    function _completeMatchWithResult(bytes32, address, bool) public override { revert("Module: Call directly"); }
    function _getTimeIncrement() public view override returns (uint256) { revert("Module: Call directly"); }
    function _hasCurrentPlayerTimedOut(bytes32) public view override returns (bool) { revert("Module: Call directly"); }
    function initializeRound(uint8, uint8, uint8) public override { revert("Module: Call directly"); }

    // ============ Tier Configuration ============

    /**
     * @dev Register a tournament tier - called by implementing contract during construction
     * Simplified: No prize distribution needed - first place always gets 100%
     */
    function registerTier(
        uint8 tierId,
        uint8 playerCount,
        uint8 instanceCount,
        uint256 entryFee,
        TimeoutConfig memory timeouts
    ) external onlyDelegateCall {
        require(!_tierConfigs[tierId].initialized, "Tier already registered");
        require(playerCount >= 2, "Need at least 2 players");
        require(instanceCount >= 1, "Need at least 1 instance");

        _tierConfigs[tierId] = TierConfig({
            playerCount: playerCount,
            instanceCount: instanceCount,
            entryFee: entryFee,
            timeouts: timeouts,
            totalRounds: _log2(playerCount),
            initialized: true
        });

        // Update tier count if this is a new highest tier
        if (tierId >= tierCount) {
            tierCount = tierId + 1;
        }
    }

    // REMOVED: registerRaffleThresholds() - Never called anywhere in codebase
    // Raffle thresholds would need to be configured differently if needed

    // ============ Enrollment Functions ============

    /**
     * @dev Enroll in tournament with entry fee
     * EXACT COPY from ETour.sol lines 562-611
     * Module implementation - called via delegatecall from game contracts
     */
    function enrollInTournament(uint8 tierId, uint8 instanceId) external payable override {
        TierConfig storage config = _tierConfigs[tierId];
        require(config.initialized, "Invalid tier");
        require(instanceId < config.instanceCount, "Invalid instance");
        require(msg.value == config.entryFee, "Incorrect entry fee");

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Lazy initialization on first enrollment
        if (tournament.enrolledCount == 0 && tournament.status == TournamentStatus.Enrolling) {
            tournament.tierId = tierId;
            tournament.instanceId = instanceId;

            tournament.enrollmentTimeout.escalation1Start = block.timestamp + config.timeouts.enrollmentWindow;
            tournament.enrollmentTimeout.escalation2Start = tournament.enrollmentTimeout.escalation1Start + config.timeouts.enrollmentLevel2Delay;
            tournament.enrollmentTimeout.activeEscalation = EscalationLevel.None;
            tournament.enrollmentTimeout.forfeitPool = 0;

            // NOTE: Match data is cleared in resetTournamentAfterCompletion (below in this module)
            // This prevents security vulnerabilities from stale match actions between tournaments
        }

        require(tournament.status == TournamentStatus.Enrolling, "Tournament not accepting enrollments");
        require(!isEnrolled[tierId][instanceId][msg.sender], "Already enrolled");
        require(tournament.enrolledCount < config.playerCount, "Tournament full");

        uint256 participantsShare = (msg.value * PARTICIPANTS_SHARE_BPS) / BASIS_POINTS;
        uint256 ownerShare = (msg.value * OWNER_SHARE_BPS) / BASIS_POINTS;
        uint256 protocolShare = (msg.value * PROTOCOL_SHARE_BPS) / BASIS_POINTS;

        tournament.enrollmentTimeout.forfeitPool += participantsShare;

        (bool ownerSuccess, ) = payable(owner).call{value: ownerShare}("");
        require(ownerSuccess, "Owner fee transfer failed");

        // Add protocol share to accumulated pool for raffle system
        accumulatedProtocolShare += protocolShare;

        enrolledPlayers[tierId][instanceId].push(msg.sender);
        isEnrolled[tierId][instanceId][msg.sender] = true;
        tournament.enrolledCount++;
        tournament.prizePool += participantsShare;

        emit TournamentEnrolled(msg.sender, tierId, instanceId);

        if (tournament.enrolledCount == config.playerCount) {
            startTournament(tierId, instanceId);
        }
    }

    /**
     * @dev Force start tournament if enrollment window expired
     * EXACT COPY from ETour.sol lines 613-631
     * Module implementation - called via delegatecall from game contracts
     */
    function forceStartTournament(uint8 tierId, uint8 instanceId) external override {
        TierConfig storage config = _tierConfigs[tierId];
        require(config.initialized, "Invalid tier");
        require(instanceId < config.instanceCount, "Invalid instance");

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        require(tournament.status == TournamentStatus.Enrolling, "Not enrolling");
        require(isEnrolled[tierId][instanceId][msg.sender], "Not enrolled");
        require(block.timestamp >= tournament.enrollmentTimeout.escalation1Start, "Enrollment window not expired");
        require(tournament.enrollmentTimeout.activeEscalation != EscalationLevel.Escalation3_ExternalPlayers, "Public tier already active");
        require(tournament.enrolledCount >= 1, "Need at least 1 player");

        tournament.enrollmentTimeout.activeEscalation = EscalationLevel.Escalation1_OpponentClaim;

        startTournament(tierId, instanceId);
    }

    /**
     * @dev Claim abandoned enrollment pool
     * EXACT COPY from ETour.sol lines 633-661
     */
    function claimAbandonedEnrollmentPool(uint8 tierId, uint8 instanceId) external onlyDelegateCall {
        TierConfig storage config = _tierConfigs[tierId];
        require(config.initialized, "Invalid tier");
        require(instanceId < config.instanceCount, "Invalid instance");

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        require(tournament.status == TournamentStatus.Enrolling, "Not enrolling");
        require(block.timestamp >= tournament.enrollmentTimeout.escalation2Start, "Public claim window not reached");
        require(tournament.enrolledCount > 0, "No enrollment pool to claim");

        tournament.enrollmentTimeout.activeEscalation = EscalationLevel.Escalation3_ExternalPlayers;

        uint256 claimAmount = tournament.enrollmentTimeout.forfeitPool;
        tournament.enrollmentTimeout.forfeitPool = 0;

        for (uint256 i = 0; i < tournament.enrolledCount; i++) {
            address player = enrolledPlayers[tierId][instanceId][i];
        }

        (bool success, ) = payable(msg.sender).call{value: claimAmount}("");
        require(success, "Transfer failed");

        updateAbandonedEarnings(tierId, instanceId, msg.sender, claimAmount);

        // Mark tournament as completed with abandoned claim reason
        tournament.status = TournamentStatus.Completed;
        tournament.completionReason = CompletionReason.AbandonedTournamentClaimed;
        tournament.winner = msg.sender;  // EL2 claimant is the winner

        // NOTE: Tournament reset with recording is handled by game contract after this function returns
        // (nested delegatecall to MODULE_PRIZES doesn't work)
    }

    /**
     * @dev Reset enrollment window for solo enrolled player
     * EXACT COPY from ETour.sol lines 670-706
     */
    function resetEnrollmentWindow(uint8 tierId, uint8 instanceId) external onlyDelegateCall {
        TierConfig storage config = _tierConfigs[tierId];
        require(config.initialized, "Invalid tier");
        require(instanceId < config.instanceCount, "Invalid instance");

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Must be enrolling status
        require(tournament.status == TournamentStatus.Enrolling, "Not enrolling");

        // Exactly 1 player enrolled
        require(tournament.enrolledCount == 1, "Must have exactly 1 player enrolled");

        // Caller must be that enrolled player
        require(isEnrolled[tierId][instanceId][msg.sender], "Not enrolled");

        // Enrollment window must have expired (past escalation1Start)
        require(
            block.timestamp >= tournament.enrollmentTimeout.escalation1Start,
            "Enrollment window not expired"
        );

        // Recalculate escalation windows from current timestamp
        tournament.enrollmentTimeout.escalation1Start =
            block.timestamp + config.timeouts.enrollmentWindow;
        tournament.enrollmentTimeout.escalation2Start =
            tournament.enrollmentTimeout.escalation1Start + config.timeouts.enrollmentLevel2Delay;
        tournament.enrollmentTimeout.activeEscalation = EscalationLevel.None;
    }

    /**
     * @dev Check if the connected wallet can reset the enrollment window
     * EXACT COPY from ETour.sol lines 714-734
     */
    function canResetEnrollmentWindow(
        uint8 tierId,
        uint8 instanceId
    ) external view returns (bool canReset) {
        TierConfig storage config = _tierConfigs[tierId];

        if (!config.initialized) return false;
        if (instanceId >= config.instanceCount) return false;

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        bool isEnrollingStatus = tournament.status == TournamentStatus.Enrolling;
        bool isExactlyOnePlayer = tournament.enrolledCount == 1;
        bool isPlayerEnrolled = isEnrolled[tierId][instanceId][msg.sender];
        bool hasWindowExpired = block.timestamp >= tournament.enrollmentTimeout.escalation1Start;

        return isEnrollingStatus &&
               isExactlyOnePlayer &&
               isPlayerEnrolled &&
               hasWindowExpired;
    }

    // ============ Tournament Start Logic ============

    /**
     * @dev Start tournament (handles solo winner case, delegates to Matches module for multi-player)
     * EXACT COPY from ETour.sol lines 831-867 with delegatecall to MODULE_MATCHES
     * INTERNAL: Only called from enrollInTournament and forceStartTournament
     */
    function startTournament(uint8 tierId, uint8 instanceId) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        tournament.status = TournamentStatus.InProgress;
        tournament.startTime = block.timestamp;
        tournament.currentRound = 0;

        // Calculate actual rounds needed based on enrolled players, not tier max
        // Use ceiling of log2 to handle odd numbers (e.g., 3 players needs 2 rounds, not 1)
        uint8 playerCount = tournament.enrolledCount;
        if (playerCount == 0) {
            tournament.actualTotalRounds = 0;
        } else if (playerCount == 1) {
            tournament.actualTotalRounds = 0; // Solo player, no rounds needed
        } else {
            // Calculate ceil(log2(playerCount))
            uint8 log2Floor = _log2(playerCount);
            // Check if playerCount is a perfect power of 2
            bool isPowerOf2 = (playerCount & (playerCount - 1)) == 0;
            tournament.actualTotalRounds = isPowerOf2 ? log2Floor : log2Floor + 1;
        }

        if (tournament.enrolledCount == 1) {
            address soloWinner = enrolledPlayers[tierId][instanceId][0];
            tournament.winner = soloWinner;
            tournament.status = TournamentStatus.Completed;
            tournament.completionReason = CompletionReason.SoloEnrollForceStart;
            // Removed: Ranking assignment (no longer needed with winner-takes-all)

            uint256 winnersPot = tournament.prizePool;
            playerPrizes[tierId][instanceId][soloWinner] = winnersPot;

            // Send prize with fallback (inlined to avoid nested delegatecall)
            bool sent = false;
            if (winnersPot > 0) {
                (bool transferSuccess, ) = payable(soloWinner).call{value: winnersPot}("");
                if (transferSuccess) {
                    sent = true;
                } else {
                    // If send failed, add amount to accumulated protocol share
                    accumulatedProtocolShare += winnersPot;
                }
            }

            // Update player earnings inline (avoid nested delegatecall)
            if (winnersPot > 0) {
                if (!_isOnLeaderboard[soloWinner]) {
                    _isOnLeaderboard[soloWinner] = true;
                    _leaderboardPlayers.push(soloWinner);
                }
                playerEarnings[soloWinner] += int256(winnersPot);
            }

            // NOTE: Tournament reset is handled by game contract after this function returns
            // (nested delegatecall to MODULE_PRIZES doesn't work)
            return;
        }

        // Note: initializeRound is called by the game contract directly after this returns
        // This allows the game contract to handle match creation with its own _createMatchGame
    }

    // ============ Helper Functions ============

    /**
     * @dev Update earnings for abandoned enrollment claim
     * EXACT COPY from ETour.sol lines 2128-2142
     * INTERNAL: Only called from claimAbandonedEnrollmentPool
     */
    function updateAbandonedEarnings(
        uint8 tierId,
        uint8 instanceId,
        address claimer,
        uint256 claimAmount
    ) internal {
        // Only track the claimer if they receive a claim amount
        // Enrolled players who abandoned don't receive anything, so don't track them
        if (claimAmount > 0) {
            // Track on leaderboard directly
            if (!_isOnLeaderboard[claimer]) {
                _isOnLeaderboard[claimer] = true;
                _leaderboardPlayers.push(claimer);
            }

            playerEarnings[claimer] += int256(claimAmount);
        }
    }

    // ============ Configuration Getters ============

    /**
     * @dev Get all tier IDs that have been registered
     * EXACT COPY from ETour.sol lines 2519-2525
     */
    function getAllTierIds() external view returns (uint8[] memory) {
        uint8[] memory tierIds = new uint8[](tierCount);
        for (uint8 i = 0; i < tierCount; i++) {
            tierIds[i] = i;
        }
        return tierIds;
    }

    /**
     * @dev Get basic tier information
     * EXACT COPY from ETour.sol lines 2534-2546
     */
    function getTierInfo(uint8 tierId) external view returns (
        uint8 playerCount,
        uint8 instanceCount,
        uint256 entryFee
    ) {
        require(_tierConfigs[tierId].initialized, "Invalid tier");
        TierConfig storage config = _tierConfigs[tierId];
        return (
            config.playerCount,
            config.instanceCount,
            config.entryFee
        );
    }

    /**
     * @dev Get timeout configuration for a tier
     * EXACT COPY from ETour.sol lines 2558-2576
     */
    function getTierTimeouts(uint8 tierId) external view returns (
        uint256 matchTimePerPlayer,
        uint256 timeIncrementPerMove,
        uint256 matchLevel2Delay,
        uint256 matchLevel3Delay,
        uint256 enrollmentWindow,
        uint256 enrollmentLevel2Delay
    ) {
        require(_tierConfigs[tierId].initialized, "Invalid tier");
        TimeoutConfig storage timeouts = _tierConfigs[tierId].timeouts;
        return (
            timeouts.matchTimePerPlayer,
            timeouts.timeIncrementPerMove,
            timeouts.matchLevel2Delay,
            timeouts.matchLevel3Delay,
            timeouts.enrollmentWindow,
            timeouts.enrollmentLevel2Delay
        );
    }

    // ============ Additional Getters (Extracted from Game Contracts) ============

    // REMOVED: getMatchId() - Redundant wrapper around _getMatchId() from ETour_Base, never called

    /**
     * @dev Get full tier configuration struct
     */
    function tierConfigs(uint8 tierId) external view returns (TierConfig memory) {
        require(tierId < tierCount, "Invalid tier ID");
        return _tierConfigs[tierId];
    }

    /**
     * @dev Get tier entry fee
     */
    function ENTRY_FEES(uint8 tierId) external view returns (uint256) {
        return _tierConfigs[tierId].entryFee;
    }

    /**
     * @dev Get tier instance count
     */
    function INSTANCE_COUNTS(uint8 tierId) external view returns (uint8) {
        return _tierConfigs[tierId].instanceCount;
    }

    /**
     * @dev Get tier player count
     */
    function TIER_SIZES(uint8 tierId) external view returns (uint8) {
        return _tierConfigs[tierId].playerCount;
    }

    // Note: getTournamentInfo() function is now inherited from ETour_Base

    /**
     * @dev Get total player capacity across all tiers
     */
    function getTotalCapacity() external view returns (uint256 totalPlayers) {
        for (uint8 i = 0; i < tierCount; i++) {
            if (_tierConfigs[i].initialized) {
                TierConfig storage config = _tierConfigs[i];
                totalPlayers += uint256(config.playerCount) * uint256(config.instanceCount);
            }
        }
        return totalPlayers;
    }

    // ============ Tournament Reset ============

    /**
     * @dev Reset tournament state after completion (with recording)
     * MOVED from ETour_Prizes.sol - Tournament lifecycle belongs in Core module
     * Records tournament completion in recentInstances before resetting
     */
    function resetTournamentAfterCompletion(
        uint8 tierId,
        uint8 instanceId,
        address[] memory enrolledPlayersCopy
    ) external onlyDelegateCall {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Record tournament completion in permanent storage BEFORE reset
        TournamentRecord storage record = recentInstances[tierId][instanceId];
        record.players = enrolledPlayersCopy;
        record.endTime = block.timestamp;
        record.prizePool = tournament.prizePool;
        record.winner = tournament.winner;
        record.completionReason = tournament.completionReason;

        // Call internal reset logic
        _resetTournamentInternal(tierId, instanceId);
    }

    /**
     * @dev Reset tournament state without recording (for abandonment/single player)
     * Used when tournament is abandoned or single player force start
     */
    function resetTournamentAfterCompletion(uint8 tierId, uint8 instanceId) external onlyDelegateCall {
        _resetTournamentInternal(tierId, instanceId);
    }

    /**
     * @dev Internal reset logic shared by both overloads
     */
    function _resetTournamentInternal(uint8 tierId, uint8 instanceId) private {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        TierConfig storage config = _tierConfigs[tierId];

        // CRITICAL: Reset status FIRST before any other operations
        tournament.status = TournamentStatus.Enrolling;

        // Continue with other resets
        tournament.currentRound = 0;
        tournament.enrolledCount = 0;
        tournament.prizePool = 0;
        tournament.startTime = 0;
        tournament.winner = address(0);
        tournament.finalsWasDraw = false;
        tournament.allDrawResolution = false;
        tournament.allDrawRound = NO_ROUND;
        tournament.completionReason = CompletionReason.NormalWin;

        tournament.enrollmentTimeout.escalation1Start = 0;
        tournament.enrollmentTimeout.escalation2Start = 0;
        tournament.enrollmentTimeout.activeEscalation = EscalationLevel.None;
        tournament.enrollmentTimeout.forfeitPool = 0;

        address[] storage players = enrolledPlayers[tierId][instanceId];

        // Copy players array before deletion for tracking cleanup
        address[] memory playersCopy = new address[](players.length);
        for (uint256 i = 0; i < players.length; i++) {
            playersCopy[i] = players[i];
        }

        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            isEnrolled[tierId][instanceId][player] = false;
            // Note: playerPrizes is intentionally NOT deleted - it's permanent historical record
        }
        delete enrolledPlayers[tierId][instanceId];

        // ARCHITECTURE: Finals are treated like any other match - no special preservation
        // Historical data is available via events (MatchCreated, MatchCompleted)
        // This prevents stale data persistence issues and simplifies the codebase

        // CRITICAL SECURITY FIX: Clear ALL possible matches immediately on reset
        // This prevents any stale match actions (moves, timeouts, ML2/ML3 claims)
        // between tournament completion and next enrollment
        //
        // We must clear based on tier's max player count, not actual enrolled count,
        // because force-started tournaments may have fewer players but still create
        // matches in higher rounds (e.g., 2 players in 4-player tier advancing to finals)
        for (uint8 roundNum = 0; roundNum < config.totalRounds; roundNum++) {
            Round storage round = rounds[tierId][instanceId][roundNum];

            // Calculate max possible matches for this round based on tier config
            // Round 0: playerCount / 2, Round 1: playerCount / 4, etc.
            uint8 maxMatchesForRound = config.playerCount / uint8(2 << roundNum);

            // Clear ALL possible matches for this round
            for (uint8 matchNum = 0; matchNum < maxMatchesForRound; matchNum++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, roundNum, matchNum);

                // Clear drawParticipants for any players in this match
                (address p1, address p2) = this._getMatchPlayers(matchId);
                if (p1 != address(0)) {
                    delete drawParticipants[tierId][instanceId][roundNum][matchNum][p1];
                }
                if (p2 != address(0)) {
                    delete drawParticipants[tierId][instanceId][roundNum][matchNum][p2];
                }

                // Clear the match data itself
                this._resetMatchGame(matchId);
            }

            // Reset round metadata
            round.totalMatches = 0;
            round.completedMatches = 0;
            round.initialized = false;
            round.drawCount = 0;
        }
    }
}
