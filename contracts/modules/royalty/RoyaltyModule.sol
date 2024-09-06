// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import { BaseModule } from "../BaseModule.sol";
import { VaultController } from "./policies/VaultController.sol";
import { IRoyaltyModule } from "../../interfaces/modules/royalty/IRoyaltyModule.sol";
import { IRoyaltyPolicy } from "../../interfaces/modules/royalty/policies/IRoyaltyPolicy.sol";
import { IExternalRoyaltyPolicy } from "../../interfaces/modules/royalty/policies/IExternalRoyaltyPolicy.sol";
import { IGroupIPAssetRegistry } from "../../interfaces/registries/IGroupIPAssetRegistry.sol";
import { IIpRoyaltyVault } from "../../interfaces/modules/royalty/policies/IIpRoyaltyVault.sol";
import { IDisputeModule } from "../../interfaces/modules/dispute/IDisputeModule.sol";
import { ILicenseRegistry } from "../../interfaces/registries/ILicenseRegistry.sol";
import { ILicensingModule } from "../../interfaces/modules/licensing/ILicensingModule.sol";
import { Errors } from "../../lib/Errors.sol";
import { ROYALTY_MODULE_KEY } from "../../lib/modules/Module.sol";

/// @title Story Protocol Royalty Module
/// @notice The Story Protocol royalty module governs the way derivatives pay royalties to their ancestors
contract RoyaltyModule is IRoyaltyModule, VaultController, ReentrancyGuardUpgradeable, BaseModule, UUPSUpgradeable {
    using ERC165Checker for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @notice Ip graph precompile contract address
    address public constant IP_GRAPH = address(0x1A);

    /// @notice Returns the percentage scale - represents 100% of royalty tokens for an ip
    uint32 public constant TOTAL_RT_SUPPLY = 100000000; // 100 * 10 ** 6

    /// @notice Returns the canonical protocol-wide licensing module
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicensingModule public immutable LICENSING_MODULE;

    /// @notice Returns the protocol-wide dispute module
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDisputeModule public immutable DISPUTE_MODULE;

    /// @notice Returns the canonical protocol-wide LicenseRegistry
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicenseRegistry public immutable LICENSE_REGISTRY;

    /// @notice Returns the canonical protocol-wide IPAssetRegistry
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGroupIPAssetRegistry public immutable IP_ASSET_REGISTRY;

    /// @dev Storage structure for the RoyaltyModule
    /// @param maxParents The maximum number of parents an IP asset can have
    /// @param maxAncestors The maximum number of ancestors an IP asset can have
    /// @param maxAccumulatedRoyaltyPolicies The maximum number of accumulated royalty policies an IP asset can have
    /// @param isWhitelistedRoyaltyPolicy Indicates if a royalty policy is whitelisted
    /// @param isWhitelistedRoyaltyToken Indicates if a royalty token is whitelisted
    /// @param isRegisteredExternalRoyaltyPolicy Indicates if an external royalty policy is registered
    /// @param ipRoyaltyVaults Indicates the royalty vault for a given IP asset (if any)
    /// @param accumulatedRoyaltyPolicies Indicates the accumulated royalty policies for a given IP asset
    /// @custom:storage-location erc7201:story-protocol.RoyaltyModule
    struct RoyaltyModuleStorage {
        uint256 maxParents;
        uint256 maxAncestors;
        uint256 maxAccumulatedRoyaltyPolicies;
        mapping(address royaltyPolicy => bool isWhitelisted) isWhitelistedRoyaltyPolicy;
        mapping(address token => bool) isWhitelistedRoyaltyToken;
        mapping(address royaltyPolicy => bool) isRegisteredExternalRoyaltyPolicy;
        mapping(address ipId => address ipRoyaltyVault) ipRoyaltyVaults;
        mapping(address ipId => EnumerableSet.AddressSet) accumulatedRoyaltyPolicies;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.RoyaltyModule")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant RoyaltyModuleStorageLocation =
        0x98dd2c34f21d19fd1d178ed731f3db3d03e0b4e39f02dbeb040e80c9427a0300;

    string public constant override name = ROYALTY_MODULE_KEY;

    /// @notice Constructor
    /// @param licensingModule The address of the licensing module
    /// @param disputeModule The address of the dispute module
    /// @param licenseRegistry The address of the license registry
    /// @param ipAssetRegistry The address of the ip asset registry
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address licensingModule, address disputeModule, address licenseRegistry, address ipAssetRegistry) {
        if (licensingModule == address(0)) revert Errors.RoyaltyModule__ZeroLicensingModule();
        if (disputeModule == address(0)) revert Errors.RoyaltyModule__ZeroDisputeModule();
        if (licenseRegistry == address(0)) revert Errors.RoyaltyModule__ZeroLicenseRegistry();
        if (ipAssetRegistry == address(0)) revert Errors.RoyaltyModule__ZeroIpAssetRegistry();

        LICENSING_MODULE = ILicensingModule(licensingModule);
        DISPUTE_MODULE = IDisputeModule(disputeModule);
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
        IP_ASSET_REGISTRY = IGroupIPAssetRegistry(ipAssetRegistry);

        _disableInitializers();
    }

    /// @notice Initializer for this implementation contract
    /// @param accessManager The address of the protocol admin roles contract
    /// @param parentLimit The maximum number of parents an IP asset can have
    /// @param ancestorLimit The maximum number of ancestors an IP asset can have
    /// @param accumulatedRoyaltyPoliciesLimit The maximum number of accumulated royalty policies an IP asset can have
    function initialize(
        address accessManager,
        uint256 parentLimit,
        uint256 ancestorLimit,
        uint256 accumulatedRoyaltyPoliciesLimit
    ) external initializer {
        if (accessManager == address(0)) revert Errors.RoyaltyModule__ZeroAccessManager();
        if (parentLimit == 0) revert Errors.RoyaltyModule__ZeroMaxParents();
        if (ancestorLimit == 0) revert Errors.RoyaltyModule__ZeroMaxAncestors();
        if (accumulatedRoyaltyPoliciesLimit == 0) revert Errors.RoyaltyModule__ZeroAccumulatedRoyaltyPoliciesLimit();

        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        $.maxParents = parentLimit;
        $.maxAncestors = ancestorLimit;
        $.maxAccumulatedRoyaltyPolicies = accumulatedRoyaltyPoliciesLimit;

        __ProtocolPausable_init(accessManager);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /// @notice Modifier to enforce that the caller is the licensing module
    modifier onlyLicensingModule() {
        if (msg.sender != address(LICENSING_MODULE)) revert Errors.RoyaltyModule__NotAllowedCaller();
        _;
    }

    /// @notice Sets the ip graph limits
    /// @dev Enforced to be only callable by the protocol admin
    /// @param parentLimit The maximum number of parents an IP asset can have
    /// @param ancestorLimit The maximum number of ancestors an IP asset can have
    /// @param accumulatedRoyaltyPoliciesLimit The maximum number of accumulated royalty policies an IP asset can have
    function setIpGraphLimits(
        uint256 parentLimit,
        uint256 ancestorLimit,
        uint256 accumulatedRoyaltyPoliciesLimit
    ) external restricted {
        if (parentLimit == 0) revert Errors.RoyaltyModule__ZeroMaxParents();
        if (ancestorLimit == 0) revert Errors.RoyaltyModule__ZeroMaxAncestors();
        if (accumulatedRoyaltyPoliciesLimit == 0) revert Errors.RoyaltyModule__ZeroAccumulatedRoyaltyPoliciesLimit();

        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        $.maxParents = parentLimit;
        $.maxAncestors = ancestorLimit;
        $.maxAccumulatedRoyaltyPolicies = accumulatedRoyaltyPoliciesLimit;

        emit IpGraphLimitsUpdated(parentLimit, ancestorLimit, accumulatedRoyaltyPoliciesLimit);
    }

    /// @notice Whitelist a royalty policy
    /// @dev Enforced to be only callable by the protocol admin
    /// @param royaltyPolicy The address of the royalty policy
    /// @param allowed Indicates if the royalty policy is whitelisted or not
    function whitelistRoyaltyPolicy(address royaltyPolicy, bool allowed) external restricted {
        if (royaltyPolicy == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyPolicy();

        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        $.isWhitelistedRoyaltyPolicy[royaltyPolicy] = allowed;

        emit RoyaltyPolicyWhitelistUpdated(royaltyPolicy, allowed);
    }

    /// @notice Whitelist a royalty token
    /// @dev Enforced to be only callable by the protocol admin
    /// @param token The token address
    /// @param allowed Indicates if the token is whitelisted or not
    function whitelistRoyaltyToken(address token, bool allowed) external restricted {
        if (token == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyToken();

        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        $.isWhitelistedRoyaltyToken[token] = allowed;

        emit RoyaltyTokenWhitelistUpdated(token, allowed);
    }

    /// @notice Registers an external royalty policy
    /// @param externalRoyaltyPolicy The address of the external royalty policy
    function registerExternalRoyaltyPolicy(address externalRoyaltyPolicy) external nonReentrant {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        if (
            $.isWhitelistedRoyaltyPolicy[externalRoyaltyPolicy] ||
            $.isRegisteredExternalRoyaltyPolicy[externalRoyaltyPolicy]
        ) revert Errors.RoyaltyModule__PolicyAlreadyWhitelistedOrRegistered();

        // checks if the IExternalRoyaltyPolicy call does not revert
        // external royalty policies contracts should inherit IExternalRoyaltyPolicy interface
        if (IExternalRoyaltyPolicy(externalRoyaltyPolicy).rtsRequiredToLink(address(0), 0) >= uint32(0)) {
            $.isRegisteredExternalRoyaltyPolicy[externalRoyaltyPolicy] = true;
            emit ExternalRoyaltyPolicyRegistered(externalRoyaltyPolicy);
        }
    }

    /// @notice Executes royalty related logic on license minting
    /// @dev Enforced to be only callable by LicensingModule
    /// @param ipId The ipId whose license is being minted (licensor)
    /// @param royaltyPolicy The royalty policy address of the license being minted
    /// @param licensePercent The license percentage of the license being minted
    /// @param externalData The external data custom to each the royalty policy
    function onLicenseMinting(
        address ipId,
        address royaltyPolicy,
        uint32 licensePercent,
        bytes calldata externalData
    ) external nonReentrant onlyLicensingModule {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();
        if (royaltyPolicy == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyPolicy();
        if (licensePercent > TOTAL_RT_SUPPLY) revert Errors.RoyaltyModule__AboveRoyaltyTokenSupplyLimit();

        if (!$.isWhitelistedRoyaltyPolicy[royaltyPolicy] && !$.isRegisteredExternalRoyaltyPolicy[royaltyPolicy])
            revert Errors.RoyaltyModule__NotAllowedRoyaltyPolicy();

        // If the an ipId has the maximum number of ancestors
        // it can not have any derivative and therefore is not allowed to mint a license
        if (_getAncestorCount(ipId) >= $.maxAncestors) revert Errors.RoyaltyModule__LastPositionNotAbleToMintLicense();

        // deploy ipRoyaltyVault for the ipId given it does not exist yet
        if ($.ipRoyaltyVaults[ipId] == address(0)) {
            address receiver = IP_ASSET_REGISTRY.isRegisteredGroup(ipId)
                ? IP_ASSET_REGISTRY.getGroupRewardPool(ipId)
                : ipId;

            _deployIpRoyaltyVault(ipId, receiver);
        }

        // for whitelisted policies calls onLicenseMinting
        if ($.isWhitelistedRoyaltyPolicy[royaltyPolicy]) {
            IRoyaltyPolicy(royaltyPolicy).onLicenseMinting(ipId, licensePercent, externalData);
        }
    }

    /// @notice Executes royalty related logic on linking to parents
    /// @dev Enforced to be only callable by LicensingModule
    /// @param ipId The children ipId that is being linked to parents
    /// @param parentIpIds The parent ipIds that the children ipId is being linked to
    /// @param licensesPercent The license percentage of the licenses being minted
    /// @param externalData The external data custom to each the royalty policy
    function onLinkToParents(
        address ipId,
        address[] calldata parentIpIds,
        address[] calldata licenseRoyaltyPolicies,
        uint32[] calldata licensesPercent,
        bytes calldata externalData
    ) external nonReentrant onlyLicensingModule {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();

        // If an IP already has a vault, it means that it's either a root node which cannot link to parents
        // or it's a derivative in which case it cannot link to parents either
        if ($.ipRoyaltyVaults[ipId] != address(0)) revert Errors.RoyaltyModule__UnlinkableToParents();

        if (parentIpIds.length == 0) revert Errors.RoyaltyModule__NoParentsOnLinking();
        if (parentIpIds.length > $.maxParents) revert Errors.RoyaltyModule__AboveParentLimit();
        if (_getAncestorCount(ipId) > $.maxAncestors) revert Errors.RoyaltyModule__AboveAncestorsLimit();

        // deploy ipRoyaltyVault for the ipId given it does not exist yet
        address ipRoyaltyVault = _deployIpRoyaltyVault(ipId, address(this));

        // send royalty tokens to the royalty policies
        // and saves the ancestors royalty policies for the child
        _distributeRoyaltyTokensToPolicies(ipId, parentIpIds, licenseRoyaltyPolicies, licensesPercent, ipRoyaltyVault);

        // for whitelisted policies calls onLinkToParents
        address[] memory accRoyaltyPolicies = $.accumulatedRoyaltyPolicies[ipId].values();
        for (uint256 i = 0; i < accRoyaltyPolicies.length; i++) {
            if (
                !$.isWhitelistedRoyaltyPolicy[accRoyaltyPolicies[i]] &&
                !$.isRegisteredExternalRoyaltyPolicy[accRoyaltyPolicies[i]]
            ) revert Errors.RoyaltyModule__NotWhitelistedOrRegisteredRoyaltyPolicy();

            if ($.isWhitelistedRoyaltyPolicy[accRoyaltyPolicies[i]]) {
                IRoyaltyPolicy(accRoyaltyPolicies[i]).onLinkToParents(
                    ipId,
                    parentIpIds,
                    licenseRoyaltyPolicies,
                    licensesPercent,
                    externalData
                );
            }
        }
    }

    /// @notice Allows the function caller to pay royalties to the receiver IP asset on behalf of the payer IP asset.
    /// @param receiverIpId The ipId that receives the royalties
    /// @param payerIpId The ipId that pays the royalties
    /// @param token The token to use to pay the royalties
    /// @param amount The amount to pay
    function payRoyaltyOnBehalf(
        address receiverIpId,
        address payerIpId,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        IDisputeModule dispute = DISPUTE_MODULE;
        if (dispute.isIpTagged(receiverIpId) || dispute.isIpTagged(payerIpId))
            revert Errors.RoyaltyModule__IpIsTagged();

        _payToReceiverVault(receiverIpId, msg.sender, token, amount);

        emit RoyaltyPaid(receiverIpId, payerIpId, msg.sender, token, amount);
    }

    /// @notice Allows to pay the minting fee for a license
    /// @param receiverIpId The ipId that receives the royalties
    /// @param payerAddress The address that pays the royalties
    /// @param token The token to use to pay the royalties
    /// @param amount The amount to pay
    function payLicenseMintingFee(
        address receiverIpId,
        address payerAddress,
        address token,
        uint256 amount
    ) external onlyLicensingModule {
        if (DISPUTE_MODULE.isIpTagged(receiverIpId)) revert Errors.RoyaltyModule__IpIsTagged();

        _payToReceiverVault(receiverIpId, payerAddress, token, amount);

        emit LicenseMintingFeePaid(receiverIpId, payerAddress, token, amount);
    }

    /// @notice Returns the total number of royalty tokens
    function totalRtSupply() external pure returns (uint32) {
        return TOTAL_RT_SUPPLY;
    }

    /// @notice Indicates if a royalty policy is whitelisted
    /// @param royaltyPolicy The address of the royalty policy
    /// @return isWhitelisted True if the royalty policy is whitelisted
    function isWhitelistedRoyaltyPolicy(address royaltyPolicy) external view returns (bool) {
        return _getRoyaltyModuleStorage().isWhitelistedRoyaltyPolicy[royaltyPolicy];
    }

    /// @notice Indicates if an external royalty policy is registered
    /// @param externalRoyaltyPolicy The address of the external royalty policy
    /// @return isRegistered True if the external royalty policy is registered
    function isRegisteredExternalRoyaltyPolicy(address externalRoyaltyPolicy) external view returns (bool) {
        return _getRoyaltyModuleStorage().isRegisteredExternalRoyaltyPolicy[externalRoyaltyPolicy];
    }

    /// @notice Indicates if a royalty token is whitelisted
    /// @param token The address of the royalty token
    /// @return isWhitelisted True if the royalty token is whitelisted
    function isWhitelistedRoyaltyToken(address token) external view returns (bool) {
        return _getRoyaltyModuleStorage().isWhitelistedRoyaltyToken[token];
    }

    /// @notice Returns the maximum number of parents an IP asset can have
    function maxParents() external view returns (uint256) {
        return _getRoyaltyModuleStorage().maxParents;
    }

    /// @notice Returns the maximum number of ancestors an IP asset can have
    function maxAncestors() external view returns (uint256) {
        return _getRoyaltyModuleStorage().maxAncestors;
    }

    /// @notice Returns the maximum number of accumulated royalty policies an IP asset can have
    function maxAccumulatedRoyaltyPolicies() external view returns (uint256) {
        return _getRoyaltyModuleStorage().maxAccumulatedRoyaltyPolicies;
    }

    /// @notice Indicates the royalty vault for a given IP asset
    /// @param ipId The ID of IP asset
    function ipRoyaltyVaults(address ipId) external view returns (address) {
        return _getRoyaltyModuleStorage().ipRoyaltyVaults[ipId];
    }

    /// @notice Returns the accumulated royalty policies for a given IP asset
    /// @param ipId The ID of IP asset
    function accumulatedRoyaltyPolicies(address ipId) external view returns (address[] memory) {
        return _getRoyaltyModuleStorage().accumulatedRoyaltyPolicies[ipId].values();
    }

    /// @notice IERC165 interface support
    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseModule, IERC165) returns (bool) {
        return interfaceId == type(IRoyaltyModule).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Deploys a new ipRoyaltyVault for the given ipId
    /// @param ipId The ID of IP asset
    /// @param receiver The address of the receiver
    /// @return The address of the deployed ipRoyaltyVault
    function _deployIpRoyaltyVault(address ipId, address receiver) internal returns (address) {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();

        address ipRoyaltyVault = address(new BeaconProxy(ipRoyaltyVaultBeacon(), ""));
        IIpRoyaltyVault(ipRoyaltyVault).initialize("Royalty Token", "RT", TOTAL_RT_SUPPLY, ipId, receiver);
        $.ipRoyaltyVaults[ipId] = ipRoyaltyVault;

        return ipRoyaltyVault;
    }

    /// @notice Distributes royalty tokens to the royalty policies of the ancestors IP assets
    /// @param ipId The ID of the IP asset
    /// @param parentIpIds The parent IP assets
    /// @param licenseRoyaltyPolicies The royalty policies of the each parent license
    /// @param licensesPercent The license percentage of the licenses being minted
    /// @param ipRoyaltyVault The address of the ipRoyaltyVault
    function _distributeRoyaltyTokensToPolicies(
        address ipId,
        address[] calldata parentIpIds,
        address[] calldata licenseRoyaltyPolicies,
        uint32[] calldata licensesPercent,
        address ipRoyaltyVault
    ) internal {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();

        uint32 totalRtsRequiredToLink;
        for (uint256 i = 0; i < parentIpIds.length; i++) {
            if (parentIpIds[i] == address(0)) revert Errors.RoyaltyModule__ZeroParentIpId();
            if (licenseRoyaltyPolicies[i] == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyPolicy();
            _addToAccumulatedRoyaltyPolicies(parentIpIds[i], licenseRoyaltyPolicies[i]);
            address[] memory accParentRoyaltyPolicies = $.accumulatedRoyaltyPolicies[parentIpIds[i]].values();
            for (uint256 j = 0; j < accParentRoyaltyPolicies.length; j++) {
                // add the parent ancestor royalty policies to the child
                _addToAccumulatedRoyaltyPolicies(ipId, accParentRoyaltyPolicies[j]);
                // transfer the required royalty tokens to each policy
                uint32 licensePercent = accParentRoyaltyPolicies[j] == licenseRoyaltyPolicies[i]
                    ? licensesPercent[i]
                    : 0;
                uint32 rtsRequiredToLink = IRoyaltyPolicy(accParentRoyaltyPolicies[j]).rtsRequiredToLink(
                    parentIpIds[i],
                    licensePercent
                );
                totalRtsRequiredToLink += rtsRequiredToLink;
                if (totalRtsRequiredToLink > TOTAL_RT_SUPPLY)
                    revert Errors.RoyaltyModule__AboveRoyaltyTokenSupplyLimit();
                IERC20(ipRoyaltyVault).safeTransfer(accParentRoyaltyPolicies[j], rtsRequiredToLink);
            }
        }

        if ($.accumulatedRoyaltyPolicies[ipId].length() > $.maxAccumulatedRoyaltyPolicies)
            revert Errors.RoyaltyModule__AboveAccumulatedRoyaltyPoliciesLimit();

        // sends remaining royalty tokens to the ipId address or
        // in the case the ipId is a group then send to the group reward pool
        address receiver = IP_ASSET_REGISTRY.isRegisteredGroup(ipId)
            ? IP_ASSET_REGISTRY.getGroupRewardPool(ipId)
            : ipId;
        IERC20(ipRoyaltyVault).safeTransfer(receiver, TOTAL_RT_SUPPLY - totalRtsRequiredToLink);
    }

    /// @notice Adds a royalty policy to the accumulated royalty policies of an IP asset
    /// @dev Function required to avoid stack too deep error
    /// @param ipId The ID of the IP asset
    /// @param royaltyPolicy The address of the royalty policy
    function _addToAccumulatedRoyaltyPolicies(address ipId, address royaltyPolicy) internal {
        _getRoyaltyModuleStorage().accumulatedRoyaltyPolicies[ipId].add(royaltyPolicy);
    }

    /// @notice Pays the royalty to the receiver vault
    /// @param receiverIpId The ID of the IP asset that receives the royalties
    /// @param payerAddress The address that pays the royalties
    /// @param token The token to use to pay the royalties
    /// @param amount The amount to pay
    function _payToReceiverVault(address receiverIpId, address payerAddress, address token, uint256 amount) internal {
        RoyaltyModuleStorage storage $ = _getRoyaltyModuleStorage();

        if (amount == 0) revert Errors.RoyaltyModule__ZeroAmount();

        address receiverVault = $.ipRoyaltyVaults[receiverIpId];
        if (receiverVault == address(0)) revert Errors.RoyaltyModule__ZeroReceiverVault();

        IIpRoyaltyVault(receiverVault).addIpRoyaltyVaultTokens(token);
        IERC20(token).safeTransferFrom(payerAddress, receiverVault, amount);
    }

    /// @notice Returns the count of ancestors for the given IP asset
    /// @param ipId The ID of the IP asset
    /// @return The number of ancestors
    function _getAncestorCount(address ipId) internal returns (uint256) {
        (bool success, bytes memory returnData) = IP_GRAPH.call(
            abi.encodeWithSignature("getAncestorIpsCount(address)", ipId)
        );
        require(success, "Call failed");
        return abi.decode(returnData, (uint256));
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    /// @dev Returns the storage struct of RoyaltyModule
    function _getRoyaltyModuleStorage() private pure returns (RoyaltyModuleStorage storage $) {
        assembly {
            $.slot := RoyaltyModuleStorageLocation
        }
    }
}
