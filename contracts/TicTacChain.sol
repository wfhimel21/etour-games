// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ETour_Base.sol";

/**
 * @title TicTacChain
 * @dev Classic Tic-Tac-Toe game implementing ETour tournament protocol (Modular Architecture)
 * Simple, solved game used as the lowest-barrier demonstration of the ETour protocol.
 *
 * This contract demonstrates modular ETour integration by:
 * 1. Inheriting ETour_Base for shared tournament state
 * 2. Delegating to specialized modules (Core, Matches, Prizes, etc.)
 * 3. Implementing abstract functions from ETour_Base (8 functions)
 * 4. Managing game-specific logic (board state, win detection, time banks)
 *
 * Part of the RW3 (Reclaim Web3) movement.
 */
contract TicTacChain is ETour_Base {

    // ============ Game-Specific Structs ============

    /**
     * @dev Match storage structure for active Tic-Tac-Toe games
     * Board is packed: 2 bits per cell (0=empty, 1=player1, 2=player2)
     * Total 9 cells = 18 bits (fits in uint256 with room to spare)
     */
    // Note: Match struct moved to ETour_Base for consistency across all games

    /**
     * @dev Extended match data for TicTacToe including common fields and game-specific state
     * Used for view functions to return complete match information
     */
    struct TicTacToeMatchData {
        CommonMatchData common;        // Standardized tournament match data
        uint256 packedBoard;           // Game-specific: packed board state
        address currentTurn;           // Who plays next (address(0) for completed)
        address firstPlayer;           // Who started the match
        uint256 player1TimeRemaining;  // Time bank for player1
        uint256 player2TimeRemaining;  // Time bank for player2
        uint256 lastMoveTimestamp;     // When last move was made
        string moves;                  // Move history (cell positions for replay)
    }

    // ============ Game-Specific Storage ============

    // Note: matches mapping moved to ETour_Base for consistency across all games

    // ============ Module Addresses ============
    // (All ETour modules inherited from ETour_Base, game logic is built-in)

    // ============ Events ============

    event MoveMade(bytes32 indexed matchId, address indexed player, uint8 cellIndex);

    // ============ Constructor ============

    constructor(
        address _moduleCoreAddress,
        address _moduleMatchesAddress,
        address _modulePrizesAddress,
        address _moduleRaffleAddress,
        address _moduleEscalationAddress
    ) ETour_Base(
        _moduleCoreAddress,
        _moduleMatchesAddress,
        _modulePrizesAddress,
        _moduleRaffleAddress,
        _moduleEscalationAddress
    ) {
        TimeoutConfig memory timeouts = TimeoutConfig({
            matchTimePerPlayer: 120,
            timeIncrementPerMove: 15,
            matchLevel2Delay: 120,
            matchLevel3Delay: 240,
            enrollmentWindow: 0,
            enrollmentLevel2Delay: 300
        });

        // Register tiers 0-2 in loop (saves bytecode vs individual calls)
        for (uint8 i = 0; i < 3; i++) {
            timeouts.enrollmentWindow = i == 0 ? 180 : (i == 1 ? 300 : 480);
            (bool success, ) = MODULE_CORE.delegatecall(
                abi.encodeWithSignature("registerTier(uint8,uint8,uint8,uint256,(uint256,uint256,uint256,uint256,uint256,uint256))",
                    i,
                    i == 0 ? 2 : (i == 1 ? 4 : 8),
                    i == 0 ? 100 : (i == 1 ? 50 : 25),
                    (i == 0 ? 0.0003 ether : (i == 1 ? 0.0007 ether : 0.0013 ether)),
                    timeouts
                )
            );
            require(success, "RT");
        }

        // Initialize progressive raffle thresholds for TicTacChain
        // Lower thresholds than base ETour to make raffles more accessible
        // Last threshold (1.0 ether) repeats for all future raffles
        raffleThresholds.push(0.001 ether);  // Raffle #0
        raffleThresholds.push(0.005 ether);  // Raffle #1
        raffleThresholds.push(0.02 ether);   // Raffle #2
        raffleThresholds.push(0.05 ether);   // Raffle #3
        raffleThresholds.push(0.25 ether);   // Raffle #4
        raffleThresholds.push(0.5 ether);    // Raffle #5
        raffleThresholds.push(0.75 ether);   // Raffle #6
        raffleThresholds.push(1.0 ether);    // Raffle #7+ (repeats)
    }

    /**
     * @dev Initialize round and create matches
     * Called when tournament starts or when advancing to next round
     */
    function initializeRound(uint8 tierId, uint8 instanceId, uint8 roundNumber) public override {
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

        Round storage round = rounds[tierId][instanceId][roundNumber];
        round.totalMatches = matchCount;
        round.completedMatches = 0;
        round.initialized = true;
        round.drawCount = 0;
        round.playerCount = playerCount;

        if (roundNumber == 0) {
            address[] storage players = enrolledPlayers[tierId][instanceId];

            address walkoverPlayer = address(0);
            if (tournament.enrolledCount % 2 == 1) {
                uint256 randomness = uint256(keccak256(abi.encodePacked(
                    block.prevrandao,
                    block.timestamp,
                    tierId,
                    instanceId,
                    tournament.enrolledCount
                )));
                uint8 walkoverIndex = uint8(randomness % tournament.enrolledCount);
                walkoverPlayer = players[walkoverIndex];

                address lastPlayer = players[tournament.enrolledCount - 1];
                players[walkoverIndex] = lastPlayer;
                players[tournament.enrolledCount - 1] = walkoverPlayer;
            }

            // Create matches directly
            for (uint8 i = 0; i < matchCount; i++) {
                address player1 = players[i * 2];
                address player2 = players[i * 2 + 1];
                _createMatchGame(tierId, instanceId, roundNumber, i, player1, player2);
            }

            if (walkoverPlayer != address(0)) {
                // Delegate winner advancement to Matches module
                (bool success, ) = MODULE_MATCHES.delegatecall(
                    abi.encodeWithSignature("advanceWinner(uint8,uint8,uint8,uint8,address)", tierId, instanceId, roundNumber, matchCount, walkoverPlayer)
                );
                require(success, "AW");
            }
        }
    }

    /**
     * @dev Get match count for round - helper function
     */
    function getMatchCountForRound(uint8 tierId, uint8 instanceId, uint8 roundNumber) public view returns (uint8) {
        TournamentInstance storage tournament = tournaments[tierId][instanceId];

        if (roundNumber == 0) {
            return tournament.enrolledCount / 2;
        }

        Round storage prevRound = rounds[tierId][instanceId][roundNumber - 1];
        // Winners from matches + bye player if previous round had odd players
        uint8 winnersFromPrevRound = (prevRound.totalMatches - prevRound.drawCount) + (prevRound.playerCount % 2);

        return winnersFromPrevRound / 2;
    }

    // ============ Public ETour Function Wrappers (Delegatecall to Modules) ============

    // Note: enrollInTournament() and forceStartTournament() are now inherited from ETour_Base

    /**
     * @dev Execute protocol raffle - delegates to Raffle module
     */
    function executeProtocolRaffle() external nonReentrant {
        (bool success, ) = MODULE_RAFFLE.delegatecall(
            abi.encodeWithSignature("executeProtocolRaffle()")
        );
        require(success, "ER");
    }

    /**
     * @dev Reset enrollment window (single player extends timeout)
     */
    function resetEnrollmentWindow(uint8 tierId, uint8 instanceId) external nonReentrant {
        (bool success, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("resetEnrollmentWindow(uint8,uint8)", tierId, instanceId)
        );
        require(success, "RW");
    }

    /// @dev Check if enrollment window can be reset (single player after timeout)
    function canResetEnrollmentWindow(uint8 tierId, uint8 instanceId) external view returns (bool) {
        TierConfig storage c = _tierConfigs[tierId];
        if (!c.initialized || instanceId >= c.instanceCount) return false;
        TournamentInstance storage t = tournaments[tierId][instanceId];
        return t.status == TournamentStatus.Enrolling &&
               t.enrolledCount == 1 &&
               isEnrolled[tierId][instanceId][msg.sender] &&
               block.timestamp >= t.enrollmentTimeout.escalation1Start;
    }

    /**
     * @dev Claim abandoned enrollment pool - delegates to Core module
     */
    function claimAbandonedEnrollmentPool(uint8 tierId, uint8 instanceId) external nonReentrant {
        // Save enrolled players before delegatecall modifies state
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        (bool success, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("claimAbandonedEnrollmentPool(uint8,uint8)", tierId, instanceId)
        );
        require(success, "CAE");

        // Reset tournament after claiming abandoned pool (modules can't do nested delegatecalls)
        (bool resetSuccess, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("resetTournamentAfterCompletion(uint8,uint8,address[])", tierId, instanceId, enrolledPlayersCopy)
        );
        require(resetSuccess, "RT");
    }

    /**
     * @dev Escalation Level 2: Advanced players force eliminate both stalled players
     */
    function forceEliminateStalledMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external nonReentrant {
        // Save enrolled players before delegatecall (in case tournament completes and resets)
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        // Save original match players before delegatecall (for MatchRecord creation)
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];
        address originalPlayer1 = m.player1;
        address originalPlayer2 = m.player2;

        (bool success, bytes memory returnData) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature(
                "forceEliminateStalledMatch(uint8,uint8,uint8,uint8)",
                tierId, instanceId, roundNumber, matchNumber
            )
        );
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert("FE");
            }
        }

        // Create MatchRecords for both eliminated players
        _addMatchRecord(originalPlayer1, m, tierId, instanceId, roundNumber, matchNumber, CompletionReason.ForceElimination);
        _addMatchRecord(originalPlayer2, m, tierId, instanceId, roundNumber, matchNumber, CompletionReason.ForceElimination);

        // Check if round is complete before consolidating
        Round storage round = rounds[tierId][instanceId][roundNumber];
        if (round.completedMatches == round.totalMatches) {
            // Consolidate next round if ML2 left odd number of winners
            (bool success, ) = MODULE_MATCHES.delegatecall(
                abi.encodeWithSignature(
                    "consolidateAndStartOddRound(uint8,uint8,uint8)",
                    tierId, instanceId, roundNumber
                )
            );
            require(success, "CO");
        }

        // Check if tournament completed and handle prize distribution/reset
        // (can happen if this was a finals match or creates orphaned winner)
        _handleTournamentCompletion(tierId, instanceId, enrolledPlayersCopy);
    }

    /**
     * @dev Escalation Level 3: External player claims stalled match slot
     */
    function claimMatchSlotByReplacement(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external nonReentrant {
        // Save enrolled players before delegatecall (in case tournament completes and resets)
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        // Save original match players before delegatecall (for MatchRecord creation)
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];
        address originalPlayer1 = m.player1;
        address originalPlayer2 = m.player2;

        (bool success, bytes memory returnData) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature(
                "claimMatchSlotByReplacement(uint8,uint8,uint8,uint8)",
                tierId, instanceId, roundNumber, matchNumber
            )
        );
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert("CR");
            }
        }

        // Create MatchRecords for all 3 affected players
        _addMatchRecord(originalPlayer1, m, tierId, instanceId, roundNumber, matchNumber, CompletionReason.Replacement);
        _addMatchRecord(originalPlayer2, m, tierId, instanceId, roundNumber, matchNumber, CompletionReason.Replacement);
        _addMatchRecord(msg.sender, m, tierId, instanceId, roundNumber, matchNumber, CompletionReason.Replacement);

        // Check if round is complete before consolidating
        Round storage round = rounds[tierId][instanceId][roundNumber];
        if (round.completedMatches == round.totalMatches) {
            // Consolidate next round if ML3 left odd number of winners
            (bool s, ) = MODULE_MATCHES.delegatecall(
                abi.encodeWithSignature(
                    "consolidateAndStartOddRound(uint8,uint8,uint8)",
                    tierId, instanceId, roundNumber
                )
            );
            require(s, "CO");
        }

        // Check if tournament completed and handle prize distribution/reset
        // (can happen if this was a finals match)
        // Note: External player was added during delegatecall, so include them in cleanup
        address[] memory allPlayers = new address[](enrolledPlayersCopy.length + 1);
        for (uint256 i = 0; i < enrolledPlayersCopy.length; i++) {
            allPlayers[i] = enrolledPlayersCopy[i];
        }
        allPlayers[enrolledPlayersCopy.length] = msg.sender; // Add external player
        _handleTournamentCompletion(tierId, instanceId, allPlayers);
    }

    // ============ Board Helper Functions ============

    /**
     * @dev Get cell value from packed board
     * @param packedBoard The packed board state (2 bits per cell)
     * @param cellIndex Index 0-8
     * @return value 0=empty, 1=player1, 2=player2
     */
    function _getCell(uint256 packedBoard, uint8 cellIndex) private pure returns (uint8) {
        return uint8((packedBoard >> (cellIndex * 2)) & 3);
    }

    /**
     * @dev Set cell value in packed board
     * @param packedBoard Current packed board state
     * @param cellIndex Index 0-8
     * @param value 0=empty, 1=player1, 2=player2
     * @return Updated packed board
     */
    function _setCell(uint256 packedBoard, uint8 cellIndex, uint8 value) private pure returns (uint256) {
        uint256 mask = ~(uint256(3) << (cellIndex * 2));
        return (packedBoard & mask) | (uint256(value) << (cellIndex * 2));
    }

    /**
     * @dev Check if player has won
     * Checks all 8 winning lines: 3 rows, 3 columns, 2 diagonals
     */
    function _checkWin(uint256 board, uint8 player) private pure returns (bool) {
        // Rows
        if (_getCell(board, 0) == player && _getCell(board, 1) == player && _getCell(board, 2) == player) return true;
        if (_getCell(board, 3) == player && _getCell(board, 4) == player && _getCell(board, 5) == player) return true;
        if (_getCell(board, 6) == player && _getCell(board, 7) == player && _getCell(board, 8) == player) return true;

        // Columns
        if (_getCell(board, 0) == player && _getCell(board, 3) == player && _getCell(board, 6) == player) return true;
        if (_getCell(board, 1) == player && _getCell(board, 4) == player && _getCell(board, 7) == player) return true;
        if (_getCell(board, 2) == player && _getCell(board, 5) == player && _getCell(board, 8) == player) return true;

        // Diagonals
        if (_getCell(board, 0) == player && _getCell(board, 4) == player && _getCell(board, 8) == player) return true;
        if (_getCell(board, 2) == player && _getCell(board, 4) == player && _getCell(board, 6) == player) return true;

        return false;
    }

    /**
     * @dev Check if board is full (draw)
     */
    function _checkDraw(uint256 board) private pure returns (bool) {
        for (uint8 i = 0; i < 9; i++) {
            if (_getCell(board, i) == 0) return false;
        }
        return true;
    }

    // ============ Abstract Functions (ETour_Base Implementation) ============

    /**
     * @dev Create new match - called by initializeRound
     */
    function _createMatchGame(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address player1,
        address player2
    ) public override {
        require(player1 != player2, "P1");
        require(player1 != address(0) && player2 != address(0), "P2");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        matchData.player1 = player1;
        matchData.player2 = player2;
        matchData.status = MatchStatus.InProgress;
        matchData.lastMoveTime = block.timestamp;
        matchData.startTime = block.timestamp;
        matchData.isDraw = false;

        // Improved randomness using multiple entropy sources
        uint256 randomness = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            block.number,
            tierId,
            instanceId,
            roundNumber,
            matchNumber,
            player1,
            player2
        )));
        matchData.currentTurn = (randomness % 2 == 0) ? player1 : player2;
        matchData.firstPlayer = matchData.currentTurn;

        // Initialize time banks: 60 seconds base
        TierConfig storage config = _tierConfigs[tierId];
        matchData.player1TimeRemaining = config.timeouts.matchTimePerPlayer;
        matchData.player2TimeRemaining = config.timeouts.matchTimePerPlayer;

        // Clear board
        matchData.packedBoard = 0;

        // Initialize move history
        matchData.moves = "";
    }

    /**
     * @dev Check if match is active (exists and not completed)
     */
    // Note: _isMatchActive() uses default implementation from ETour_Base

    /**
     * @dev Mark match as complete in TicTacToe Match storage
     * Implements hook from ETour_Base
     */
    function _completeMatchGameSpecific(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        address winner,
        bool isDraw
    ) internal override {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        matchData.status = MatchStatus.Completed;
        // For draws, winner should always be address(0)
        matchData.winner = isDraw ? address(0) : winner;
        matchData.isDraw = isDraw;
    }

    /**
     * @dev Get time increment per move (Fischer increment)
     */
    function _getTimeIncrement() public view override returns (uint256) {
        return 15; // 15 seconds Fischer increment
    }

    // ============ Wrapper Functions (bytes32 matchId variants for module compatibility) ============

    /**
     * @dev Reset match - wrapper for modules expecting bytes32 matchId
     */
    function _resetMatchGame(bytes32 matchId) public override {
        Match storage matchData = matches[matchId];

        matchData.player1 = address(0);
        matchData.player2 = address(0);
        matchData.winner = address(0);
        matchData.currentTurn = address(0);
        matchData.firstPlayer = address(0);
        matchData.status = MatchStatus.NotStarted;
        matchData.isDraw = false;
        matchData.packedBoard = 0;
        matchData.startTime = 0;
        matchData.lastMoveTime = 0;
        matchData.player1TimeRemaining = 0;
        matchData.player2TimeRemaining = 0;
        matchData.moves = "";  // Clear move history
    }

    /**
     * @dev Get match result - wrapper for modules
     */
    function _getMatchResult(bytes32 matchId) public view override returns (address winner, bool isDraw, MatchStatus status) {
        Match storage matchData = matches[matchId];
        return (matchData.winner, matchData.isDraw, matchData.status);
    }

    // Note: _getMatchPlayers() and _setMatchPlayer() are now inherited from ETour_Base

    /**
     * @dev Initialize match for play - wrapper for modules
     */
    function _initializeMatchForPlay(bytes32 matchId, uint8 tierId) public override {
        Match storage matchData = matches[matchId];

        // Set match status and times
        matchData.status = MatchStatus.InProgress;
        matchData.startTime = block.timestamp;
        matchData.lastMoveTime = block.timestamp;
        matchData.packedBoard = 0;  // Clear board
        matchData.isDraw = false;
        matchData.winner = address(0);

        // Improved randomness using multiple entropy sources
        uint256 randomness = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            block.number,
            matchId,
            matchData.player1,
            matchData.player2
        )));
        matchData.currentTurn = (randomness % 2 == 0) ? matchData.player1 : matchData.player2;
        matchData.firstPlayer = matchData.currentTurn;

        // Reset time banks
        TierConfig storage config = _tierConfigs[tierId];
        matchData.player1TimeRemaining = config.timeouts.matchTimePerPlayer;
        matchData.player2TimeRemaining = config.timeouts.matchTimePerPlayer;
    }

    /**
     * @dev Complete match with result - wrapper for modules
     */
    function _completeMatchWithResult(bytes32 matchId, address winner, bool isDraw) public override {
        Match storage matchData = matches[matchId];

        matchData.status = MatchStatus.Completed;
        // For draws, winner should always be address(0)
        matchData.winner = isDraw ? address(0) : winner;
        matchData.isDraw = isDraw;

        // Note: Caching is handled by _completeMatchInternal which calls the other overload
        // This override is just for module interface compliance
    }

    /**
     * @dev Check if current player timed out - wrapper for modules
     */
    function _hasCurrentPlayerTimedOut(bytes32 matchId) public view override returns (bool) {
        Match storage matchData = matches[matchId];

        if (matchData.status != MatchStatus.InProgress) return false;

        uint256 elapsed = block.timestamp - matchData.lastMoveTime;
        uint256 currentPlayerTime = (matchData.currentTurn == matchData.player1)
            ? matchData.player1TimeRemaining
            : matchData.player2TimeRemaining;

        return elapsed >= currentPlayerTime;
    }

    // Note: _getActiveMatchData() is now inherited from ETour_Base

    // ============ Game Logic (Tic-Tac-Toe Specific) ============

    function makeMove(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        uint8 cellIndex
    ) external nonReentrant {
        require(cellIndex < 9, "IC");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        require(matchData.status == MatchStatus.InProgress, "MA");
        require(msg.sender == matchData.player1 || msg.sender == matchData.player2, "NP");
        require(msg.sender == matchData.currentTurn, "NT");
        require(_getCell(matchData.packedBoard, cellIndex) == 0, "CO");

        // Update time bank for current player
        uint256 elapsed = block.timestamp - matchData.lastMoveTime;
        if (matchData.currentTurn == matchData.player1) {
            matchData.player1TimeRemaining = (matchData.player1TimeRemaining > elapsed)
                ? matchData.player1TimeRemaining - elapsed
                : 0;
            matchData.player1TimeRemaining += _getTimeIncrement();
        } else {
            matchData.player2TimeRemaining = (matchData.player2TimeRemaining > elapsed)
                ? matchData.player2TimeRemaining - elapsed
                : 0;
            matchData.player2TimeRemaining += _getTimeIncrement();
        }
        matchData.lastMoveTime = block.timestamp;

        // Make move: Set cell to player's symbol (1 or 2)
        uint8 symbol = (msg.sender == matchData.player1) ? 1 : 2;
        matchData.packedBoard = _setCell(matchData.packedBoard, cellIndex, symbol);

        // Store move in history as compact bytes: each move is 1 byte (cellIndex)
        matchData.moves = string(abi.encodePacked(matchData.moves, cellIndex));

        // Clear any escalation state since a move was made (match is no longer stalled) - inlined
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        timeout.isStalled = false;
        timeout.escalation1Start = 0;
        timeout.escalation2Start = 0;
        timeout.activeEscalation = EscalationLevel.None;

        emit MoveMade(matchId, msg.sender, cellIndex);

        // Check for win
        if (_checkWin(matchData.packedBoard, symbol)) {
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, msg.sender, false, CompletionReason.NormalWin);
            return;
        }

        // Check for draw
        if (_checkDraw(matchData.packedBoard)) {
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
            return;
        }

        // Switch turn
        matchData.currentTurn = (matchData.currentTurn == matchData.player1)
            ? matchData.player2
            : matchData.player1;
    }

    // ============ View Functions ============

    function getMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) public view returns (TicTacToeMatchData memory) {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        // Check if match exists in active storage (even if completed)
        if (matchData.player1 != address(0)) {
            TicTacToeMatchData memory fullData;

            // Build CommonMatchData
            address loser = address(0);
            if (!matchData.isDraw && matchData.winner != address(0)) {
                loser = (matchData.winner == matchData.player1) ? matchData.player2 : matchData.player1;
            }

            fullData.common = CommonMatchData({
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

            // Add game-specific data
            fullData.packedBoard = matchData.packedBoard;
            fullData.currentTurn = matchData.currentTurn;
            fullData.firstPlayer = matchData.firstPlayer;
            fullData.player1TimeRemaining = matchData.player1TimeRemaining;
            fullData.player2TimeRemaining = matchData.player2TimeRemaining;
            fullData.lastMoveTimestamp = matchData.lastMoveTime;
            fullData.moves = matchData.moves;

            return fullData;
        }

        // Match not found in active storage - return empty data
        TicTacToeMatchData memory emptyData;
        return emptyData;
    }
}