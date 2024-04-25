// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IIPAccountStorage } from "./interfaces/IIPAccountStorage.sol";
import { IModuleRegistry } from "./interfaces/registries/IModuleRegistry.sol";
import { Errors } from "./lib/Errors.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { ShortStrings } from "@openzeppelin/contracts/utils/ShortStrings.sol";
/// @title IPAccount Storage
/// @dev Implements the IIPAccountStorage interface for managing IPAccount's state using a namespaced storage pattern.
/// Inherits all functionalities from IIPAccountStorage, providing concrete implementations for the interface's methods.
/// This contract allows Modules to store and retrieve data in a structured and conflict-free manner
/// by utilizing namespaces, where the default namespace is determined by the
/// `msg.sender` (the caller Module's address).
contract IPAccountStorage is ERC165, IIPAccountStorage {
    using ShortStrings for *;

    address public immutable MODULE_REGISTRY;
    address public immutable LICENSE_REGISTRY;
    address public immutable IP_ASSET_REGISTRY;

    mapping(bytes32 => mapping(bytes32 => bytes)) public bytesData;
    mapping(bytes32 => mapping(bytes32 => bytes32)) public bytes32Data;

    modifier onlyRegisteredModule() {
        if (
            msg.sender != IP_ASSET_REGISTRY &&
            msg.sender != LICENSE_REGISTRY &&
            !IModuleRegistry(MODULE_REGISTRY).isRegistered(msg.sender)
        ) {
            revert Errors.IPAccountStorage__NotRegisteredModule(msg.sender);
        }
        _;
    }

    constructor(address ipAssetRegistry, address licenseRegistry, address moduleRegistry) {
        MODULE_REGISTRY = moduleRegistry;
        LICENSE_REGISTRY = licenseRegistry;
        IP_ASSET_REGISTRY = ipAssetRegistry;
    }

    /// @inheritdoc IIPAccountStorage
    function setBytes(bytes32 key, bytes calldata value) external onlyRegisteredModule {
        bytesData[_toBytes32(msg.sender)][key] = value;
    }

    /// @inheritdoc IIPAccountStorage
    function setBytesBatch(bytes32[] calldata keys, bytes[] calldata values) external onlyRegisteredModule {
        if (keys.length != values.length) revert Errors.IPAccountStorage__InvalidBatchLengths();
        for (uint256 i = 0; i < keys.length; i++) {
            bytesData[_toBytes32(msg.sender)][keys[i]] = values[i];
        }
    }

    /// @inheritdoc IIPAccountStorage
    function getBytesBatch(
        bytes32[] calldata namespaces,
        bytes32[] calldata keys
    ) external view returns (bytes[] memory values) {
        if (namespaces.length != keys.length) revert Errors.IPAccountStorage__InvalidBatchLengths();
        values = new bytes[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            values[i] = bytesData[namespaces[i]][keys[i]];
        }
    }

    /// @inheritdoc IIPAccountStorage
    function getBytes(bytes32 key) external view returns (bytes memory) {
        return bytesData[_toBytes32(msg.sender)][key];
    }
    /// @inheritdoc IIPAccountStorage
    function getBytes(bytes32 namespace, bytes32 key) external view returns (bytes memory) {
        return bytesData[namespace][key];
    }

    /// @inheritdoc IIPAccountStorage
    function setBytes32(bytes32 key, bytes32 value) external onlyRegisteredModule {
        bytes32Data[_toBytes32(msg.sender)][key] = value;
    }

    /// @inheritdoc IIPAccountStorage
    function setBytes32Batch(bytes32[] calldata keys, bytes32[] calldata values) external onlyRegisteredModule {
        if (keys.length != values.length) revert Errors.IPAccountStorage__InvalidBatchLengths();
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32Data[_toBytes32(msg.sender)][keys[i]] = values[i];
        }
    }

    /// @inheritdoc IIPAccountStorage
    function getBytes32Batch(
        bytes32[] calldata namespaces,
        bytes32[] calldata keys
    ) external view returns (bytes32[] memory values) {
        if (namespaces.length != keys.length) revert Errors.IPAccountStorage__InvalidBatchLengths();
        values = new bytes32[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            values[i] = bytes32Data[namespaces[i]][keys[i]];
        }
    }

    /// @inheritdoc IIPAccountStorage
    function getBytes32(bytes32 key) external view returns (bytes32) {
        return bytes32Data[_toBytes32(msg.sender)][key];
    }
    /// @inheritdoc IIPAccountStorage
    function getBytes32(bytes32 namespace, bytes32 key) external view returns (bytes32) {
        return bytes32Data[namespace][key];
    }

    /// @notice ERC165 interface identifier for IIPAccountStorage
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IIPAccountStorage).interfaceId || super.supportsInterface(interfaceId);
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}
