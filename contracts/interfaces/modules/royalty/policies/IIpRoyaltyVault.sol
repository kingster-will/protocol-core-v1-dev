// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IpRoyaltyVault interface
interface IIpRoyaltyVault {
    /// @notice Event emitted when a revenue token is added to a vault
    /// @param token The address of the revenue token
    /// @param amount The amount of revenue token added
    event RevenueTokenAddedToVault(address token, uint256 amount);

    /// @notice Event emitted when a revenue token is claimed
    /// @param claimer The address of the claimer
    /// @param token The revenue token claimed
    /// @param amount The amount of revenue token claimed
    event RevenueTokenClaimed(address claimer, address token, uint256 amount);

    /// @notice Initializer for this implementation contract
    /// @param name The name of the royalty token
    /// @param symbol The symbol of the royalty token
    /// @param supply The total supply of the royalty token
    /// @param ipIdAddress The ip id the royalty vault belongs to
    /// @param rtReceiver The address of the royalty token receiver
    function initialize(
        string memory name,
        string memory symbol,
        uint32 supply,
        address ipIdAddress,
        address rtReceiver
    ) external;

    /// @notice Updates the vault balance with the new amount of revenue token
    /// @param token The address of the revenue token
    /// @param amount The amount of revenue token to add
    /// @dev Only callable by the royalty module or whitelisted royalty policy
    function updateVaultBalance(address token, uint256 amount) external;

    /// @notice Allows token holders to claim revenue token
    /// @param claimer The address of the claimer
    /// @param token The revenue tokens to claim
    /// @return The amount of revenue tokens claimed
    function claimRevenueOnBehalf(address claimer, address token) external returns (uint256);

    /// @notice Allows token holders to claim a batch of revenue tokens
    /// @param claimer The address of the claimer
    /// @param tokenList The list of revenue tokens to claim
    /// @return The amount of revenue tokens claimed of each token
    function claimRevenueOnBehalfByTokenBatch(
        address claimer,
        address[] calldata tokenList
    ) external returns (uint256[] memory);

    /// @notice Allows to claim revenue tokens on behalf of the ip royalty vault
    /// @param tokenList The list of revenue tokens to claim
    /// @param targetIpId The target ip id to claim revenue tokens from
    function claimByTokenBatchAsSelf(address[] calldata tokenList, address targetIpId) external;

    /// @notice Get total amount of revenue token claimable by a token holder
    /// @param claimer The address of the token holder
    /// @param token The revenue token to claim
    /// @return The amount of revenue token claimable
    function claimableRevenue(address claimer, address token) external view returns (uint256);

    /// @notice The ip id to whom this royalty vault belongs to
    function ipId() external view returns (address);

    /// @notice The list of revenue tokens in the vault
    function tokens() external view returns (address[] memory);
}
