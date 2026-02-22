// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ETour_Base.sol";

/**
 * @title ETour_Matches
 * @dev Stateless module for match creation, round progression, and winner advancement
 *
 * This module handles:
 * - Round initialization and match creation
 * - Match completion and winner advancement
 * - Round completion and tournament finalization
 * - Orphaned winner handling
 * - Player consolidation logic
 *
 * CRITICAL - DELEGATECALL SEMANTICS:
 * When game contract calls this module via delegatecall:
 * - This code executes AS IF it's part of the game contract
 * - Can directly access storage variables (tournaments, rounds, etc.)
 * - address(this) = game contract address
 * - msg.sender = original caller
 *
 * STATELESS: This contract declares NO storage variables of its own.
 * All storage access is to the game contract's storage via delegatecall context.
 */
contract ETour_Matches is ETour_Base {

    // Constructor - modules need to set module addresses even though they're stateless
    constructor() ETour_Base(address(0), address(0), address(0), address(0), address(0)) {}

    // ============ Abstract Function Stubs (Empty implementations for module deployment) ============
    // During delegatecall, game contract's implementations are called via this.function()
    function _createMatchGame(uint8, uint8, uint8, uint8, address, address) public override {}
    function _resetMatchGame(bytes32) public override {}
    function _getMatchResult(bytes32) public view override returns (address, bool, MatchStatus) { return (address(0), false, MatchStatus.NotStarted); }
    function _getMatchPlayers(bytes32) public view override returns (address, address) { return (address(0), address(0)); }
    function _setMatchPlayer(bytes32, uint8, address) public override {}
    function _initializeMatchForPlay(bytes32, uint8) public override {}
    function _completeMatchWithResult(bytes32, address, bool) public override {}
    function _getTimeIncrement() public view override returns (uint256) { return 0; }
    function _hasCurrentPlayerTimedOut(bytes32) public view override returns (bool) { return false; }
    function _isMatchActive(bytes32) public view override returns (bool) { return false; }
    function _getActiveMatchData(bytes32, uint8, uint8, uint8, uint8) public view override returns (CommonMatchData memory) { return CommonMatchData({
        player1: address(0), player2: address(0), winner: address(0), loser: address(0),
        status: MatchStatus.NotStarted, isDraw: false, startTime: 0, lastMoveTime: 0,
        tierId: 0, instanceId: 0, roundNumber: 0, matchNumber: 0, isCached: false
    }); }

    // ============ Round Initialization ============

    /**
     * @dev Initialize a new round with matches
     * EXACT COPY from ETour.sol lines 869-911
     * Module implementation - called via delegatecall from game contracts
     */
    function initializeRound(uint8 tierId, uint8 instanceId, uint8 roundNumber) public override onlyDelegateCall {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Calculate playerCount for this round
        uint8 playerCount;
        if (roundNumber == 0) {
            playerCount = tournament.enrolledCount;
        } else {
            Round storage prevRound = rounds[tierId][instanceId][roundNumber - 1];
            // Winners from matches + bye player if previous round had odd players
            playerCount = (prevRound.totalMatches - prevRound.drawCount) + (prevRound.playerCount % 2);
        }

        uint8 matchCount = playerCount / 2;
        require(matchCount > 0 || roundNumber > 0, "Invalid match count");

        Round storage round = rounds[tierId][instanceId][roundNumber];
        round.totalMatches = matchCount;
        round.completedMatches = 0;
        round.initialized = true;
        round.drawCount = 0;
        round.playerCount = playerCount;

        if (roundNumber == 0) {
            address[] storage players = enrolledPlayers[tierId][instanceId];
            require(players.length >= 2, "Not enough players");

            address walkoverPlayer = address(0);
            if (tournament.enrolledCount % 2 == 1) {
                uint8 walkoverIndex = uint8(uint256(keccak256(abi.encodePacked(
                    block.prevrandao, block.timestamp, tierId, instanceId, tournament.enrolledCount
                ))) % tournament.enrolledCount);

                walkoverPlayer = players[walkoverIndex];
                players[walkoverIndex] = players[tournament.enrolledCount - 1];
                players[tournament.enrolledCount - 1] = walkoverPlayer;
            }

            for (uint8 i = 0; i < matchCount;) {
                require(players[i * 2] != address(0) && players[i * 2 + 1] != address(0), "Invalid player addresses");
                this._createMatchGame(tierId, instanceId, roundNumber, i, players[i * 2], players[i * 2 + 1]);
                unchecked { i++; }
            }

            if (walkoverPlayer != address(0)) {
                advanceWinner(tierId, instanceId, roundNumber, matchCount, walkoverPlayer);
            }
        }
    }

    // ============ Match Completion ============

    /**
     * @dev Complete a match and handle advancement
     * EXACT COPY from ETour.sol lines 999-1047
     * NOTE: Depends on _clearEscalationState from Escalation module
     */
    function completeMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address winner,
        bool isDraw,
        CompletionReason reason
    ) public onlyDelegateCall {
        // Note: Escalation state is cleared by the game contract before calling completeMatch

        if (!isDraw) {
            TournamentInstance storage tournament = tournaments[tierId][instanceId];

            // Note: Loser elimination hook is called by the game contract after delegatecall
            // (can't call hooks from within modules as they use empty stubs)

            // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
            if (roundNumber < tournament.actualTotalRounds - 1) {
                advanceWinner(tierId, instanceId, roundNumber, matchNumber, winner);
            }
            // Note: Winner elimination check happens when their next match completes (or tournament ends)
            // This keeps winners in the active tournament list even while waiting for next round to start
        }

        Round storage round = rounds[tierId][instanceId][roundNumber];
        round.completedMatches++;

        if (isDraw) {
            round.drawCount++;
        }

        // BUG FIX: Handle consolidation scenario where totalMatches = 0
        // Round is complete when completedMatches == totalMatches, OR
        // when totalMatches = 0 and we have 1 completed match (consolidation finals)
        bool isRoundComplete = (round.completedMatches == round.totalMatches) ||
                              (round.totalMatches == 0 && round.completedMatches == 1);

        if (isRoundComplete) {
            if (hasOrphanedWinners(tierId, instanceId, roundNumber)) {
                processOrphanedWinners(tierId, instanceId, roundNumber);
                // After processing orphaned winners, check if tournament can complete
                // This handles the case where only one winner remains after force elimination
                checkForSoleWinnerCompletion(tierId, instanceId, roundNumber);
            }
            completeRound(tierId, instanceId, roundNumber, reason);
        }
    }

    // ============ Winner Advancement ============

    /**
     * @dev Advance winner to next round
     * OPTIMIZED: Simplified logic and reduced redundant calls
     */
    function advanceWinner(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address winner
    ) public onlyDelegateCall {
        uint8 nextRound = roundNumber + 1;
        Round storage nextRoundData = rounds[tierId][instanceId][nextRound];
        if (!nextRoundData.initialized) {
            initializeRound(tierId, instanceId, nextRound);
        }

        bytes32 nextMatchId = _getMatchId(tierId, instanceId, nextRound, matchNumber / 2);

        // Set player based on match parity
        this._setMatchPlayer(nextMatchId, matchNumber & 1, winner);

        // Check if both players are set and match can start
        (address p1, address p2) = this._getMatchPlayers(nextMatchId);
        if (p1 != address(0) && p2 != address(0)) {
            require(p1 != p2, "Cannot match player against themselves");
            this._initializeMatchForPlay(nextMatchId, tierId);
        }
    }

    // ============ Round Completion ============

    /**
     * @dev Complete a round and handle tournament progression
     * REFACTORED: Broken down into smaller helper functions
     */
    function completeRound(uint8 tierId, uint8 instanceId, uint8 roundNumber, CompletionReason reason) internal {
        if (_isActualFinalsRound(tierId, instanceId, roundNumber)) {
            _handleFinalsCompletion(tierId, instanceId, roundNumber, reason);
            return;
        }

        Round storage round = rounds[tierId][instanceId][roundNumber];
        if (round.drawCount == round.totalMatches && round.totalMatches > 0) {
            address[] memory remainingPlayers = getRemainingPlayers(tierId, instanceId, roundNumber);
            completeTournamentAllDraw(tierId, instanceId, roundNumber, remainingPlayers);
            return;
        }

        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        tournament.currentRound = roundNumber + 1;
        consolidateScatteredPlayers(tierId, instanceId, roundNumber + 1);

        if (tournament.status == TournamentStatus.Completed) {
            return;
        }

        if (_checkAndHandleSoleWinner(tierId, instanceId, roundNumber)) {
            return;
        }

        // Inline: Handle finals walkover scenario
        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        uint8 nextRound = roundNumber + 1;
        if (nextRound == tournament.actualTotalRounds - 1) {
            bytes32 finalsMatchId = _getMatchId(tierId, instanceId, nextRound, 0);
            (address fp1, address fp2) = this._getMatchPlayers(finalsMatchId);

            if ((fp1 != address(0) && fp2 == address(0)) || (fp2 != address(0) && fp1 == address(0))) {
                completeTournament(tierId, instanceId, fp1 != address(0) ? fp1 : fp2);
            }
        }
    }

    /**
     * @dev Check if round is actual finals (not semi-finals with walkover)
     */
    function _isActualFinalsRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber
    ) internal view returns (bool) {
        Round storage round = rounds[tierId][instanceId][roundNumber];
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (roundNumber == tournament.actualTotalRounds - 1) {
            return true;
        }

        bool appearsToBeFinalsMatch = (roundNumber > 0 && round.completedMatches == 1 &&
                                      (round.totalMatches == 1 || round.totalMatches == 0));

        if (!appearsToBeFinalsMatch || roundNumber >= tournament.actualTotalRounds - 1) {
            return false;
        }

        // Inline: Check if next round has players (walkover scenario)
        uint8 nextRound = roundNumber + 1;
        for (uint8 m = 0; m < 4;) {
            bytes32 nextMatchId = _getMatchId(tierId, instanceId, nextRound, m);
            (address p1, address p2) = this._getMatchPlayers(nextMatchId);
            if (p1 != address(0) || p2 != address(0)) {
                return false; // Has players, not finals
            }
            unchecked { m++; }
        }
        return true; // No players in next round, this is finals
    }

    /**
     * @dev Handle completion of finals match
     */
    function _handleFinalsCompletion(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        CompletionReason reason
    ) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        bytes32 finalMatchId = _getMatchId(tierId, instanceId, roundNumber, 0);
        (address finalWinner, bool finalIsDraw, ) = this._getMatchResult(finalMatchId);

        if (finalIsDraw) {
            tournament.finalsWasDraw = true;
            tournament.completionReason = CompletionReason.AllDrawScenario;
            tournament.winner = address(0);
            completeTournament(tierId, instanceId, address(0));
        } else {
            // Use the passed completion reason (e.g., Timeout for ML1)
            tournament.completionReason = reason;
            completeTournament(tierId, instanceId, finalWinner);
        }
    }

    /**
     * @dev Check for sole winner scenario and complete if found
     * @return true if tournament was completed
     */
    function _checkAndHandleSoleWinner(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber
    ) internal returns (bool) {
        Round storage round = rounds[tierId][instanceId][roundNumber];
        Round storage nextRoundData = rounds[tierId][instanceId][roundNumber + 1];

        if (!nextRoundData.initialized || nextRoundData.totalMatches != 0) {
            return false;
        }

        address soleWinner = address(0);
        uint8 winnerCount = 0;

        for (uint8 i = 0; i < round.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, i);
            (address matchWinner, bool matchIsDraw, MatchStatus matchStatus) = this._getMatchResult(matchId);
            if (matchStatus == MatchStatus.Completed && matchWinner != address(0) && !matchIsDraw) {
                soleWinner = matchWinner;
                winnerCount++;
            }
            unchecked { i++; }
        }

        if (winnerCount != 1) {
            return false;
        }

        // Inline: Count players in next round for walkover check
        uint8 playersInNextRound = 0;
        uint8 nextRound = roundNumber + 1;
        for (uint8 m = 0; m < 4;) {
            bytes32 nextMatchId = _getMatchId(tierId, instanceId, nextRound, m);
            (address p1, address p2) = this._getMatchPlayers(nextMatchId);
            if (p1 != address(0)) playersInNextRound++;
            if (p2 != address(0)) playersInNextRound++;
            if (p1 == address(0) && p2 == address(0)) break;
            unchecked { m++; }
        }

        if (playersInNextRound == 0) {
            completeTournament(tierId, instanceId, soleWinner);
            return true;
        }

        return false;
    }

    // ============ Tournament Completion ============

    /**
     * @dev Complete tournament and distribute prizes
     * EXACT COPY from ETour.sol lines 1142-1172
     * INTERNAL: Only called from within this module
     */
    function completeTournament(uint8 tierId, uint8 instanceId, address winner) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        // Set status to Completed before reset (will be set to Enrolling during reset)
        tournament.status = TournamentStatus.Completed;

        if (tournament.winner == address(0)) {
            tournament.winner = winner;
            // Removed: Ranking assignments (no longer needed with winner-takes-all)
        }

        // NOTE: Prize distribution, earnings update, reset, and event emission are handled by the game contract
        // (TicTacChain) after it detects tournament completion, because nested delegatecalls
        // from MODULE_MATCHES -> MODULE_PRIZES don't work (MODULE_PRIZES = address(0) in module bytecode)
    }

    /**
     * @dev Complete tournament with all-draw resolution
     * EXACT COPY from ETour.sol lines 1174-1199
     * INTERNAL: Only called from within this module
     */
    function completeTournamentAllDraw(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        address[] memory remainingPlayers
    ) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        // Set status to Completed before reset (will be set to Enrolling during reset)
        tournament.status = TournamentStatus.Completed;
        tournament.allDrawResolution = true;
        tournament.allDrawRound = roundNumber;
        tournament.winner = address(0);
        tournament.completionReason = CompletionReason.AllDrawScenario;

        // Silence unused parameter warning (used by game contract)
        remainingPlayers;

        // NOTE: Prize distribution, earnings update, and reset are handled by the game contract
        // (TicTacChain) after it detects tournament completion, because nested delegatecalls
        // from MODULE_MATCHES -> MODULE_PRIZES don't work (MODULE_PRIZES = address(0) in module bytecode)
    }

    // ============ Player Consolidation ============

    /**
     * @dev Consolidate scattered players into complete matches
     * REFACTORED: Combined loops for better gas efficiency
     */
    function consolidateScatteredPlayers(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber
    ) internal {
        Round storage round = rounds[tierId][instanceId][roundNumber];
        if (!round.initialized) {
            return;
        }

        // Single loop: collect players AND check if consolidation needed
        address[] memory playersInRound = new address[](round.totalMatches * 2);
        uint8 playerCount = 0;
        bool needsConsolidation = false;

        for (uint8 i = 0; i < round.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, i);
            (address p1, address p2) = this._getMatchPlayers(matchId);

            bool hasPlayer1 = p1 != address(0);
            bool hasPlayer2 = p2 != address(0);

            if (hasPlayer1) playersInRound[playerCount++] = p1;
            if (hasPlayer2) playersInRound[playerCount++] = p2;

            // Check if match is incomplete (XOR logic)
            if (hasPlayer1 != hasPlayer2) {
                needsConsolidation = true;
            }
            unchecked { i++; }
        }

        if (playerCount == 0 || !needsConsolidation) {
            return;
        }

        if (playerCount == 1) {
            completeTournament(tierId, instanceId, playersInRound[0]);
            return;
        }

        // Reset all matches
        for (uint8 i = 0; i < round.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, i);
            this._resetMatchGame(matchId);
            unchecked { i++; }
        }

        // Handle walkover if odd number of players
        uint8 originalPlayerCount = playerCount;  // Save before walkover selection
        address walkoverPlayer = address(0);
        if (playerCount % 2 == 1) {
            (walkoverPlayer, playerCount) = _selectWalkoverPlayer(
                playersInRound, playerCount, tierId, instanceId, roundNumber
            );
        }

        // Update round and create new matches
        uint8 newMatchCount = playerCount / 2;
        round.totalMatches = newMatchCount;
        round.completedMatches = 0;
        round.drawCount = 0;
        round.playerCount = originalPlayerCount;

        for (uint8 i = 0; i < newMatchCount;) {
            this._createMatchGame(
                tierId,
                instanceId,
                roundNumber,
                i,
                playersInRound[i * 2],
                playersInRound[i * 2 + 1]
            );
            unchecked { i++; }
        }

        if (walkoverPlayer != address(0)) {
            advanceWinner(tierId, instanceId, roundNumber, newMatchCount, walkoverPlayer);
        }
    }

    /**
     * @dev Consolidate and start next round when odd number of winners after ML2/ML3
     * REFACTORED: Using walkover helper and early returns
     */
    function consolidateAndStartOddRound(
        uint8 tierId,
        uint8 instanceId,
        uint8 completedRound
    ) public onlyDelegateCall {
        Round storage completedRoundStruct = rounds[tierId][instanceId][completedRound];
        if (!completedRoundStruct.initialized) {
            return;
        }

        // Count winners from completed round
        address[] memory winners = new address[](completedRoundStruct.totalMatches * 2);
        uint8 winnersCount = 0;

        for (uint8 i = 0; i < completedRoundStruct.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, completedRound, i);
            (address winner, bool isDraw, MatchStatus status) = this._getMatchResult(matchId);

            if (status == MatchStatus.Completed && !isDraw && winner != address(0)) {
                winners[winnersCount++] = winner;
            }
            unchecked { i++; }
        }

        // Early return if no winners or even number
        if (winnersCount == 0 || winnersCount % 2 == 0) {
            return;
        }

        uint8 nextRound = completedRound + 1;
        Round storage nextRoundStruct = rounds[tierId][instanceId][nextRound];

        // If already initialized, use consolidation logic
        if (nextRoundStruct.initialized) {
            consolidateScatteredPlayers(tierId, instanceId, nextRound);
            return;
        }

        // Initialize next round with odd winner handling
        uint8 properMatchCount = (winnersCount - 1) / 2;
        nextRoundStruct.initialized = true;
        nextRoundStruct.totalMatches = properMatchCount;
        nextRoundStruct.completedMatches = 0;
        nextRoundStruct.drawCount = 0;
        nextRoundStruct.playerCount = winnersCount;

        // Select walkover player
        address walkoverPlayer;
        (walkoverPlayer, winnersCount) = _selectWalkoverPlayer(
            winners, winnersCount, tierId, instanceId, nextRound
        );

        // Create matches for remaining players
        for (uint8 i = 0; i < properMatchCount;) {
            this._createMatchGame(
                tierId,
                instanceId,
                nextRound,
                i,
                winners[i * 2],
                winners[i * 2 + 1]
            );
            unchecked { i++; }
        }

        // Advance walkover player if not finals
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (nextRound < tournament.actualTotalRounds - 1) {
            advanceWinner(tierId, instanceId, nextRound, properMatchCount, walkoverPlayer);
        }
    }

    // ============ Orphaned Winner Handling ============

    /**
     * @dev Check if round has orphaned winners
     * REFACTORED: Using helper to reduce duplication
     * INTERNAL: Only called from within this module
     */
    function hasOrphanedWinners(uint8 tierId, uint8 instanceId, uint8 roundNumber) internal view returns (bool) {
        uint8 matchCount = getMatchCountForRound(tierId, instanceId, roundNumber);

        for (uint8 i = 0; i < matchCount;) {
            if (i + 1 >= matchCount) break;

            bytes32 matchId1 = _getMatchId(tierId, instanceId, roundNumber, i);
            bytes32 matchId2 = _getMatchId(tierId, instanceId, roundNumber, i + 1);

            (address w1, bool d1, MatchStatus s1) = this._getMatchResult(matchId1);
            (address w2, bool d2, MatchStatus s2) = this._getMatchResult(matchId2);

            bool m1Complete = s1 == MatchStatus.Completed;
            bool m2Complete = s2 == MatchStatus.Completed;
            bool m1HasWinner = w1 != address(0) && !d1;
            bool m2HasWinner = w2 != address(0) && !d2;

            if (m1Complete && m2Complete && (m1HasWinner != m2HasWinner)) {
                return true;
            }
            unchecked { i += 2; }
        }

        return false;
    }

    /**
     * @dev Process orphaned winners by advancing them
     * REFACTORED: Combined logic to reduce duplication
     */
    function processOrphanedWinners(uint8 tierId, uint8 instanceId, uint8 roundNumber) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (roundNumber >= tournament.actualTotalRounds - 1) {
            return;
        }

        uint8 matchCount = getMatchCountForRound(tierId, instanceId, roundNumber);

        for (uint8 i = 0; i < matchCount;) {
            if (i + 1 >= matchCount) break;

            bytes32 matchId1 = _getMatchId(tierId, instanceId, roundNumber, i);
            bytes32 matchId2 = _getMatchId(tierId, instanceId, roundNumber, i + 1);

            (address w1, bool d1, MatchStatus s1) = this._getMatchResult(matchId1);
            (address w2, bool d2, MatchStatus s2) = this._getMatchResult(matchId2);

            bool m1Complete = s1 == MatchStatus.Completed;
            bool m2Complete = s2 == MatchStatus.Completed;

            if (m1Complete && m2Complete) {
                bool m1HasWinner = w1 != address(0) && !d1;
                bool m2HasWinner = w2 != address(0) && !d2;

                if (m1HasWinner && !m2HasWinner) {
                    advanceWinner(tierId, instanceId, roundNumber, i, w1);
                } else if (m2HasWinner && !m1HasWinner) {
                    advanceWinner(tierId, instanceId, roundNumber, i + 1, w2);
                }
            }
            unchecked { i += 2; }
        }
    }

    /**
     * @dev Get remaining players in a round
     * OPTIMIZED: Single allocation, no temp array
     * INTERNAL: Only called from within this module
     */
    function getRemainingPlayers(uint8 tierId, uint8 instanceId, uint8 roundNumber) internal view returns (address[] memory) {
        Round storage round = rounds[tierId][instanceId][roundNumber];

        // First pass: count players
        uint8 count = 0;
        for (uint8 i = 0; i < round.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, i);
            (address p1, address p2) = this._getMatchPlayers(matchId);
            if (p1 != address(0)) count++;
            if (p2 != address(0)) count++;
            unchecked { i++; }
        }

        // Allocate exact size
        address[] memory result = new address[](count);

        // Second pass: fill array
        uint8 index = 0;
        for (uint8 i = 0; i < round.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, i);
            (address p1, address p2) = this._getMatchPlayers(matchId);
            if (p1 != address(0)) result[index++] = p1;
            if (p2 != address(0)) result[index++] = p2;
            unchecked { i++; }
        }

        return result;
    }

    /**
     * @dev Check if tournament should complete with sole winner after orphan processing
     * REFACTORED: Early returns and simplified logic
     * INTERNAL: Only called from within this module
     */
    function checkForSoleWinnerCompletion(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber
    ) internal {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];
        if (tournament.status == TournamentStatus.Completed) {
            return;
        }

        // Use actualTotalRounds (based on enrolled players) not config.totalRounds (tier max)
        if (roundNumber >= tournament.actualTotalRounds - 1) {
            return;
        }

        uint8 nextRound = roundNumber + 1;
        Round storage nextRoundData = rounds[tierId][instanceId][nextRound];
        if (!nextRoundData.initialized) {
            return;
        }

        address soleWinner = address(0);
        uint8 advancedPlayerCount = 0;

        for (uint8 i = 0; i < nextRoundData.totalMatches;) {
            bytes32 matchId = _getMatchId(tierId, instanceId, nextRound, i);
            (address p1, address p2) = this._getMatchPlayers(matchId);

            if (p1 != address(0)) {
                soleWinner = p1;
                advancedPlayerCount++;
            }
            if (p2 != address(0)) {
                soleWinner = p2;
                advancedPlayerCount++;
            }
            unchecked { i++; }
        }

        // Check for bye player (odd players in next round)
        if (nextRoundData.playerCount % 2 == 1) {
            bytes32 byeMatchId = _getMatchId(tierId, instanceId, nextRound, nextRoundData.totalMatches);
            (address byeP1, address byeP2) = this._getMatchPlayers(byeMatchId);
            if (byeP1 != address(0)) {
                soleWinner = byeP1;
                advancedPlayerCount++;
            }
            if (byeP2 != address(0)) {
                soleWinner = byeP2;
                advancedPlayerCount++;
            }
        }

        if (advancedPlayerCount == 1) {
            completeTournament(tierId, instanceId, soleWinner);
        }
    }

    // ============ Helper Functions ============

    /**
     * @dev Get match count for a round
     * EXACT COPY from ETour.sol lines 914-930
     * INTERNAL: Only called from within this module (game contracts have their own implementations)
     */
    function getMatchCountForRound(uint8 tierId, uint8 instanceId, uint8 roundNumber) internal view returns (uint8) {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        if (roundNumber == 0) {
            return tournament.enrolledCount / 2;
        }

        Round storage prevRound = rounds[tierId][instanceId][roundNumber - 1];
        // Winners from matches + bye player if previous round had odd players
        uint8 winnersFromPrevRound = (prevRound.totalMatches - prevRound.drawCount) + (prevRound.playerCount % 2);

        return winnersFromPrevRound / 2;
    }

    /**
     * @dev Select a random walkover player from array
     */
    function _selectWalkoverPlayer(
        address[] memory players,
        uint8 playerCount,
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber
    ) internal view returns (address walkoverPlayer, uint8 newPlayerCount) {
        uint8 walkoverIndex = uint8(uint256(keccak256(abi.encodePacked(
            block.prevrandao, block.timestamp, tierId, instanceId, roundNumber, playerCount
        ))) % playerCount);
        walkoverPlayer = players[walkoverIndex];
        players[walkoverIndex] = players[playerCount - 1];
        newPlayerCount = playerCount - 1;
    }

    // ============ Player Advancement Detection ============

    /**
     * @dev Check if a player has advanced past the stalled round
     *
     * Used by Level 2 escalation to determine if a player can force-eliminate stalled players.
     * A player is "advanced" if they either:
     * 1. Won a match in rounds 0 to stalledRoundNumber (inclusive), OR
     * 2. Are assigned to a match in a round after stalledRoundNumber
     *
     * This is a VIEW function called via staticcall from ETour_Escalation module.
     *
     * @param tierId Tournament tier
     * @param instanceId Instance within tier
     * @param stalledRoundNumber Round number of the stalled match
     * @param player Address to check
     * @return hasAdvanced True if player is in an advanced round
     *
     * EXTRACTION: Removes ~45 lines of duplicate code from each game contract
     */
    // Note: isPlayerInAdvancedRound() is now implemented in ETour_Base for direct storage access
}
