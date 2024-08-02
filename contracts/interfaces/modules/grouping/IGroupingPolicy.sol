// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/// @title IGroupingPolicy
/// @notice Interface for grouping policies
interface IGroupingPolicy {
    /// @notice Returns the reward for each IP in the group
    /// @param groupId The group ID
    /// @param token The reward token
    /// @param ipIds The IP IDs
    /// @return The rewards for each IP
    function getReward(
        address groupId,
        address token,
        address[] calldata ipIds
    ) external view returns (uint256[] memory);
}