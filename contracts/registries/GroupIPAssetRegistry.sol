// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IIPAccount } from "../interfaces/IIPAccount.sol";
import { IGroupIPAssetRegistry } from "../interfaces/registries/IGroupIPAssetRegistry.sol";
import { IGroupingModule } from "../interfaces/modules/grouping/IGroupingModule.sol";
import { ProtocolPausableUpgradeable } from "../pause/ProtocolPausableUpgradeable.sol";
import { Errors } from "../lib/Errors.sol";
import { IPAccountStorageOps } from "../lib/IPAccountStorageOps.sol";

/// @title IP Asset Registry
/// @notice This contract acts as the source of truth for all IP registered in
///         Story Protocol. An IP is identified by its contract address, token
///         id, and coin type, meaning any NFT may be conceptualized as an IP.
///         Once an IP is registered into the protocol, a corresponding IP
///         asset is generated, which references an IP resolver for metadata
///         attribution and an IP account for protocol authorization.
///         IMPORTANT: The IP account address, besides being used for protocol
///                    auth, is also the canonical IP identifier for the IP NFT.
abstract contract GroupIPAssetRegistry is IGroupIPAssetRegistry, ProtocolPausableUpgradeable {
    using IPAccountStorageOps for IIPAccount;
    using EnumerableSet for EnumerableSet.AddressSet;
    using ERC165Checker for address;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable

    IGroupingModule public immutable GROUPING_MODULE;

    /// @dev Storage structure for the Group IPAsset Registry
    /// @custom:storage-location erc7201:story-protocol.GroupIPAssetRegistry
    struct GroupIPAssetRegistryStorage {
        mapping(address groupIpId => EnumerableSet.AddressSet memberIpIds) groups;
        mapping(address ipId => address rewardPool) rewardPools;
        mapping(address rewardPool => bool isRegistered) registeredGroupRewardPools;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.GroupIPAssetRegistry")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GroupIPAssetRegistryStorageLocation =
        0xa87c61809af5a42943abd137c7acff8426aab6f7a1f5c967a03d1d718ba5cf00;

    modifier onlyGroupingModule() {
        if (msg.sender != address(GROUPING_MODULE)) {
            revert Errors.GroupIPAssetRegistry__CallerIsNotGroupingModule(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address groupingModule) {
        GROUPING_MODULE = IGroupingModule(groupingModule);
        _disableInitializers();
    }

    /// @notice Registers a Group IPA
    /// @param groupNft The address of the group IPA
    /// @param groupNftId The id of the group IPA
    /// @param rewardPool The address of the group reward pool
    /// @return groupId The address of the newly registered Group IPA.
    function registerGroup(
        address groupNft,
        uint256 groupNftId,
        address rewardPool
    ) external onlyGroupingModule whenNotPaused returns (address groupId) {
        groupId = _register({ chainid: block.chainid, tokenContract: groupNft, tokenId: groupNftId });

        IIPAccount(payable(groupId)).setBool("GROUP_IPA", true);
        GroupIPAssetRegistryStorage storage $ = _getGroupIPAssetRegistryStorage();
        if (!$.registeredGroupRewardPools[rewardPool]) {
            revert Errors.GroupIPAssetRegistry__GroupRewardPoolNotRegistered(rewardPool);
        }
        _getGroupIPAssetRegistryStorage().rewardPools[groupId] = rewardPool;
    }

    /// @notice Whitelists a group reward pool
    /// @param rewardPool The address of the group reward pool
    function whitelistGroupRewardPool(address rewardPool) external onlyGroupingModule whenNotPaused {
        _getGroupIPAssetRegistryStorage().registeredGroupRewardPools[rewardPool] = true;
    }

    function addGroupMember(address groupId, address[] calldata ipIds) external onlyGroupingModule whenNotPaused {
        if (!_isRegisteredGroup(groupId)) {
            revert Errors.GroupIPAssetRegistry__NotRegisteredGroupIP(groupId);
        }
        EnumerableSet.AddressSet storage allMemberIpIds = _getGroupIPAssetRegistryStorage().groups[groupId];
        for (uint256 i = 0; i < ipIds.length; i++) {
            address ipId = ipIds[i];
            if (!_isRegistered(ipId)) revert Errors.GroupIPAssetRegistry__NotRegisteredIP(ipId);
            allMemberIpIds.add(ipId);
        }
    }

    function removeGroupMember(address groupId, address[] calldata ipIds) external onlyGroupingModule whenNotPaused {
        if (!_isRegisteredGroup(groupId)) {
            revert Errors.GroupIPAssetRegistry__NotRegisteredGroupIP(groupId);
        }
        EnumerableSet.AddressSet storage allMemberIpIds = _getGroupIPAssetRegistryStorage().groups[groupId];
        for (uint256 i = 0; i < ipIds.length; i++) {
            allMemberIpIds.remove(ipIds[i]);
        }
    }

    /// @notice Checks whether a group IPA was registered based on its ID.
    /// @param groupId The address of the Group IPA.
    /// @return isRegistered Whether the Group IPA was registered into the protocol.
    function isRegisteredGroup(address groupId) external view returns (bool) {
        if (!_isRegistered(groupId)) return false;
        return IIPAccount(payable(groupId)).getBool("GROUP_IPA");
    }

    /// @notice Retrieves the group policy for a Group IPA
    /// @param groupId The address of the Group IPA.
    /// @return rewardPool The address of the group policy.
    function getGroupRewardPool(address groupId) external view returns (address) {
        return _getGroupIPAssetRegistryStorage().rewardPools[groupId];
    }

    /// @notice Retrieves the group members for a Group IPA
    /// @param groupId The address of the Group IPA.
    /// @param startIndex The start index of the group members to retrieve
    /// @param size The size of the group members to retrieve
    /// @return results The addresses of the group members
    function getGroupMembers(
        address groupId,
        uint256 startIndex,
        uint256 size
    ) external view returns (address[] memory results) {
        EnumerableSet.AddressSet storage allMemberIpIds = _getGroupIPAssetRegistryStorage().groups[groupId];
        uint256 totalSize = allMemberIpIds.length();
        if (startIndex >= totalSize) return results;

        uint256 resultsSize = (startIndex + size) > totalSize ? size - ((startIndex + size) - totalSize) : size;
        for (uint256 i = 0; i < resultsSize; i++) {
            results[i] = allMemberIpIds.at(startIndex + i);
        }
        return results;
    }

    /// @notice Checks whether an IP is a member of a Group IPA
    /// @param groupId The address of the Group IPA.
    /// @param ipId The address of the IP.
    /// @return isMember Whether the IP is a member of the Group IPA.
    function containsIp(address groupId, address ipId) external view returns (bool) {
        return _getGroupIPAssetRegistryStorage().groups[groupId].contains(ipId);
    }

    /// @notice Retrieves the total number of members in a Group IPA
    /// @param groupId The address of the Group IPA.
    /// @return totalMembers The total number of members in the Group IPA.
    function totalMembers(address groupId) external view returns (uint256) {
        return _getGroupIPAssetRegistryStorage().groups[groupId].length();
    }

    function _isRegisteredGroup(address groupId) internal view returns (bool) {
        if (!_isRegistered(groupId)) return false;
        return IIPAccount(payable(groupId)).getBool("GROUP_IPA");
    }

    function _register(uint256 chainid, address tokenContract, uint256 tokenId) internal virtual returns (address id);

    function _isRegistered(address id) internal view virtual returns (bool);

    /// @dev Returns the storage struct of GroupIPAssetRegistry.
    function _getGroupIPAssetRegistryStorage() private pure returns (GroupIPAssetRegistryStorage storage $) {
        assembly {
            $.slot := GroupIPAssetRegistryStorageLocation
        }
    }
}