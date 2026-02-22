// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ETour_Base.sol";

interface IChessRules {
    function processMove(uint256 board, uint256 state, uint8 from, uint8 to, uint8 promotion, bool isWhite) external pure returns (bool valid, uint256 newBoard, uint256 newState, uint8 gameEnd);
}

contract ChessOnChain is ETour_Base {

    IChessRules public immutable CHESS_RULES;

    uint256 private constant INITIAL_BOARD = 0xA89CB98A77777777000000000000000000000000000000001111111142365324;
    uint256 private constant INITIAL_STATE = 63 | (1 << 22);  // 63 = NO_EN_PASSANT, bit 22 = fullMoveNumber=1

    // ============ Game-Specific Structs ============

    // Note: Match struct moved to ETour_Base for consistency across all games

    struct ChessMatchData {
        CommonMatchData common;
        uint256 packedBoard;
        uint256 packedState;
        address currentTurn;
        address firstPlayer;
        uint256 player1TimeRemaining;
        uint256 player2TimeRemaining;
        string moves;                  // Move history (algebraic notation for replay)
    }
    // Note: LeaderboardEntry struct now inherited from ETour_Base

    // ============ Game-Specific Storage ============

    // Note: matches mapping moved to ETour_Base for consistency across all games

    // Threefold repetition tracking: matchId -> positionHash -> occurrenceCount
    // Position hash incorporates gameNonce to invalidate counts on match reset
    mapping(bytes32 => mapping(bytes32 => uint8)) private _positionCounts;
    mapping(bytes32 => uint256) private _gameNonce;

    // Elite tournament match history (Tier 3 and Tier 7 finals)
    Match[] public eliteMatches;

    // ============ Events ============

    event MoveMade(bytes32 indexed matchId, address indexed player, uint8 from, uint8 to);

    // ============ Constructor ============

    constructor(
        address _moduleCoreAddress,
        address _moduleMatchesAddress,
        address _modulePrizesAddress,
        address _moduleRaffleAddress,
        address _moduleEscalationAddress,
        address _moduleChessRulesAddress
    ) ETour_Base(
        _moduleCoreAddress,
        _moduleMatchesAddress,
        _modulePrizesAddress,
        _moduleRaffleAddress,
        _moduleEscalationAddress
    ) {
        CHESS_RULES = IChessRules(_moduleChessRulesAddress);

        TimeoutConfig memory timeouts = TimeoutConfig({
            matchTimePerPlayer: 600,
            timeIncrementPerMove: 15,
            matchLevel2Delay: 180,
            matchLevel3Delay: 360,
            enrollmentWindow: 0,  // Set per tier in loop
            enrollmentLevel2Delay: 300
        });

        for (uint8 i = 0; i < 8; i++) {
            timeouts.enrollmentWindow = i < 4 ? 600 : 1800;
            timeouts.matchTimePerPlayer = i == 3 || i == 7 ? 1200 : 600;
            timeouts.timeIncrementPerMove = i == 3 || i == 7 ? 30 : 15;

            (bool success, ) = MODULE_CORE.delegatecall(
                abi.encodeWithSignature("registerTier(uint8,uint8,uint8,uint256,(uint256,uint256,uint256,uint256,uint256,uint256))",
                    i,                           // tierId
                    i < 4 ? 2 : 4,               // playerCount
                    i < 4 ? 100 : 50,            // instanceCount
                    (
                        i == 0 ? 0.003 ether :
                        i == 1 ? 0.008 ether :
                        i == 2 ? 0.015 ether :
                        i == 3 ? 0.1 ether :
                        i == 4 ? 0.004 ether :
                        i == 5 ? 0.009 ether :
                        i == 6 ? 0.02 ether :
                                 0.15 ether
                    ),                          // entryFee
                    timeouts
                )
            );
            require(success, "RT");
        }
        // Initialize progressive raffle thresholds
        // Last threshold repeats for all future raffles
        raffleThresholds.push(0.005 ether);  // Raffle #0
        raffleThresholds.push(0.02 ether);   // Raffle #1
        raffleThresholds.push(0.05 ether);   // Raffle #2+ (repeats)
    }

    // ============ Initialization ============

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
                    block.prevrandao, block.timestamp, tierId, instanceId, tournament.enrolledCount
                )));
                uint8 walkoverIndex = uint8(randomness % tournament.enrolledCount);
                walkoverPlayer = players[walkoverIndex];

                address lastPlayer = players[tournament.enrolledCount - 1];
                players[walkoverIndex] = lastPlayer;
                players[tournament.enrolledCount - 1] = walkoverPlayer;
            }

            for (uint8 i = 0; i < matchCount; i++) {
                address p1 = players[i * 2];
                address p2 = players[i * 2 + 1];
                _createMatchGame(tierId, instanceId, roundNumber, i, p1, p2);
            }

            if (walkoverPlayer != address(0)) {
                (bool success, ) = MODULE_MATCHES.delegatecall(
                    abi.encodeWithSignature("advanceWinner(uint8,uint8,uint8,uint8,address)", tierId, instanceId, roundNumber, matchCount, walkoverPlayer)
                );
                require(success, "AW");
            }
        }
    }

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

    // ============ Inline Helpers ============

    function _getPiece(uint256 board, uint8 square) private pure returns (uint8) {
        return uint8((board >> (square * 4)) & 0xF);
    }

    function _isWhitePiece(uint8 piece) private pure returns (bool) {
        return piece >= 1 && piece <= 6;
    }

    function _isBlackPiece(uint8 piece) private pure returns (bool) {
        return piece >= 7 && piece <= 12;
    }

    /// @dev Compute position hash for threefold repetition detection
    /// Includes: board state, castling rights, en passant square, side to move, and game nonce
    function _computePositionHash(uint256 board, uint256 state, bool isWhiteTurn, uint256 nonce) private pure returns (bytes32) {
        // Extract position-relevant state: bits 0-11 (en passant + castling flags)
        uint256 positionState = state & 0xFFF;
        return keccak256(abi.encodePacked(board, positionState, isWhiteTurn, nonce));
    }

    // ============ Public ETour Function Wrappers ============

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

    function forceEliminateStalledMatch(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber) external nonReentrant {
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
            abi.encodeWithSignature("forceEliminateStalledMatch(uint8,uint8,uint8,uint8)", tierId, instanceId, roundNumber, matchNumber)
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
            require(success, "CO");
        }

        // Check if tournament completed and handle prize distribution/reset
        _handleTournamentCompletion(tierId, instanceId, enrolledPlayersCopy);
    }

    function claimMatchSlotByReplacement(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber) external nonReentrant {
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
            abi.encodeWithSignature("claimMatchSlotByReplacement(uint8,uint8,uint8,uint8)", tierId, instanceId, roundNumber, matchNumber)
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
            require(s, "CO");
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

    // ============ Chess Gameplay ============

    function makeMove(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber, uint8 from, uint8 to, uint8 promotion) external nonReentrant {
        require(from < 64 && to < 64 && from != to, "IS");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];

        require(m.status == MatchStatus.InProgress, "MA");
        require(msg.sender == m.player1 || msg.sender == m.player2, "NP");
        require(msg.sender == m.currentTurn, "NT");

        bool isWhite = (msg.sender == m.player1);
        uint8 piece = _getPiece(m.packedBoard, from);
        require(isWhite ? _isWhitePiece(piece) : _isBlackPiece(piece), "NYP");

        // Single call to module for validation, execution, and game-end detection
        (bool valid, uint256 newBoard, uint256 newState, uint8 gameEnd) = CHESS_RULES.processMove(m.packedBoard, m.packedState, from, to, promotion, isWhite);
        require(valid, "IM");

        // Update time bank
        uint256 elapsed = block.timestamp - m.lastMoveTime;
        if (isWhite) {
            m.player1TimeRemaining = m.player1TimeRemaining > elapsed ? m.player1TimeRemaining - elapsed + 15 : 15;
        } else {
            m.player2TimeRemaining = m.player2TimeRemaining > elapsed ? m.player2TimeRemaining - elapsed + 15 : 15;
        }
        m.lastMoveTime = block.timestamp;
        m.packedBoard = newBoard;
        m.packedState = newState;

        // Store move in history as compact bytes: each move is 2 bytes (from, to)
        m.moves = string(abi.encodePacked(m.moves, from, to));

        // Track position for threefold repetition (position after move, opponent's turn)
        bytes32 positionHash = _computePositionHash(newBoard, newState, !isWhite, _gameNonce[matchId]);
        uint8 positionCount = ++_positionCounts[matchId][positionHash];

        // Clear any escalation state since a move was made (match is no longer stalled) - inlined
        MatchTimeoutState storage timeout = matchTimeouts[matchId];
        timeout.isStalled = false;
        timeout.escalation1Start = 0;
        timeout.escalation2Start = 0;
        timeout.activeEscalation = EscalationLevel.None;

        emit MoveMade(matchId, msg.sender, from, to);

        if (gameEnd == 1) { // checkmate
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, msg.sender, false, CompletionReason.NormalWin);
        } else if (gameEnd == 2) { // stalemate
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
        } else if (gameEnd == 3) { // fifty-move rule
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
        } else if (gameEnd == 4) { // insufficient material
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
        } else if (positionCount >= 3) { // threefold repetition
            _completeMatchInternal(tierId, instanceId, roundNumber, matchNumber, address(0), true, CompletionReason.Draw);
        } else {
            m.currentTurn = isWhite ? m.player2 : m.player1;
        }
    }

    // ============ Abstract Functions (ETour_Base Implementation) ============

    function _createMatchGame(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber, address player1, address player2) public override {
        require(player1 != player2 && player1 != address(0) && player2 != address(0), "IP");

        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];

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

        if (randomness % 2 == 0) {
            matchData.player1 = player1;
            matchData.player2 = player2;
        } else {
            matchData.player1 = player2;
            matchData.player2 = player1;
        }

        matchData.currentTurn = matchData.player1;
        matchData.firstPlayer = matchData.player1;
        matchData.status = MatchStatus.InProgress;
        matchData.startTime = block.timestamp;
        matchData.lastMoveTime = block.timestamp;
        matchData.isDraw = false;
        matchData.packedBoard = INITIAL_BOARD;
        matchData.packedState = INITIAL_STATE;
        matchData.moves = "";

        matchData.player1TimeRemaining = _tierConfigs[tierId].timeouts.matchTimePerPlayer;
        matchData.player2TimeRemaining = _tierConfigs[tierId].timeouts.matchTimePerPlayer;

        // Record initial position for threefold repetition tracking (white to move)
        bytes32 initialPositionHash = _computePositionHash(INITIAL_BOARD, INITIAL_STATE, true, _gameNonce[matchId]);
        _positionCounts[matchId][initialPositionHash] = 1;
    }

    // Note: _isMatchActive() uses default implementation from ETour_Base

    /**
     * @dev Mark match as complete in Chess Match storage
     * Implements hook from ETour_Base
     */
    function _completeMatchGameSpecific(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber, address winner, bool isDraw) internal override {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage matchData = matches[matchId];
        matchData.status = MatchStatus.Completed;
        // For draws, winner should always be address(0)
        matchData.winner = isDraw ? address(0) : winner;
        matchData.isDraw = isDraw;
    }

    function _getTimeIncrement() public pure override returns (uint256) { return 15; }

    function _resetMatchGame(bytes32 matchId) public override {
        Match storage m = matches[matchId];
        m.player1 = address(0); m.player2 = address(0); m.winner = address(0);
        m.currentTurn = address(0); m.firstPlayer = address(0);
        m.status = MatchStatus.NotStarted; m.isDraw = false;
        m.packedBoard = 0; m.packedState = 0;
        m.startTime = 0; m.lastMoveTime = 0;
        m.player1TimeRemaining = 0; m.player2TimeRemaining = 0;
        m.moves = "";  // Clear move history
        // Increment nonce to invalidate any stale position counts
        ++_gameNonce[matchId];
    }

    function _getMatchResult(bytes32 matchId) public view override returns (address, bool, MatchStatus) {
        Match storage m = matches[matchId];
        return (m.winner, m.isDraw, m.status);
    }

    function _initializeMatchForPlay(bytes32 matchId, uint8 tierId) public override {
        Match storage m = matches[matchId];
        m.status = MatchStatus.InProgress;
        m.startTime = block.timestamp;
        m.lastMoveTime = block.timestamp;
        m.packedBoard = INITIAL_BOARD;
        m.packedState = INITIAL_STATE;
        m.isDraw = false;
        m.winner = address(0);

        // Improved randomness using multiple entropy sources
        uint256 randomness = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            block.number,
            matchId,
            m.player1,
            m.player2
        )));

        if (randomness % 2 == 1) {
            (m.player1, m.player2) = (m.player2, m.player1);
        }
        m.currentTurn = m.player1;
        m.firstPlayer = m.player1;

        m.player1TimeRemaining = _tierConfigs[tierId].timeouts.matchTimePerPlayer;
        m.player2TimeRemaining = _tierConfigs[tierId].timeouts.matchTimePerPlayer;

        // Increment game nonce to invalidate previous position counts, then record initial position
        uint256 nonce = ++_gameNonce[matchId];
        bytes32 initialPositionHash = _computePositionHash(INITIAL_BOARD, INITIAL_STATE, true, nonce);
        _positionCounts[matchId][initialPositionHash] = 1;
    }

    function _completeMatchWithResult(bytes32 matchId, address winner, bool isDraw) public override {
        Match storage m = matches[matchId];
        m.status = MatchStatus.Completed;
        // For draws, winner should always be address(0)
        m.winner = isDraw ? address(0) : winner;
        m.isDraw = isDraw;
    }

    function _hasCurrentPlayerTimedOut(bytes32 matchId) public view override returns (bool) {
        Match storage m = matches[matchId];
        if (m.status != MatchStatus.InProgress) return false;
        uint256 elapsed = block.timestamp - m.lastMoveTime;
        uint256 time = (m.currentTurn == m.player1) ? m.player1TimeRemaining : m.player2TimeRemaining;
        return elapsed >= time;
    }

    // Note: _getActiveMatchData() is now inherited from ETour_Base

    // ============ View Functions ============

    function getMatch(uint8 tierId, uint8 instanceId, uint8 roundNumber, uint8 matchNumber) public view returns (ChessMatchData memory) {
        bytes32 matchId = _getMatchId(tierId, instanceId, roundNumber, matchNumber);
        Match storage m = matches[matchId];

        if (m.player1 != address(0)) {
            address loser = (!m.isDraw && m.winner != address(0)) ? (m.winner == m.player1 ? m.player2 : m.player1) : address(0);
            return ChessMatchData(
                CommonMatchData(m.player1, m.player2, m.winner, loser, m.status, m.isDraw, m.startTime, m.lastMoveTime, tierId, instanceId, roundNumber, matchNumber, false),
                m.packedBoard, m.packedState, m.currentTurn, m.firstPlayer, m.player1TimeRemaining, m.player2TimeRemaining, m.moves
            );
        }

        // Match not found - return empty data
        ChessMatchData memory emptyData;
        return emptyData;
    }

    /**
     * @dev Hook called BEFORE tournament reset to archive elite matches
     * Override from ETour_Base for ChessOnChain-specific archival logic
     */
    function _onTournamentCompletedBeforeReset(uint8 tierId, uint8 instanceId) internal override {
        // Archive elite tournament finals (Tier 3 or Tier 7)
        if (tierId == 3 || tierId == 7) {
            TournamentInstance storage tournament = tournaments[tierId][instanceId];
            bytes32 finalsMatchId = _getMatchId(tierId, instanceId, tournament.currentRound, 0);
            eliteMatches.push(matches[finalsMatchId]);
        }
    }

    // Note: Player tracking functions (_addPlayerEnrollingTournament, _removePlayerEnrollingTournament,
    //       _addPlayerActiveTournament, _removePlayerActiveTournament) are now inherited from ETour_Base
}
