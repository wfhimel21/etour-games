// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ETour_Base.sol";

/**
 * @title ETour_Prizes
 * @dev Stateless module for prize distribution and tournament reset
 *
 * This module handles:
 * - Prize calculation based on ranking and prize distribution
 * - Prize sending with fallback to protocol pool
 * - Equal prize distribution for all-draw scenarios
 * - Player earnings tracking and leaderboard management
 * - Tournament state reset after completion
 *
 * CRITICAL - DELEGATECALL SEMANTICS:
 * When game contract calls this module via delegatecall:
 * - This code executes AS IF it's part of the game contract
 * - Can directly access storage variables (tournaments, playerPrizes, etc.)
 * - address(this) = game contract address
 * - msg.sender = original caller
 * - msg.value = value sent
 *
 * STATELESS: This contract declares NO storage variables of its own.
 * All storage access is to the game contract's storage via delegatecall context.
 */
contract ETour_Prizes is ETour_Base {

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

    // ============ Prize Distribution Functions ============

    /**
     * @dev Attempts to send prize to a recipient with fallback to protocol pool if failed
     * EXACT COPY from ETour.sol lines 1214-1236
     * INTERNAL - Only called within this module by distributePrizes/distributeEqualPrizes
     */
    function sendPrizeWithFallback(
        address recipient,
        uint256 amount,
        uint8 tierId,
        uint8 instanceId,
        string memory gameName
    ) internal returns (bool success) {
        require(amount > 0, "AM");

        // Attempt to send the prize once
        (bool sent, ) = payable(recipient).call{value: amount}("");

        if (sent) {
            return true; // Prize sent successfully
        }

        // If send failed, add amount to accumulated protocol share
        accumulatedProtocolShare += amount;

        return false; // Indicate fallback occurred
    }

    /**
     * @dev Distribute prize to tournament winner (winner-takes-all)
     * Simplified from ranking-based distribution
     * @return winners Array of addresses that received prizes
     * @return prizes Array of prize amounts corresponding to each winner
     */
    function distributePrizes(uint8 tierId, uint8 instanceId, uint256 winnersPot, string memory gameName)
        external
        onlyDelegateCall
        returns (address[] memory winners, uint256[] memory prizes)
    {
        address winner = tournaments[tierId][instanceId].winner;
        playerPrizes[tierId][instanceId][winner] = winnersPot;

        // Attempt to send prize with fallback to protocol pool if failed
        bool sent = sendPrizeWithFallback(winner, winnersPot, tierId, instanceId, gameName);

        // Return arrays (always single winner)
        winners = new address[](1);
        prizes = new uint256[](1);
        winners[0] = winner;
        prizes[0] = sent ? winnersPot : 0;
    }

    /**
     * @dev Distribute equal prizes to all remaining players (all-draw scenario)
     * EXACT COPY from ETour.sol lines 1276-1297
     * @return winners Array of addresses that received prizes
     * @return prizes Array of prize amounts corresponding to each winner
     */
    function distributeEqualPrizes(
        uint8 tierId,
        uint8 instanceId,
        address[] memory remainingPlayers,
        uint256 winnersPot,
        string memory gameName
    ) external onlyDelegateCall returns (address[] memory winners, uint256[] memory prizes) {
        uint256 prizePerPlayer = winnersPot / remainingPlayers.length;

        // Use temporary arrays with max possible size
        address[] memory tempWinners = new address[](remainingPlayers.length);
        uint256[] memory tempPrizes = new uint256[](remainingPlayers.length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < remainingPlayers.length; i++) {
            address player = remainingPlayers[i];
            playerPrizes[tierId][instanceId][player] = prizePerPlayer;

            // Attempt to send prize with fallback to protocol pool if failed
            // Call directly as internal function (no nested delegatecall needed)
            bool sent = sendPrizeWithFallback(player, prizePerPlayer, tierId, instanceId, gameName);

            // Only add to return arrays if prize was successfully sent
            if (sent) {
                tempWinners[successCount] = player;
                tempPrizes[successCount] = prizePerPlayer;
                successCount++;
            }
        }

        // Create properly sized return arrays
        winners = new address[](successCount);
        prizes = new uint256[](successCount);
        for (uint256 i = 0; i < successCount; i++) {
            winners[i] = tempWinners[i];
            prizes[i] = tempPrizes[i];
        }
    }

    // Removed: calculatePrizeForRank and _calculatePrizeForRank (no longer needed with winner-takes-all)

    // ============ Earnings & Leaderboard Functions ============

    /**
     * @dev Update player earnings after tournament completion
     * EXACT COPY from ETour.sol lines 2109-2126
     */
    function updatePlayerEarnings(uint8 tierId, uint8 instanceId, address winner) external onlyDelegateCall {
        address[] storage players = enrolledPlayers[tierId][instanceId];

        // Only track players who actually won prizes on the leaderboard
        for (uint8 i = 0; i < players.length; i++) {
            address player = players[i];
            uint256 prize = playerPrizes[tierId][instanceId][player];

            if (prize > 0) {
                // Player won a prize - track them and add earnings
                // Call directly as internal function (no nested delegatecall needed)
                trackOnLeaderboard(player);

                playerEarnings[player] += int256(prize);
            }
            // Players with no prize are not tracked unless already on leaderboard
        }
    }

    /**
     * @dev Track player on leaderboard if not already tracked
     * EXACT COPY from ETour.sol lines 2144-2149
     * INTERNAL - Only called within this module by updatePlayerEarnings
     */
    function trackOnLeaderboard(address player) internal {
        if (!_isOnLeaderboard[player]) {
            _isOnLeaderboard[player] = true;
            _leaderboardPlayers.push(player);
        }
    }

    // Note: resetTournamentAfterCompletion moved to ETour_Core.sol
    // Tournament lifecycle (including reset) belongs in Core module

    // ============ Leaderboard Getters ============

    // Note: LeaderboardEntry struct and getLeaderboard() function
    // are now inherited from ETour_Base

    /**
     * @dev Get count of players on leaderboard
     * EXACT COPY from ETour.sol lines 2438-2440
     */
    function getLeaderboardCount() external view returns (uint256) {
        return _leaderboardPlayers.length;
    }
}
