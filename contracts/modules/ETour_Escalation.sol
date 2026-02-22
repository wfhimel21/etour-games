// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ETour_Base.sol";

/**
 * @title ETour_Escalation
 * @dev Stateless module for timeout tracking and escalation logic
 *
 * This module handles:
 * - Match stalling detection when players run out of time
 * - 3-level escalation system for handling stalled matches
 * - Level 1: Opponent claims timeout victory (via game contract)
 * - Level 2: Advanced players force eliminate both stalled players
 * - Level 3: External players replace stalled players and win match
 * - Escalation state management and availability checks
 *
 * CRITICAL - DELEGATECALL SEMANTICS:
 * When game contract calls this module via delegatecall:
 * - This code executes AS IF it's part of the game contract
 * - Can directly access storage variables (matchTimeouts, tournaments, etc.)
 * - address(this) = game contract address
 * - msg.sender = original caller
 * - msg.value = value sent
 *
 * STATELESS: This contract declares NO storage variables of its own.
 * All storage access is to the game contract's storage via delegatecall context.
 */
contract ETour_Escalation is ETour_Base {

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

    // ============ Match Stalling Functions ============

    /**
     * @dev Mark a match as stalled when timeout is claimable
     * EXACT COPY from ETour.sol lines 1669-1683
     */
    function markMatchStalled(bytes32 matchId, uint8 tierId, uint256 timeoutOccurredAt) external onlyDelegateCall {
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        if (!timeout.isStalled) {
            timeout.isStalled = true;
            TierConfig storage config = _tierConfigs[tierId];

            // If timeoutOccurredAt is 0, use current time
            uint256 baseTime = timeoutOccurredAt == 0 ? block.timestamp : timeoutOccurredAt;

            // Use tier-specific timeout configuration
            timeout.escalation1Start = baseTime + config.timeouts.matchLevel2Delay;
            timeout.escalation2Start = baseTime + config.timeouts.matchLevel3Delay;
            timeout.activeEscalation = EscalationLevel.None;
        }
    }

    /**
     * @dev Internal helper for marking match as stalled
     * EXACT COPY from ETour.sol lines 1669-1683
     */
    function _markMatchStalled(bytes32 matchId, uint8 tierId, uint256 timeoutOccurredAt) internal {
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        if (!timeout.isStalled) {
            timeout.isStalled = true;
            TierConfig storage config = _tierConfigs[tierId];

            // If timeoutOccurredAt is 0, use current time
            uint256 baseTime = timeoutOccurredAt == 0 ? block.timestamp : timeoutOccurredAt;

            // Use tier-specific timeout configuration
            timeout.escalation1Start = baseTime + config.timeouts.matchLevel2Delay;
            timeout.escalation2Start = baseTime + config.timeouts.matchLevel3Delay;
            timeout.activeEscalation = EscalationLevel.None;
        }
    }

    /**
     * @dev Clear escalation state for a match after it completes
     * EXACT COPY from ETour.sol lines 1696-1702
     */
    function clearEscalationState(bytes32 matchId) external onlyDelegateCall {
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        timeout.isStalled = false;
        timeout.escalation1Start = 0;
        timeout.escalation2Start = 0;
        timeout.activeEscalation = EscalationLevel.None;
    }

    /**
     * @dev Internal helper for clearing escalation state
     * EXACT COPY from ETour.sol lines 1696-1702
     */
    function _clearEscalationState(bytes32 matchId) internal {
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        timeout.isStalled = false;
        timeout.escalation1Start = 0;
        timeout.escalation2Start = 0;
        timeout.activeEscalation = EscalationLevel.None;
    }

    // REMOVED: checkAndMarkStalled() external - Never called via delegatecall
    // Only internal version _checkAndMarkStalled() is used

    /**
     * @dev Internal helper for checking and marking stalled
     * EXACT COPY from ETour.sol lines 1709-1748
     */
    function _checkAndMarkStalled(
        bytes32 matchId,
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) internal returns (bool) {
        MatchTimeoutState storage timeout = matchTimeouts[matchId];

        // If already marked as stalled, return true
        if (timeout.isStalled) {
            return true;
        }

        // Check if match is active
        if (!this._isMatchActive(matchId)) {
            return false;
        }

        // Get match common data to check status
        CommonMatchData memory matchData = this._getActiveMatchData(matchId, tierId, instanceId, roundNumber, matchNumber);
        if (matchData.status != MatchStatus.InProgress) {
            return false;
        }

        // Check if current player has run out of time (using game-specific time bank logic)
        if (this._hasCurrentPlayerTimedOut(matchId)) {
            TierConfig storage config = _tierConfigs[tierId];

            // Calculate when the timeout occurred for accurate escalation timing
            // Timeout occurs at: lastMoveTime + currentPlayer's timeRemaining
            uint256 timeoutOccurredAt = matchData.lastMoveTime + config.timeouts.matchTimePerPlayer;

            // Mark as stalled with escalation timers starting from timeout occurrence
            _markMatchStalled(matchId, tierId, timeoutOccurredAt);
            return true;
        }

        return false;
    }

    // ============ Escalation Level 2 & 3 Functions ============

    /**
     * @dev Level 2 Escalation: Advanced player forces elimination of stalled match
     * EXACT COPY from ETour.sol lines 1755-1779
     */
    function forceEliminateStalledMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external {
        // SECURITY: Verify tournament is active before allowing escalation
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        require(tournament.status == TournamentStatus.InProgress, "Tournament not in progress");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);

        // Check and mark match as stalled if it qualifies
        _checkAndMarkStalled(matchId, tierId, instanceId, roundNumber, matchNumber);

        MatchTimeoutState storage timeout = matchTimeouts[matchId];

        // Require match is stalled and Level 2 is active
        require(timeout.isStalled, "Match not stalled");
        require(block.timestamp >= timeout.escalation1Start, "Level 2 not active yet");

        // Require caller is an advanced player
        bool isAdvanced = _isPlayerInAdvancedRound(tierId, instanceId, roundNumber, msg.sender);
        require(isAdvanced, "Not an advanced player");

        // Mark escalation level and double eliminate both players
        timeout.activeEscalation = EscalationLevel.Escalation2_AdvancedPlayers;

        // Complete match with double elimination (no tournament winner)
        _completeMatchDoubleEliminationInternal(tierId, instanceId, roundNumber, matchNumber);
    }

    /**
     * @dev Level 3 Escalation: External player replaces stalled players
     * EXACT COPY from ETour.sol lines 1787-1812
     */
    function claimMatchSlotByReplacement(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external {
        // SECURITY: Verify tournament is active before allowing escalation
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        require(tournament.status == TournamentStatus.InProgress, "Tournament not in progress");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);

        // Check and mark match as stalled if it qualifies
        _checkAndMarkStalled(matchId, tierId, instanceId, roundNumber, matchNumber);

        MatchTimeoutState storage timeout = matchTimeouts[matchId];

        // Require match is stalled and Level 3 window is active
        require(timeout.isStalled, "Match not stalled");
        require(block.timestamp >= timeout.escalation2Start, "Level 3 not active yet");

        // Prevent advanced players from claiming (they should use L2 instead)
        bool isAdvanced = _isPlayerInAdvancedRound(tierId, instanceId, roundNumber, msg.sender);
        require(!isAdvanced, "Advanced players cannot claim L3");

        // Prevent players currently in an active match from claiming
        bool inActiveMatch = _isPlayerInActiveMatch(tierId, instanceId, msg.sender);
        require(!inActiveMatch, "Cannot claim while in active match");

        // Mark escalation level and complete match with replacement winner
        timeout.activeEscalation = EscalationLevel.Escalation3_ExternalPlayers;

        // Complete match with replacement
        _completeMatchByReplacementInternal(tierId, instanceId, roundNumber, matchNumber, msg.sender);
    }

    // ============ Advanced Player Checking ============

    // Note: isPlayerInAdvancedRound() is now implemented in ETour_Base for direct storage access
    // The internal _isPlayerInAdvancedRound() helper below is still used within this module

    /**
     * @dev Internal helper for checking if player is currently in an active match
     */
    function _isPlayerInActiveMatch(
        uint8 tierId,
        uint8 instanceId,
        address player
    ) internal view returns (bool) {
        TierConfig storage config = _tierConfigs[tierId];

        // Check all rounds in this tournament
        for (uint8 r = 0; r < config.totalRounds; r++) {
            Round storage round = rounds[tierId][instanceId][r];
            if (!round.initialized) continue;

            // Check all matches in this round
            for (uint8 m = 0; m < round.totalMatches; m++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, r, m);
                (address p1, address p2) = this._getMatchPlayers(matchId);

                // Check if player is in this match
                if (p1 == player || p2 == player) {
                    // Check if match is in progress
                    (, , MatchStatus status) = this._getMatchResult(matchId);
                    if (status == MatchStatus.InProgress) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * @dev Internal helper for checking if player is in advanced round
     * EXACT COPY from ETour.sol lines 1822-1866
     */
    function _isPlayerInAdvancedRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 stalledRoundNumber,
        address player
    ) internal view returns (bool) {
        if (!isEnrolled[tierId][instanceId][player]) {
            return false;
        }


        // Check 1: Has player won a match in any round up to and including the stalled round?
        for (uint8 r = 0; r <= stalledRoundNumber; r++) {
            Round storage round = rounds[tierId][instanceId][r];

            for (uint8 m = 0; m < round.totalMatches; m++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, r, m);
                (address winner, bool isDraw, MatchStatus status) = this._getMatchResult(matchId);

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
                (address p1, address p2) = this._getMatchPlayers(matchId);

                if (p1 == player || p2 == player) {
                    return true;
                }
            }
        }

        return false;
    }

    // ============ Match Completion Functions ============

    /**
     * @dev Complete a match by double elimination (both players eliminated, no winner)
     * Internal version called from within the module
     */
    function _completeMatchDoubleEliminationInternal(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) internal {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        (address player1, address player2) = this._getMatchPlayers(matchId);

        this._completeMatchWithResult(matchId, address(0), false);

        // Note: Ranking assignments removed (winner-takes-all distribution)

        Round storage round = rounds[tierId][instanceId][roundNumber];
        round.completedMatches++;

        if (round.completedMatches == round.totalMatches) {
            // Check for orphaned winners and complete round (inline logic)
            _handleRoundCompletion(tierId, instanceId, roundNumber);
        }

        // Clear escalation state AFTER _handleRoundCompletion checks it
        // FIX: Moved from before _handleRoundCompletion to preserve escalation state
        // for tournament completionReason determination
        _clearEscalationState(matchId);
    }

    /**
     * @dev Complete a match by replacement (external player takes over as winner)
     * Internal version called from within the module
     */
    function _completeMatchByReplacementInternal(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address replacementPlayer
    ) internal {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        (address player1, address player2) = this._getMatchPlayers(matchId);

        this._completeMatchWithResult(matchId, replacementPlayer, false);

        // Note: Ranking assignments removed (winner-takes-all distribution)

        // Add replacement player to tournament if not already enrolled
        if (!isEnrolled[tierId][instanceId][replacementPlayer]) {
            enrolledPlayers[tierId][instanceId].push(replacementPlayer);
            isEnrolled[tierId][instanceId][replacementPlayer] = true;
            TournamentInstance storage tournament = tournaments[tierId][instanceId];
            tournament.enrolledCount++;
        }

        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (roundNumber < tournament.actualTotalRounds - 1) {
            // Advance winner inline
            _advanceWinnerToNextRound(tierId, instanceId, roundNumber, matchNumber, replacementPlayer);
        }

        Round storage round = rounds[tierId][instanceId][roundNumber];
        round.completedMatches++;

        if (round.completedMatches == round.totalMatches) {
            // Check for orphaned winners and complete round (inline logic)
            _handleRoundCompletion(tierId, instanceId, roundNumber);
        }

        // Clear escalation state AFTER _handleRoundCompletion checks it
        // FIX: Moved from before _handleRoundCompletion to preserve escalation state
        // for tournament completionReason determination
        _clearEscalationState(matchId);
    }

    // REMOVED: assignRankingOnElimination() and _assignRankingOnElimination()
    // Both were no-ops since rankings were removed with winner-takes-all distribution

    // ============ Escalation Availability Helpers (Public View) ============
    // Note: All escalation view functions and claimTimeoutWin kept in ETour_Base
    // to avoid stack depth issues and preserve error messages

    // ============ Helper Functions for Escalation ============

    /**
     * @dev Advance winner to next round
     */
    function _advanceWinnerToNextRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 currentRound,
        uint8 currentMatchNum,
        address winner
    ) internal {
        // Calculate next round and match position
        uint8 nextRound = currentRound + 1;
        uint8 nextMatchNum = currentMatchNum / 2;

        // Get or create next match
        Round storage nextRoundStruct = rounds[tierId][instanceId][nextRound];

        // Initialize next round if needed
        if (!nextRoundStruct.initialized) {
            TierConfig storage config = _tierConfigs[tierId];
            // Calculate matches for next round: playerCount / 2^(round+1)
            uint8 nextRoundMatches = config.playerCount / uint8(2 ** (nextRound + 1));
            nextRoundStruct.initialized = true;
            nextRoundStruct.totalMatches = nextRoundMatches;
            nextRoundStruct.completedMatches = 0;
        }

        bytes32 nextMatchId = _getMatchId(tierId, instanceId, nextRound, nextMatchNum);


        // Set player in next match (use game interface to set properly)
        uint8 slot = currentMatchNum % 2; // 0 or 1
        this._setMatchPlayer(nextMatchId, slot, winner);

        // If both players assigned, initialize the match
        (address p1, address p2) = this._getMatchPlayers(nextMatchId);
        if (p1 != address(0) && p2 != address(0)) {
            this._initializeMatchForPlay(nextMatchId, tierId);
        }
    }

    /**
     * @dev Handle round completion logic
     * Simplified version - just marks tournament complete if appropriate
     */
    function _handleRoundCompletion(uint8 tierId, uint8 instanceId, uint8 roundNumber) internal {
        TierConfig storage config = _tierConfigs[tierId];
        Round storage round = rounds[tierId][instanceId][roundNumber];

        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Check if this is the final round
        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (roundNumber == tournament.actualTotalRounds - 1) {
            // Finals completed - check for winner
            bytes32 finalsMatchId = _getMatchId(tierId, instanceId, roundNumber, 0);
            (address winner, bool isDraw, ) = this._getMatchResult(finalsMatchId);
            if (!isDraw && winner != address(0)) {
                // Check if this was an escalation-based win
                MatchTimeoutState storage finalsTimeout = matchTimeouts[finalsMatchId];
                if (finalsTimeout.activeEscalation == EscalationLevel.Escalation3_ExternalPlayers) {
                    // ML3 replacement win
                    tournament.completionReason = CompletionReason.Replacement;
                } else {
                    // Normal winner (including ML1/timeout)
                    tournament.completionReason = CompletionReason.NormalWin;
                }
                tournament.winner = winner;
                tournament.status = TournamentStatus.Completed;
                // Removed: Ranking assignment (no longer needed with winner-takes-all)
            } else if (isDraw) {
                // Draw in finals
                tournament.finalsWasDraw = true;
                tournament.completionReason = CompletionReason.Draw;
                tournament.status = TournamentStatus.Completed;
                // Removed: Ranking assignments for draw (no longer needed)
            } else if (!isDraw && winner == address(0)) {
                // Both finalists were eliminated (ML2 double elimination)
                // Set all-draw resolution to distribute prizes equally to any remaining eligible players
                tournament.status = TournamentStatus.Completed;
                tournament.allDrawResolution = true;
                tournament.allDrawRound = roundNumber;
                tournament.winner = address(0);
                tournament.completionReason = CompletionReason.ForceElimination;
            }
        } else {
            // Non-final round completed - check for orphaned winner scenario
            // Count winners from current round
            uint8 winnersCount = 0;
            address lastWinner = address(0);

            for (uint8 m = 0; m < round.totalMatches; m++) {
                bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, m);
                (address winner, bool isDraw, MatchStatus status) = this._getMatchResult(matchId);

                if (status == MatchStatus.Completed && !isDraw && winner != address(0)) {
                    winnersCount++;
                    lastWinner = winner;
                }
            }

            // Check for sole remaining player (either from matches or as bye)
            // BUG FIX: Check if next round has any players (from walkovers)
            // before declaring sole winner. This prevents premature tournament
            // completion when walkover players are already in the next round.
            uint8 nextRound = roundNumber + 1;
            Round storage nextRoundStruct = rounds[tierId][instanceId][nextRound];

            uint8 playersInNextRound = 0;
            address solePlayerInNextRound = address(0);
            if (nextRoundStruct.initialized) {
                for (uint8 m = 0; m < nextRoundStruct.totalMatches; m++) {
                    bytes32 nextMatchId = _getMatchId(tierId, instanceId, nextRound, m);
                    (address p1, address p2) = this._getMatchPlayers(nextMatchId);
                    if (p1 != address(0)) {
                        playersInNextRound++;
                        solePlayerInNextRound = p1;
                    }
                    if (p2 != address(0)) {
                        playersInNextRound++;
                        solePlayerInNextRound = p2;
                    }
                }
                // Check for bye player (odd players in next round)
                if (nextRoundStruct.playerCount % 2 == 1) {
                    bytes32 byeMatchId = _getMatchId(tierId, instanceId, nextRound, nextRoundStruct.totalMatches);
                    (address byeP1, address byeP2) = this._getMatchPlayers(byeMatchId);
                    if (byeP1 != address(0)) {
                        playersInNextRound++;
                        solePlayerInNextRound = byeP1;
                    }
                    if (byeP2 != address(0)) {
                        playersInNextRound++;
                        solePlayerInNextRound = byeP2;
                    }
                }
            }

            // Complete tournament if exactly 1 player remains (either from matches or bye)
            if ((winnersCount == 1 && playersInNextRound == 0 && lastWinner != address(0)) ||
                (winnersCount == 0 && playersInNextRound == 1 && solePlayerInNextRound != address(0))) {
                TournamentInstance storage tournament = tournaments[tierId][instanceId];
                tournament.winner = winnersCount == 1 ? lastWinner : solePlayerInNextRound;
                tournament.status = TournamentStatus.Completed;
                tournament.completionReason = CompletionReason.NormalWin;
                // Removed: Ranking assignment (no longer needed with winner-takes-all)

                // NOTE: Prize distribution, earnings update, event emission, and reset
                // are handled by the game contract (TicTacChain) after detecting completion.
                // This is the same pattern used by MODULE_MATCHES.completeTournament()
            }
        }
    }
}
