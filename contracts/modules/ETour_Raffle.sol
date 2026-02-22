// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ETour_Base.sol";

/**
 * @title ETour_Raffle
 * @dev Stateless module for protocol raffle execution
 *
 * This module handles:
 * - Raffle threshold and reserve calculations
 * - Player eligibility checking for raffle participation
 * - Weighted random winner selection based on enrollment counts
 * - Raffle execution with owner/winner distribution (5%/90%)
 * - Raffle state information for UI display
 *
 * CRITICAL - DELEGATECALL SEMANTICS:
 * When game contract calls this module via delegatecall:
 * - This code executes AS IF it's part of the game contract
 * - Can directly access storage variables (accumulatedProtocolShare, tournaments, etc.)
 * - address(this) = game contract address
 * - msg.sender = original caller
 * - msg.value = value sent
 *
 * STATELESS: This contract declares NO storage variables of its own.
 * All storage access is to the game contract's storage via delegatecall context.
 */
contract ETour_Raffle is ETour_Base {

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

    // ============ Raffle Configuration Functions ============
    // Note: All raffle threshold/reserve getters removed
    // Logic inlined directly in executeProtocolRaffle()

    // ============ Player Eligibility Functions ============

    /**
     * @dev Checks if caller is enrolled in any active tournament
     * EXACT COPY from ETour.sol lines 2732-2755
     */
    function isCallerEnrolledInActiveTournament(address caller) external view returns (bool) {
        for (uint8 tierId = 0; tierId < tierCount; tierId++) {
            TierConfig storage config = _tierConfigs[tierId];

            for (uint8 instanceId = 0; instanceId < config.instanceCount; instanceId++) {
                TournamentInstance storage tournament = tournaments[tierId][instanceId];

                // Only check Enrolling and InProgress tournaments
                if (tournament.status == TournamentStatus.Enrolling ||
                    tournament.status == TournamentStatus.InProgress) {

                    if (isEnrolled[tierId][instanceId][caller]) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * @dev Internal helper to check if caller is enrolled in active tournament
     * EXACT COPY from ETour.sol lines 2732-2755
     */
    function _isCallerEnrolledInActiveTournament(address caller) internal view returns (bool) {
        for (uint8 tierId = 0; tierId < tierCount; tierId++) {
            TierConfig storage config = _tierConfigs[tierId];

            for (uint8 instanceId = 0; instanceId < config.instanceCount; instanceId++) {
                TournamentInstance storage tournament = tournaments[tierId][instanceId];

                // Only check Enrolling and InProgress tournaments
                if (tournament.status == TournamentStatus.Enrolling ||
                    tournament.status == TournamentStatus.InProgress) {

                    if (isEnrolled[tierId][instanceId][caller]) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * @dev Gets all enrolled players across active tournaments with enrollment counts
     * EXACT COPY from ETour.sol lines 2763-2840
     */
    function getAllEnrolledPlayersWithWeights()
        external
        view
        returns (
            address[] memory players,
            uint16[] memory weights,
            uint256 totalWeight
        )
    {
        // Use dynamic approach with temporary arrays (max 1000 unique players)
        address[] memory tempPlayers = new address[](1000);
        uint256 uniqueCount = 0;
        totalWeight = 0;

        // First pass: collect unique players and count total enrollments
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

                        // Check if player already in tempPlayers
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

                        totalWeight++;
                    }
                }
            }
        }

        // Allocate exact-size arrays
        players = new address[](uniqueCount);
        weights = new uint16[](uniqueCount);

        // Second pass: count weights for each unique player
        for (uint256 i = 0; i < uniqueCount; i++) {
            players[i] = tempPlayers[i];
            uint16 playerWeight = 0;

            for (uint8 tierId = 0; tierId < tierCount; tierId++) {
                TierConfig storage config = _tierConfigs[tierId];

                for (uint8 instanceId = 0; instanceId < config.instanceCount; instanceId++) {
                    TournamentInstance storage tournament = tournaments[tierId][instanceId];

                    if ((tournament.status == TournamentStatus.Enrolling ||
                         tournament.status == TournamentStatus.InProgress) &&
                        isEnrolled[tierId][instanceId][players[i]]) {
                        playerWeight++;
                    }
                }
            }

            weights[i] = playerWeight;
        }

        return (players, weights, totalWeight);
    }

    /**
     * @dev Get count of unique eligible players for raffle
     * Returns the number of unique players enrolled in active tournaments
     */
    function getEligiblePlayerCount() external view returns (uint256) {
        (address[] memory players, , ) = _getAllEnrolledPlayersWithWeights();
        return players.length;
    }

    /**
     * @dev Internal helper to get all enrolled players with weights
     * EXACT COPY from ETour.sol lines 2763-2840
     */
    function _getAllEnrolledPlayersWithWeights()
        internal
        view
        returns (
            address[] memory players,
            uint16[] memory weights,
            uint256 totalWeight
        )
    {
        // Use dynamic approach with temporary arrays (max 1000 unique players)
        address[] memory tempPlayers = new address[](1000);
        uint256 uniqueCount = 0;
        totalWeight = 0;

        // First pass: collect unique players and count total enrollments
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

                        // Check if player already in tempPlayers
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

                        totalWeight++;
                    }
                }
            }
        }

        // Allocate exact-size arrays
        players = new address[](uniqueCount);
        weights = new uint16[](uniqueCount);

        // Second pass: count weights for each unique player
        for (uint256 i = 0; i < uniqueCount; i++) {
            players[i] = tempPlayers[i];
            uint16 playerWeight = 0;

            for (uint8 tierId = 0; tierId < tierCount; tierId++) {
                TierConfig storage config = _tierConfigs[tierId];

                for (uint8 instanceId = 0; instanceId < config.instanceCount; instanceId++) {
                    TournamentInstance storage tournament = tournaments[tierId][instanceId];

                    if ((tournament.status == TournamentStatus.Enrolling ||
                         tournament.status == TournamentStatus.InProgress) &&
                        isEnrolled[tierId][instanceId][players[i]]) {
                        playerWeight++;
                    }
                }
            }

            weights[i] = playerWeight;
        }

        return (players, weights, totalWeight);
    }

    // REMOVED: selectWeightedWinner() external - Duplicate of internal version, never used
    // Only internal _selectWeightedWinner() is needed

    /**
     * @dev Internal helper for weighted winner selection
     * EXACT COPY from ETour.sol lines 2850-2875
     */
    function _selectWeightedWinner(
        address[] memory players,
        uint16[] memory weights,
        uint256 totalWeight,
        uint256 randomness
    ) internal pure returns (address winner) {
        require(players.length > 0, "No players available");
        require(players.length == weights.length, "Array length mismatch");

        // Generate random position in [0, totalWeight)
        uint256 randomPosition = randomness % totalWeight;

        // Find winner using cumulative probability
        uint256 cumulativeWeight = 0;

        for (uint256 i = 0; i < players.length; i++) {
            cumulativeWeight += weights[i];

            if (randomPosition < cumulativeWeight) {
                return players[i];
            }
        }

        // Fallback (should never reach here)
        return players[players.length - 1];
    }

    // ============ Raffle Execution ============

    /**
     * @dev Executes protocol raffle when accumulated fees exceed threshold
     * Only requires that the caller is enrolled in any active tournament
     */
    function executeProtocolRaffle()
        external
        returns (
            address winner,
            uint256 ownerAmount,
            uint256 winnerAmount
        )
    {
        // EFFECT 1: Get next raffle index from array length
        uint256 nextRaffleIndex = raffleResults.length;

        // EFFECT 2: Get threshold for next raffle
        uint256 threshold = (nextRaffleIndex < raffleThresholds.length)
            ? raffleThresholds[nextRaffleIndex]
            : raffleThresholds[raffleThresholds.length - 1];

        // CHECK 1: Verify threshold met
        require(
            accumulatedProtocolShare >= threshold,
            "Raffle threshold not met"
        );

        // CHECK 2: Verify caller is enrolled in active tournament
        require(
            _isCallerEnrolledInActiveTournament(msg.sender),
            "Only enrolled players can trigger raffle"
        );

        // EFFECT 3: Calculate raffle amount
        // (reserve must use current threshold, not next threshold)
        uint256 reserve = (threshold * 5) / 100;  // 5% of current threshold
        uint256 raffleAmount = accumulatedProtocolShare - reserve;
        ownerAmount = (raffleAmount * 5) / 95;  // 5% of total (5/95 of remaining)
        winnerAmount = (raffleAmount * 90) / 95; // 90% of total (90/95 of remaining)

        // EFFECT 4: Update accumulated protocol share (keep reserve)
        accumulatedProtocolShare = reserve;

        // EFFECT 5: Get all enrolled players with weights
        (
            address[] memory players,
            uint16[] memory weights,
            uint256 totalWeight
        ) = _getAllEnrolledPlayersWithWeights();

        require(totalWeight > 0, "No eligible players for raffle");

        // EFFECT 6: Generate randomness and select winner
        uint256 randomness = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            block.number,
            msg.sender,
            accumulatedProtocolShare
        )));

        winner = _selectWeightedWinner(players, weights, totalWeight, randomness);

        // Find winner's enrollment count for event
        uint256 winnerEnrollmentCount = 0;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == winner) {
                winnerEnrollmentCount = weights[i];
                break;
            }
        }

        // EFFECT 7: Store historic raffle result by pushing to array
        raffleResults.push(RaffleResult({
            executor: msg.sender,
            timestamp: uint64(block.timestamp),
            rafflePot: raffleAmount + reserve,
            participants: players,
            weights: weights,
            winner: winner
        }));

        // INTERACTION 1: Send to owner
        (bool ownerSent, ) = payable(owner).call{value: ownerAmount}("");
        require(ownerSent, "Failed to send owner share");

        // INTERACTION 2: Send to winner
        (bool winnerSent, ) = payable(winner).call{value: winnerAmount}("");
        require(winnerSent, "Failed to send winner share");

        return (winner, ownerAmount, winnerAmount);
    }

    // ============ Raffle Info Getters ============

    /**
     * @dev Returns complete raffle result data for a specific raffle index
     * Needed because public mapping can't return dynamic arrays
     * Client can derive: reserve=5% of rafflePot, owner=5% of 95%, winner=90% of 95%
     */
    function getRaffleResult(uint256 raffleIndex)
        external
        view
        returns (
            address executor,
            uint64 timestamp,
            uint256 rafflePot,
            address[] memory participants,
            uint16[] memory weights,
            address winner
        )
    {
        RaffleResult storage result = raffleResults[raffleIndex];
        return (
            result.executor,
            result.timestamp,
            result.rafflePot,
            result.participants,
            result.weights,
            result.winner
        );
    }

    // Note: getRaffleInfo() function is now inherited from ETour_Base
}
