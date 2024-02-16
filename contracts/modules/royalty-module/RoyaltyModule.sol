// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { Governable } from "../../governance/Governable.sol";
import { IRoyaltyModule } from "../../interfaces/modules/royalty/IRoyaltyModule.sol";
import { IRoyaltyPolicy } from "../../interfaces/modules/royalty/policies/IRoyaltyPolicy.sol";
import { Errors } from "../../lib/Errors.sol";
import { ROYALTY_MODULE_KEY } from "../../lib/modules/Module.sol";
import { BaseModule } from "../BaseModule.sol";
import { IIPAccount } from "contracts/interfaces/IIPAccount.sol";
import { IPAccountStorageOps } from "contracts/lib/IPAccountStorageOps.sol";

/// @title Story Protocol Royalty Module
/// @notice The Story Protocol royalty module allows to set royalty policies an ipId
///         and pay royalties as a derivative ip.
contract RoyaltyModule is IRoyaltyModule, Governable, ReentrancyGuard, BaseModule {
    using ERC165Checker for address;
    using IPAccountStorageOps for IIPAccount;

    string public constant override name = ROYALTY_MODULE_KEY;

    /// @notice Indicates the royalty policy for a given ipId
    bytes32 public constant IP_STORAGE_ROYALTY_POLICY = "royaltyPolicy";
    /// @notice Indicates if a royalty policy is immutable
    bytes32 public constant IP_STORAGE_ROYALTY_POLICY_IMMUTABLE = "royaltyPolicyImmutable";

    /// @notice Licensing module address
    address public LICENSING_MODULE;

    /// @notice Indicates if a royalty policy is whitelisted
    mapping(address royaltyPolicy => bool allowed) public isWhitelistedRoyaltyPolicy;

    /// @notice Indicates if a royalty token is whitelisted
    mapping(address token => bool) public isWhitelistedRoyaltyToken;

    /// @notice Constructor
    /// @param _governance The address of the governance contract
    constructor(address _governance) Governable(_governance) {}

    modifier onlyLicensingModule() {
        if (msg.sender != LICENSING_MODULE) revert Errors.RoyaltyModule__NotAllowedCaller();
        _;
    }

    /// @notice Sets the license registry
    /// @param _licensingModule The address of the license registry
    function setLicensingModule(address _licensingModule) external onlyProtocolAdmin {
        if (_licensingModule == address(0)) revert Errors.RoyaltyModule__ZeroLicensingModule();

        LICENSING_MODULE = _licensingModule;
    }

    /// @notice Whitelist a royalty policy
    /// @param _royaltyPolicy The address of the royalty policy
    /// @param _allowed Indicates if the royalty policy is whitelisted or not
    function whitelistRoyaltyPolicy(address _royaltyPolicy, bool _allowed) external onlyProtocolAdmin {
        if (_royaltyPolicy == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyPolicy();

        isWhitelistedRoyaltyPolicy[_royaltyPolicy] = _allowed;

        emit RoyaltyPolicyWhitelistUpdated(_royaltyPolicy, _allowed);
    }

    /// @notice Whitelist a royalty token
    /// @param _token The token address
    /// @param _allowed Indicates if the token is whitelisted or not
    function whitelistRoyaltyToken(address _token, bool _allowed) external onlyProtocolAdmin {
        if (_token == address(0)) revert Errors.RoyaltyModule__ZeroRoyaltyToken();

        isWhitelistedRoyaltyToken[_token] = _allowed;

        emit RoyaltyTokenWhitelistUpdated(_token, _allowed);
    }

    // TODO: Ensure that the ipId that is passed in from license cannot be manipulated
    //       - given ipId addresses are deterministic
    /// @notice Sets the royalty policy for an ipId
    /// @param _ipId The ipId
    /// @param _royaltyPolicy The address of the royalty policy
    /// @param _parentIpIds The parent ipIds
    /// @param _data The data to initialize the policy
    function setRoyaltyPolicy(
        address _ipId,
        address _royaltyPolicy,
        address[] calldata _parentIpIds,
        bytes calldata _data
    ) external nonReentrant onlyLicensingModule {
        if (isRoyaltyPolicyImmutable(_ipId)) revert Errors.RoyaltyModule__AlreadySetRoyaltyPolicy();
        if (!isWhitelistedRoyaltyPolicy[_royaltyPolicy]) revert Errors.RoyaltyModule__NotWhitelistedRoyaltyPolicy();

        if (_parentIpIds.length > 0) _setRoyaltyPolicyImmutable(_ipId, true);

        // the loop below is limited to 100 iterations
        for (uint32 i = 0; i < _parentIpIds.length; i++) {
            if (_getRoyaltyPolicy(_parentIpIds[i]) != _royaltyPolicy)
                revert Errors.RoyaltyModule__IncompatibleRoyaltyPolicy();
            _setRoyaltyPolicyImmutable(_parentIpIds[i], true);
        }

        _setRoyaltyPolicy(_ipId, _royaltyPolicy);

        IRoyaltyPolicy(_royaltyPolicy).initPolicy(_ipId, _parentIpIds, _data);

        emit RoyaltyPolicySet(_ipId, _royaltyPolicy, _data);
    }

    function setRoyaltyPolicyImmutable(address _ipId) external onlyLicensingModule {
        _setRoyaltyPolicyImmutable(_ipId, true);
    }

    function minRoyaltyFromDescendants(address _ipId) external view returns (uint256) {
        address royaltyPolicy = _getRoyaltyPolicy(_ipId);
        if (royaltyPolicy == address(0)) revert Errors.RoyaltyModule__NoRoyaltyPolicySet();

        return IRoyaltyPolicy(royaltyPolicy).minRoyaltyFromDescendants(_ipId);
    }

    /// @notice Allows a sender to to pay royalties on behalf of an ipId
    /// @param _receiverIpId The ipId that receives the royalties
    /// @param _payerIpId The ipId that pays the royalties
    /// @param _token The token to use to pay the royalties
    /// @param _amount The amount to pay
    function payRoyaltyOnBehalf(
        address _receiverIpId,
        address _payerIpId,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        address royaltyPolicy = _getRoyaltyPolicy(_receiverIpId);
        if (royaltyPolicy == address(0)) revert Errors.RoyaltyModule__NoRoyaltyPolicySet();
        if (!isWhitelistedRoyaltyToken[_token]) revert Errors.RoyaltyModule__NotWhitelistedRoyaltyToken();
        if (!isWhitelistedRoyaltyPolicy[royaltyPolicy]) revert Errors.RoyaltyModule__NotWhitelistedRoyaltyPolicy();

        IRoyaltyPolicy(royaltyPolicy).onRoyaltyPayment(msg.sender, _receiverIpId, _token, _amount);

        emit RoyaltyPaid(_receiverIpId, _payerIpId, msg.sender, _token, _amount);
    }

    function royaltyPolicies(address ipId) external view returns (address) {
        return _getRoyaltyPolicy(ipId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseModule, IERC165) returns (bool) {
        return interfaceId == type(IRoyaltyModule).interfaceId || super.supportsInterface(interfaceId);
    }

    function isRoyaltyPolicyImmutable(address ipAccount) public view returns (bool) {
        return IIPAccount(payable(ipAccount)).getBool(IP_STORAGE_ROYALTY_POLICY_IMMUTABLE);
    }

    function _setRoyaltyPolicy(address ipAccount, address royaltyPolicy) internal {
        IIPAccount(payable(ipAccount)).setAddress(IP_STORAGE_ROYALTY_POLICY, royaltyPolicy);
    }

    function _setRoyaltyPolicyImmutable(address ipAccount, bool isImmutable) internal {
        IIPAccount(payable(ipAccount)).setBool(IP_STORAGE_ROYALTY_POLICY_IMMUTABLE, isImmutable);
    }

    function _getRoyaltyPolicy(address ipAccount) internal view returns (address) {
        return IIPAccount(payable(ipAccount)).getAddress(IP_STORAGE_ROYALTY_POLICY);
    }
}
