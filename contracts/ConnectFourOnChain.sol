// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ETour_Base.sol";

// ConnectFourOnChain - ETour tournament protocol
contract ConnectFourOnChain is ETour_Base {

    error InvalidColumn();
    error MatchNotActive();
    error NotPlayer();
    error NotYourTurn();
    error ColumnFull();
    error OperationFailed();

    uint8 private constant ROWS = 6;
    uint8 private constant COLS = 7;
    uint8 private constant TOTAL_CELLS = 42;
    uint8 private constant CONNECT_COUNT = 4;

    struct ConnectFourMatchData {
        CommonMatchData common;        // Standardized tournament match data
        uint256 packedBoard;           // Game-specific: packed board state
        address currentTurn;           // Who plays next (address(0) for completed)
        address firstPlayer;           // Who started the match
        uint256 player1TimeRemaining;  // Time bank for player1
        uint256 player2TimeRemaining;  // Time bank for player2
        string moves;                  // Move history (column numbers for replay)
    }

    // ============ Game-Specific Storage ============

    // Note: matches mapping moved to ETour_Base for consistency across all games

    // ============ Events ============

    event MoveMade(bytes32 indexed matchId, address indexed player, uint8 column, uint8 row);

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
        _registerTiers();

        // Initialize progressive raffle thresholds
        // Last threshold (1 ether) repeats for all future raffles
        raffleThresholds.push(0.001 ether);  // Raffle #0
        raffleThresholds.push(0.01 ether);   // Raffle #1
        raffleThresholds.push(0.05 ether);   // Raffle #2
        raffleThresholds.push(0.4 ether);    // Raffle #3
        raffleThresholds.push(0.75 ether);   // Raffle #4
        raffleThresholds.push(1 ether);      // Raffle #5+ (repeats)

    }

    // ============ Initialization ============

    function _registerTiers() private {
        TimeoutConfig memory timeouts = TimeoutConfig({
            matchTimePerPlayer: 300,
            timeIncrementPerMove: 15,
            matchLevel2Delay: 120,
            matchLevel3Delay: 240,
            enrollmentWindow: 0, // set per tier below
            enrollmentLevel2Delay: 300
        });

        // Tier 0 (different timeout)
        timeouts.enrollmentWindow = 300;
        (bool s0, ) = MODULE_CORE.delegatecall(abi.encodeWithSignature("registerTier(uint8,uint8,uint8,uint256,(uint256,uint256,uint256,uint256,uint256,uint256))", 0, 2, 100, 0.001 ether, timeouts));
        require(s0, "RT");

        // Tiers 1 & 2 share timeout
        timeouts.enrollmentWindow = 600;
        (bool s1, ) = MODULE_CORE.delegatecall(abi.encodeWithSignature("registerTier(uint8,uint8,uint8,uint256,(uint256,uint256,uint256,uint256,uint256,uint256))", 1, 4, 50, 0.002 ether, timeouts));
        require(s1, "RT");
        timeouts.enrollmentWindow = 900;
        (bool s2, ) = MODULE_CORE.delegatecall(abi.encodeWithSignature("registerTier(uint8,uint8,uint8,uint256,(uint256,uint256,uint256,uint256,uint256,uint256))", 2, 8, 25, 0.004 ether, timeouts));
        require(s2, "RT");
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

            for (uint8 i = 0; i < matchCount; i++) {
                address player1 = players[i * 2];
                address player2 = players[i * 2 + 1];
                _createMatchGame(tierId, instanceId, roundNumber, i, player1, player2);
            }

            if (walkoverPlayer != address(0)) {
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

    /**
     * @dev Enroll in tournament - delegates to Core module
     */
    // Note: enrollInTournament() and forceStartTournament() are now inherited from ETour_Base


    function executeProtocolRaffle() external nonReentrant {
        (bool success, ) = MODULE_RAFFLE.delegatecall(
            abi.encodeWithSignature("executeProtocolRaffle()")
        );
        require(success, "ER");
    }

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

        (bool resetSuccess, ) = MODULE_CORE.delegatecall(
            abi.encodeWithSignature("resetTournamentAfterCompletion(uint8,uint8,address[])", tierId, instanceId, enrolledPlayersCopy)
        );
        require(resetSuccess, "RT");
    }


    function forceEliminateStalledMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external nonReentrant {
        // Save enrolled players before delegatecall modifies state
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        // Save original match players before delegatecall (for MatchRecord creation)
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];
        address originalPlayer1 = m.player1;
        address originalPlayer2 = m.player2;

        (bool success, ) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature(
                "forceEliminateStalledMatch(uint8,uint8,uint8,uint8)",
                tierId, instanceId, roundNumber, matchNumber
            )
        );
        require(success, "FE");

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
            require(success, "CS");
        }

        // Check if tournament completed and handle prize distribution/reset
        _handleTournamentCompletion(tierId, instanceId, enrolledPlayersCopy);
    }


    function claimMatchSlotByReplacement(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) external nonReentrant {
        // Save enrolled players before delegatecall modifies state
        address[] memory enrolledPlayersCopy = new address[](enrolledPlayers[tierId][instanceId].length);
        for (uint256 i = 0; i < enrolledPlayers[tierId][instanceId].length; i++) {
            enrolledPlayersCopy[i] = enrolledPlayers[tierId][instanceId][i];
        }

        // Save original match players before delegatecall (for MatchRecord creation)
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];
        address originalPlayer1 = m.player1;
        address originalPlayer2 = m.player2;

        (bool success, ) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature(
                "claimMatchSlotByReplacement(uint8,uint8,uint8,uint8)",
                tierId, instanceId, roundNumber, matchNumber
            )
        );
        require(success, "CR");

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
            require(s, "CS");
        }

        // Add external player to cleanup list for tournament completion
        address[] memory allPlayers = new address[](enrolledPlayersCopy.length + 1);
        for (uint256 i = 0; i < enrolledPlayersCopy.length; i++) {
            allPlayers[i] = enrolledPlayersCopy[i];
        }
        allPlayers[enrolledPlayersCopy.length] = msg.sender; // Add external player

        // Check if tournament completed and handle prize distribution/reset
        _handleTournamentCompletion(tierId, instanceId, allPlayers);
    }
    // Note: isMatchEscL2Available(), isMatchEscL3Available(), isPlayerInAdvancedRound(),
    //       claimTimeoutWin() are all inherited from ETour_Base

    // Note: _handleTournamentCompletion() is now inherited from ETour_Base

    // Note: _completeMatchInternal() is now inherited from ETour_Base

    // ============ Board Helper Functions ============

    /**
     * @dev Get cell value from packed board
     * @param packedBoard The packed board state (2 bits per cell)
     * @param cellIndex Index 0-41
     * @return value 0=empty, 1=Red, 2=Yellow
     */
    function _getCell(uint256 packedBoard, uint8 cellIndex) private pure returns (uint8) {
        return uint8((packedBoard >> (cellIndex * 2)) & 3);
    }

    /**
     * @dev Set cell value in packed board
     * @param packedBoard Current packed board state
     * @param cellIndex Index 0-41
     * @param value 0=empty, 1=Red, 2=Yellow
     * @return Updated packed board
     */
    function _setCell(uint256 packedBoard, uint8 cellIndex, uint8 value) private pure returns (uint256) {
        uint256 mask = ~(uint256(3) << (cellIndex * 2));
        return (packedBoard & mask) | (uint256(value) << (cellIndex * 2));
    }

    /**
     * @dev Convert 2D board coordinates to 1D cell index
     * Board uses row-major ordering: cellIndex = row * 7 + col
     */
    function _getCellIndex(uint8 row, uint8 col) private pure returns (uint8) {
        return row * COLS + col;
    }

    /**
     * @dev Check if coordinates are within board bounds
     */
    function _isValidPosition(int8 row, int8 col) private pure returns (bool) {
        return row >= 0 && row < int8(ROWS) && col >= 0 && col < int8(COLS);
    }

    /**
     * @dev Check if board is completely full (all 42 cells occupied)
     * Used for draw detection
     */
    function _isBoardFull(uint256 packedBoard) private pure returns (bool) {
        for (uint8 i = 0; i < TOTAL_CELLS; i++) {
            if (_getCell(packedBoard, i) == 0) return false;
        }
        return true;
    }

    /**
     * @dev Count total moves made (non-empty cells)
     * Calculated on-the-fly by scanning board
     */
    function _countMoves(uint256 packedBoard) private pure returns (uint8) {
        uint8 count = 0;
        for (uint8 i = 0; i < TOTAL_CELLS; i++) {
            if (_getCell(packedBoard, i) != 0) count++;
        }
        return count;
    }

    /**
     * @dev Check if player has won with their last move
     * Checks all 4 directions: horizontal, vertical, diagonal, anti-diagonal
     */
    function _checkWin(
        uint256 packedBoard,
        uint8 piece,
        uint8 row,
        uint8 col
    ) private pure returns (bool) {
        // Horizontal
        if (_checkLine(packedBoard, piece, row, col, 0, 1)) return true;

        // Vertical
        if (_checkLine(packedBoard, piece, row, col, 1, 0)) return true;

        // Diagonal (down-right)
        if (_checkLine(packedBoard, piece, row, col, 1, 1)) return true;

        // Anti-diagonal (down-left)
        if (_checkLine(packedBoard, piece, row, col, 1, -1)) return true;

        return false;
    }

    /**
     * @dev Check for 4-in-a-row in a specific direction (bidirectional)
     * Counts pieces in both directions from the last played position
     */
    function _checkLine(
        uint256 packedBoard,
        uint8 piece,
        uint8 row,
        uint8 col,
        int8 dRow,
        int8 dCol
    ) private pure returns (bool) {
        uint8 count = 1;

        int8 r = int8(row) + dRow;
        int8 c = int8(col) + dCol;
        while (_isValidPosition(r, c) && _getCell(packedBoard, _getCellIndex(uint8(r), uint8(c))) == piece) {
            count++;
            if (count >= CONNECT_COUNT) return true;
            r += dRow;
            c += dCol;
        }

        r = int8(row) - dRow;
        c = int8(col) - dCol;
        while (_isValidPosition(r, c) && _getCell(packedBoard, _getCellIndex(uint8(r), uint8(c))) == piece) {
            count++;
            if (count >= CONNECT_COUNT) return true;
            r -= dRow;
            c -= dCol;
        }

        return false;
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

        TierConfig storage config = _tierConfigs[tierId];
        matchData.player1TimeRemaining = config.timeouts.matchTimePerPlayer;
        matchData.player2TimeRemaining = config.timeouts.matchTimePerPlayer;

        matchData.packedBoard = 0;

        // Initialize move history
        matchData.moves = "";
    }


    // Note: _isMatchActive() uses default implementation from ETour_Base

    /**
     * @dev Mark match as complete in ConnectFour Match storage
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

    function _getTimeIncrement() public pure override returns (uint256) {
        return 15;
    }

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

    
    function _getMatchResult(bytes32 matchId) public view override returns (address winner, bool isDraw, MatchStatus status) {
        Match storage matchData = matches[matchId];
        return (matchData.winner, matchData.isDraw, matchData.status);
    }

    // Note: _getMatchPlayers() and _setMatchPlayer() are now inherited from ETour_Base

    function _initializeMatchForPlay(bytes32 matchId, uint8 tierId) public override {
        Match storage matchData = matches[matchId];

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

        TierConfig storage config = _tierConfigs[tierId];
        matchData.player1TimeRemaining = config.timeouts.matchTimePerPlayer;
        matchData.player2TimeRemaining = config.timeouts.matchTimePerPlayer;
    }

    
    function _completeMatchWithResult(bytes32 matchId, address winner, bool isDraw) public override {
        Match storage matchData = matches[matchId];

        matchData.status = MatchStatus.Completed;
        // For draws, winner should always be address(0)
        matchData.winner = isDraw ? address(0) : winner;
        matchData.isDraw = isDraw;
    }

    
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

    // ============ Game Logic (Connect Four Specific) ============

    /**
     * @dev Make a move on the Connect Four board
     * Handles gravity (piece drops to lowest available row), time bank updates with Fischer increment
     */
    function makeMove(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber,
        uint8 column
    ) external nonReentrant {
        if (column >= COLS) revert InvalidColumn();

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        if (matchData.status != MatchStatus.InProgress) revert MatchNotActive();
        if (msg.sender != matchData.player1 && msg.sender != matchData.player2) revert NotPlayer();
        if (msg.sender != matchData.currentTurn) revert NotYourTurn();

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

        uint8 targetRow = ROWS;
        for (uint8 row = ROWS; row > 0; row--) {
            uint8 checkCell = _getCellIndex(row - 1, column);
            if (_getCell(matchData.packedBoard, checkCell) == 0) {
                targetRow = row - 1;
                break;
            }
        }

        if (targetRow >= ROWS) revert ColumnFull();

        uint8 piece = (msg.sender == matchData.player1) ? 1 : 2;

        uint8 cellIndex = _getCellIndex(targetRow, column);
        matchData.packedBoard = _setCell(matchData.packedBoard, cellIndex, piece);

        // Store move in history as compact bytes: each move is 1 byte (column)
        matchData.moves = string(abi.encodePacked(matchData.moves, column));

        // Clear any escalation state since a move was made (match is no longer stalled)
        (bool clearSuccess, ) = MODULE_ESCALATION.delegatecall(
            abi.encodeWithSignature("clearEscalationState(bytes32)", matchId)
        );
        require(clearSuccess, "CE");

        emit MoveMade(matchId, msg.sender, column, targetRow);

        // Check for win
        if (_checkWin(matchData.packedBoard, piece, targetRow, column)) {
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, msg.sender, false, CompletionReason.NormalWin);
            return;
        }

        // Check for draw (board full)
        if (_isBoardFull(matchData.packedBoard)) {
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
            return;
        }

        // Switch turn
        matchData.currentTurn = (matchData.currentTurn == matchData.player1)
            ? matchData.player2
            : matchData.player1;
    }

    // ============ View Functions ============

    /**
     * @dev Get complete match data
     */
    function getMatch(
        uint8 tierId,
        uint8 instanceId,
        uint8 roundNumber,
        uint8 matchNumber
    ) public view returns (ConnectFourMatchData memory) {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

        if (matchData.player1 != address(0)) {
            ConnectFourMatchData memory fullData;

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
            fullData.moves = matchData.moves;

            return fullData;
        }

        // Match not found - return empty data
        ConnectFourMatchData memory emptyData;
        return emptyData;
    }

    // Note: getPlayerStats(), getTournamentInfo(), getRoundInfo(), getLeaderboard(), getRaffleInfo()
    //       are all inherited from ETour_Base

    // Note: Player tracking hooks removed - all tracking now done client-side

    // Note: Player tracking functions (_addPlayerEnrollingTournament, _removePlayerEnrollingTournament,
    //       _addPlayerActiveTournament, _removePlayerActiveTournament) are now inherited from ETour_Base
}
