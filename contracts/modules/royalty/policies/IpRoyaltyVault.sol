// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/security/ReentrancyGuardUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ERC20SnapshotUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/IERC20Upgradeable.sol";

import { IRoyaltyPolicyLAP } from "../../../interfaces/modules/royalty/policies/IRoyaltyPolicyLAP.sol";
import { IDisputeModule } from "../../../interfaces/modules/dispute/IDisputeModule.sol";
import { IIpRoyaltyVault } from "../../../interfaces/modules/royalty/policies/IIpRoyaltyVault.sol";
import { ArrayUtils } from "../../../lib/ArrayUtils.sol";
import { Errors } from "../../../lib/Errors.sol";

/// @title Ip Royalty Vault
/// @notice Defines the logic for claiming royalty tokens and revenue tokens for a given IP
contract IpRoyaltyVault is IIpRoyaltyVault, ERC20SnapshotUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice LAP royalty policy address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRoyaltyPolicyLAP public immutable ROYALTY_POLICY_LAP;

    /// @notice Dispute module address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDisputeModule public immutable DISPUTE_MODULE;

    /// @notice Ip id to whom this royalty vault belongs to
    address public ipId;

    /// @notice Amount of unclaimed royalty tokens
    uint32 public unclaimedRoyaltyTokens;

    /// @notice Last snapshotted timestamp
    uint256 public lastSnapshotTimestamp;

    /// @notice Amount of revenue token in the ancestors vault
    mapping(address token => uint256 amount) public ancestorsVaultAmount;

    /// @notice Indicates if a given ancestor address has already claimed
    mapping(address ancestorIpId => bool) public isClaimedByAncestor;

    /// @notice Amount of revenue token in the claim vault
    mapping(address token => uint256 amount) public claimVaultAmount;

    /// @notice Amount of tokens claimable at a given snapshot
    mapping(uint256 snapshotId => mapping(address token => uint256 amount)) public claimableAtSnapshot;

    /// @notice Amount of unclaimed tokens at the snapshot
    mapping(uint256 snapshotId => uint32 tokenAmount) public unclaimedAtSnapshot;

    /// @notice Indicates whether the claimer has claimed the revenue tokens at a given snapshot
    mapping(uint256 snapshotId => mapping(address claimer => mapping(address token => bool)))
        public isClaimedAtSnapshot;

    /// @notice Royalty tokens of the vault
    EnumerableSet.AddressSet private _tokens;

    /// @notice Constructor
    /// @param royaltyPolicyLAP The address of the royalty policy LAP
    /// @param disputeModule The address of the dispute module
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address royaltyPolicyLAP, address disputeModule) {
        if (royaltyPolicyLAP == address(0)) revert Errors.IpRoyaltyVault__ZeroRoyaltyPolicyLAP();
        if (disputeModule == address(0)) revert Errors.IpRoyaltyVault__ZeroDisputeModule();

        ROYALTY_POLICY_LAP = IRoyaltyPolicyLAP(royaltyPolicyLAP);
        DISPUTE_MODULE = IDisputeModule(disputeModule);

        _disableInitializers();
    }

    // TODO: adjust/review for upgradeability
    /// @notice Initializer for this implementation contract
    /// @param name The name of the royalty token
    /// @param symbol The symbol of the royalty token
    /// @param supply The total supply of the royalty token
    /// @param unclaimedTokens The amount of unclaimed royalty tokens reserved for ancestors
    /// @param ipIdAddress The ip id the royalty vault belongs to
    function initialize(
        string memory name,
        string memory symbol,
        uint32 supply,
        uint32 unclaimedTokens,
        address ipIdAddress
    ) external initializer {
        if (ipIdAddress == address(0)) revert Errors.IpRoyaltyVault__ZeroIpId();

        ipId = ipIdAddress;
        lastSnapshotTimestamp = block.timestamp;
        unclaimedRoyaltyTokens = unclaimedTokens;

        _mint(address(this), unclaimedTokens);
        _mint(ipIdAddress, supply - unclaimedTokens);

        __ReentrancyGuard_init();
        __ERC20Snapshot_init();
        __ERC20_init(name, symbol);
    }

    /// @notice Adds a new revenue token to the vault
    /// @param token The address of the revenue token
    /// @dev Only callable by the royalty policy LAP
    function addIpRoyaltyVaultTokens(address token) external {
        if (msg.sender != address(ROYALTY_POLICY_LAP)) revert Errors.IpRoyaltyVault__NotRoyaltyPolicyLAP();
        _tokens.add(token);
    }

    /// @notice Snapshots the claimable revenue and royalty token amounts
    /// @return snapshotId The snapshot id
    function snapshot() external returns (uint256) {
        if (block.timestamp - lastSnapshotTimestamp < ROYALTY_POLICY_LAP.getSnapshotInterval())
            revert Errors.IpRoyaltyVault__SnapshotIntervalTooShort();

        uint256 snapshotId = _snapshot();
        lastSnapshotTimestamp = block.timestamp;

        uint32 unclaimedTokens = unclaimedRoyaltyTokens;
        unclaimedAtSnapshot[snapshotId] = unclaimedTokens;

        address[] memory tokens = _tokens.values();

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
            if (tokenBalance == 0) {
                _tokens.remove(tokens[i]);
                continue;
            }

            uint256 newRevenue = tokenBalance - claimVaultAmount[tokens[i]] - ancestorsVaultAmount[tokens[i]];
            if (newRevenue == 0) continue;

            uint256 ancestorsTokens = (newRevenue * unclaimedTokens) / totalSupply();
            ancestorsVaultAmount[tokens[i]] += ancestorsTokens;

            uint256 claimableTokens = newRevenue - ancestorsTokens;
            claimableAtSnapshot[snapshotId][tokens[i]] = claimableTokens;
            claimVaultAmount[tokens[i]] += claimableTokens;
        }

        emit SnapshotCompleted(snapshotId, block.timestamp, unclaimedTokens);

        return snapshotId;
    }

    /// @notice Calculates the amount of revenue token claimable by a token holder at certain snapshot
    /// @param account The address of the token holder
    /// @param snapshotId The snapshot id
    /// @param token The revenue token to claim
    /// @return The amount of revenue token claimable
    function claimableRevenue(address account, uint256 snapshotId, address token) external view returns (uint256) {
        return _claimableRevenue(account, snapshotId, token);
    }

    /// @notice Allows token holders to claim revenue token based on the token balance at certain snapshot
    /// @param snapshotId The snapshot id
    /// @param tokens The list of revenue tokens to claim
    function claimRevenueByTokenBatch(uint256 snapshotId, address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 claimableToken = _claimableRevenue(msg.sender, snapshotId, tokens[i]);
            if (claimableToken == 0) continue;

            isClaimedAtSnapshot[snapshotId][msg.sender][tokens[i]] = true;
            claimVaultAmount[tokens[i]] -= claimableToken;
            IERC20Upgradeable(tokens[i]).safeTransfer(msg.sender, claimableToken);

            emit RevenueTokenClaimed(msg.sender, tokens[i], claimableToken);
        }
    }

    /// @notice Allows token holders to claim by a list of snapshot ids based on the token balance at certain snapshot
    /// @param snapshotIds The list of snapshot ids
    /// @param token The revenue token to claim
    function claimRevenueBySnapshotBatch(uint256[] memory snapshotIds, address token) external {
        uint256 claimableToken;
        for (uint256 i = 0; i < snapshotIds.length; i++) {
            claimableToken += _claimableRevenue(msg.sender, snapshotIds[i], token);
            isClaimedAtSnapshot[snapshotIds[i]][msg.sender][token] = true;
        }

        claimVaultAmount[token] -= claimableToken;
        IERC20Upgradeable(token).safeTransfer(msg.sender, claimableToken);

        emit RevenueTokenClaimed(msg.sender, token, claimableToken);
    }

    /// @notice Allows ancestors to claim the royalty tokens and any accrued revenue tokens
    /// @param ancestorIpId The ip id of the ancestor to whom the royalty tokens belong to
    function collectRoyaltyTokens(address ancestorIpId) external nonReentrant {
        (, , , address[] memory ancestors, uint32[] memory ancestorsRoyalties) = ROYALTY_POLICY_LAP.getRoyaltyData(
            ipId
        );

        if (DISPUTE_MODULE.isIpTagged(ipId)) revert Errors.IpRoyaltyVault__IpTagged();
        if (isClaimedByAncestor[ancestorIpId]) revert Errors.IpRoyaltyVault__AlreadyClaimed();

        // check if the address being claimed to is an ancestor
        (uint32 index, bool isIn) = ArrayUtils.indexOf(ancestors, ancestorIpId);
        if (!isIn) revert Errors.IpRoyaltyVault__ClaimerNotAnAncestor();

        // transfer royalty tokens to the ancestor
        IERC20Upgradeable(address(this)).safeTransfer(ancestorIpId, ancestorsRoyalties[index]);

        // collect accrued revenue tokens (if any)
        _collectAccruedTokens(ancestorsRoyalties[index], ancestorIpId);

        isClaimedByAncestor[ancestorIpId] = true;
        unclaimedRoyaltyTokens -= ancestorsRoyalties[index];

        emit RoyaltyTokensCollected(ancestorIpId, ancestorsRoyalties[index]);
    }

    /// @notice Returns the list of revenue tokens in the vault
    /// @return The list of revenue tokens
    function getVaultTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    /// @notice A function to calculate the amount of revenue token claimable by a token holder at certain snapshot
    /// @param account The address of the token holder
    /// @param snapshotId The snapshot id
    /// @param token The revenue token to claim
    /// @return The amount of revenue token claimable
    function _claimableRevenue(address account, uint256 snapshotId, address token) internal view returns (uint256) {
        // if the ip is tagged, then the unclaimed royalties are lost
        if (DISPUTE_MODULE.isIpTagged(ipId)) return 0;

        uint256 balance = balanceOfAt(account, snapshotId);
        uint256 totalSupply = totalSupplyAt(snapshotId) - unclaimedAtSnapshot[snapshotId];
        uint256 claimableToken = claimableAtSnapshot[snapshotId][token];
        return isClaimedAtSnapshot[snapshotId][account][token] ? 0 : (balance * claimableToken) / totalSupply;
    }

    /// @dev Collect the accrued tokens (if any)
    /// @param royaltyTokensToClaim The amount of royalty tokens being claimed by the ancestor
    /// @param ancestorIpId The ip id of the ancestor to whom the royalty tokens belong to
    function _collectAccruedTokens(uint256 royaltyTokensToClaim, address ancestorIpId) internal {
        address[] memory tokens = _tokens.values();

        for (uint256 i = 0; i < tokens.length; ++i) {
            // the only case in which unclaimedRoyaltyTokens can be 0 is when the vault is empty and everyone claimed
            // in which case the call will revert upstream with IpRoyaltyVault__AlreadyClaimed error
            uint256 collectAmount = (ancestorsVaultAmount[tokens[i]] * royaltyTokensToClaim) / unclaimedRoyaltyTokens;
            if (collectAmount == 0) continue;

            ancestorsVaultAmount[tokens[i]] -= collectAmount;
            IERC20Upgradeable(tokens[i]).safeTransfer(ancestorIpId, collectAmount);

            emit RevenueTokenClaimed(ancestorIpId, tokens[i], collectAmount);
        }
    }
}
