// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contracts
import { IpRoyaltyVault } from "../../../../contracts/modules/royalty/policies/IpRoyaltyVault.sol";
// solhint-disable-next-line max-line-length
import { IIpRoyaltyVault } from "../../../../contracts/interfaces/modules/royalty/policies/IIpRoyaltyVault.sol";
import { Errors } from "../../../../contracts/lib/Errors.sol";

// tests
import { BaseTest } from "../../utils/BaseTest.t.sol";

contract TestIpRoyaltyVault is BaseTest {
    function setUp() public override {
        super.setUp();

        vm.startPrank(u.admin);
        royaltyModule.whitelistRoyaltyToken(address(LINK), true);
        vm.stopPrank();
    }

    function test_IpRoyaltyVault_decimals() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(2), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(2)));
        vm.stopPrank();

        assertEq(ipRoyaltyVault.decimals(), 6);
    }

    function test_IpRoyaltyVault_updateVaultBalance_revert_NotRoyaltyModule() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.expectRevert(Errors.IpRoyaltyVault__NotAllowedToAddTokenToVault.selector);
        ipRoyaltyVault.updateVaultBalance(address(USDC), 1);
    }

    function test_IpRoyaltyVault_updateVaultBalance_revert_NotWhitelistedRoyaltyToken() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.startPrank(address(royaltyModule));
        vm.expectRevert(Errors.IpRoyaltyVault__NotWhitelistedRoyaltyToken.selector);
        ipRoyaltyVault.updateVaultBalance(address(0), 1);
        vm.stopPrank();
    }

    function test_IpRoyaltyVault_updateVaultBalance_revert_ZeroAmount() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.startPrank(address(royaltyModule));
        vm.expectRevert(Errors.IpRoyaltyVault__ZeroAmount.selector);
        ipRoyaltyVault.updateVaultBalance(address(USDC), 0);
    }

    function test_IpRoyaltyVault_updateVaultBalance() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.startPrank(address(royaltyModule));

        vm.expectEmit(true, true, true, true, address(ipRoyaltyVault));
        emit IIpRoyaltyVault.RevenueTokenAddedToVault(address(USDC), 1);

        ipRoyaltyVault.updateVaultBalance(address(USDC), 1);
        vm.stopPrank();

        assertEq(ipRoyaltyVault.tokens().length, 1);
        assertEq(ipRoyaltyVault.tokens()[0], address(USDC));
    }

    function test_IpRoyaltyVault_constructor_revert_ZeroDisputeModule() public {
        vm.expectRevert(Errors.IpRoyaltyVault__ZeroDisputeModule.selector);
        IpRoyaltyVault vault = new IpRoyaltyVault(
            address(0),
            address(royaltyModule),
            address(licenseRegistry),
            address(groupingModule)
        );
    }

    function test_IpRoyaltyVault_constructor_revert_ZeroRoyaltyModule() public {
        vm.expectRevert(Errors.IpRoyaltyVault__ZeroRoyaltyModule.selector);
        IpRoyaltyVault vault = new IpRoyaltyVault(
            address(disputeModule),
            address(0),
            address(licenseRegistry),
            address(groupingModule)
        );
    }

    function test_IpRoyaltyVault_constructor_revert_ZeroIpAssetRegistry() public {
        vm.expectRevert(Errors.IpRoyaltyVault__ZeroIpAssetRegistry.selector);
        IpRoyaltyVault vault = new IpRoyaltyVault(
            address(disputeModule),
            address(royaltyModule),
            address(0),
            address(groupingModule)
        );
    }

    function test_IpRoyaltyVault_constructor_revert_ZeroGroupingModule() public {
        vm.expectRevert(Errors.IpRoyaltyVault__ZeroGroupingModule.selector);
        IpRoyaltyVault vault = new IpRoyaltyVault(
            address(disputeModule),
            address(royaltyModule),
            address(licenseRegistry),
            address(0)
        );
    }

    function test_IpRoyaltyVault_constructor() public {
        IpRoyaltyVault vault = new IpRoyaltyVault(
            address(disputeModule),
            address(royaltyModule),
            address(licenseRegistry),
            address(groupingModule)
        );
        assertEq(address(vault.DISPUTE_MODULE()), address(disputeModule));
        assertEq(address(vault.ROYALTY_MODULE()), address(royaltyModule));
        assertEq(address(vault.IP_ASSET_REGISTRY()), address(licenseRegistry));
        assertEq(address(vault.GROUPING_MODULE()), address(groupingModule));
    }

    function test_IpRoyaltyVault_initialize() public {
        // mint license for IP80
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(80), address(royaltyPolicyLRP), uint32(10 * 10 ** 6), "");

        address ipRoyaltyVault = royaltyModule.ipRoyaltyVaults(address(80));

        uint256 ipId80IpIdBalance = IERC20(ipRoyaltyVault).balanceOf(address(80));

        assertEq(ERC20(ipRoyaltyVault).name(), "Royalty Token");
        assertEq(ERC20(ipRoyaltyVault).symbol(), "RT");
        assertEq(ERC20(ipRoyaltyVault).totalSupply(), royaltyModule.maxPercent());
        assertEq(IIpRoyaltyVault(ipRoyaltyVault).ipId(), address(80));
        assertEq(ipId80IpIdBalance, royaltyModule.maxPercent());
    }

    function test_IpRoyaltyVault_claimRevenue() public {
        // payment is made to vault
        uint256 royaltyAmount = 100000 * 10 ** 6;
        USDC.mint(address(2), royaltyAmount); // 100k USDC
        LINK.mint(address(2), royaltyAmount); // 100k LINK
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(2), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(2)));
        vm.stopPrank();
        vm.startPrank(address(2));
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(USDC), royaltyAmount);
        LINK.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(LINK), royaltyAmount);
        vm.stopPrank();

        uint256 usdcClaimVaultBefore = USDC.balanceOf(address(ipRoyaltyVault));
        uint256 linkClaimVaultBefore = LINK.balanceOf(address(ipRoyaltyVault));

        // users claim all USDC
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        vm.startPrank(address(2));
        ipRoyaltyVault.claimRevenueOnBehalfByTokenBatch(tokens, address(2));
        vm.stopPrank();

        // all USDC was claimed but LINK was not
        assertEq(USDC.balanceOf(address(ipRoyaltyVault)), 0);
        assertEq(LINK.balanceOf(address(ipRoyaltyVault)), linkClaimVaultBefore);
    }

    function test_IpRoyaltyVault_claimRevenue_revert_Paused() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IIpRoyaltyVault ipRoyaltyVault = IIpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.prank(u.admin);
        royaltyModule.pause();

        vm.expectRevert(Errors.IpRoyaltyVault__EnforcedPause.selector);
        ipRoyaltyVault.claimRevenueOnBehalfByTokenBatch(new address[](0), u.admin);
    }

    function test_IpRoyaltyVault_claimableRevenue() public {
        uint256 royaltyAmount = 100 * 10 ** 6;
        address receiverIpId = address(2);
        address payerIpId = address(3);
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(receiverIpId, address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IIpRoyaltyVault ipRoyaltyVault = IIpRoyaltyVault(royaltyModule.ipRoyaltyVaults(receiverIpId));
        vm.stopPrank();

        // send 30% of rts to another address
        address minorityHolder = address(1);
        vm.prank(receiverIpId);
        IERC20(address(ipRoyaltyVault)).transfer(minorityHolder, 30e6);

        // payment is made to vault
        vm.startPrank(payerIpId);
        USDC.mint(payerIpId, royaltyAmount);
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(receiverIpId, payerIpId, address(USDC), royaltyAmount);

        uint256 claimableRevenueIpId = ipRoyaltyVault.claimableRevenue(receiverIpId, address(USDC));
        uint256 claimableRevenueMinHolder = ipRoyaltyVault.claimableRevenue(minorityHolder, address(USDC));
        assertEq(claimableRevenueIpId, (royaltyAmount * 70e6) / 100e6);
        assertEq(claimableRevenueMinHolder, (royaltyAmount * 30e6) / 100e6);
    }

    function test_IpRoyaltyVault_claimRevenueOnBehalfByTokenBatch_revert_VaultsMustClaimAsSelf() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.expectRevert(Errors.IpRoyaltyVault__VaultsMustClaimAsSelf.selector);
        IIpRoyaltyVault(ipRoyaltyVault).claimRevenueOnBehalfByTokenBatch(new address[](0), address(ipRoyaltyVault));
    }

    function test_IpRoyaltyVault_claimRevenueOnBehalfByTokenBatch_revert_GroupPoolMustClaimViaGroupingModule() public {
        address groupId = groupingModule.registerGroup(address(evenSplitGroupPool));
        address rewardPool = ipAssetRegistry.getGroupRewardPool(groupId);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(groupId), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(groupId)));
        vm.stopPrank();

        assertEq(IERC20(address(ipRoyaltyVault)).balanceOf(address(rewardPool)), 100e6);

        vm.expectRevert(Errors.IpRoyaltyVault__GroupPoolMustClaimViaGroupingModule.selector);
        ipRoyaltyVault.claimRevenueOnBehalfByTokenBatch(new address[](0), address(rewardPool));
    }

    function test_IpRoyaltyVault_claimRevenueOnBehalfByTokenBatch_revert_NoClaimableTokens() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.startPrank(address(royaltyModule));
        ipRoyaltyVault.updateVaultBalance(address(USDC), 1);
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        vm.expectRevert(Errors.IpRoyaltyVault__NoClaimableTokens.selector);
        ipRoyaltyVault.claimRevenueOnBehalfByTokenBatch(tokens, u.admin);
    }

    function test_IpRoyaltyVault_claimRevenueOnBehalfByTokenBatch() public {
        // payment is made to vault
        uint256 royaltyAmount = 100000 * 10 ** 6;
        USDC.mint(address(2), royaltyAmount); // 100k USDC
        LINK.mint(address(2), royaltyAmount); // 100k LINK
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(2), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(2)));
        vm.stopPrank();
        vm.startPrank(address(2));
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(USDC), royaltyAmount);
        LINK.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(LINK), royaltyAmount);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(LINK);

        uint256 userUsdcBalanceBefore = USDC.balanceOf(address(2));
        uint256 userLinkBalanceBefore = LINK.balanceOf(address(2));
        uint256 contractUsdcBalanceBefore = USDC.balanceOf(address(ipRoyaltyVault));
        uint256 contractLinkBalanceBefore = LINK.balanceOf(address(ipRoyaltyVault));

        vm.startPrank(address(2));

        uint256 expectedAmount = royaltyAmount;

        vm.expectEmit(true, true, true, true, address(ipRoyaltyVault));
        emit IIpRoyaltyVault.RevenueTokenClaimed(address(2), address(USDC), expectedAmount);
        emit IIpRoyaltyVault.RevenueTokenClaimed(address(2), address(LINK), expectedAmount);

        ipRoyaltyVault.claimRevenueOnBehalfByTokenBatch(tokens, address(2));

        assertEq(USDC.balanceOf(address(2)) - userUsdcBalanceBefore, expectedAmount);
        assertEq(LINK.balanceOf(address(2)) - userLinkBalanceBefore, expectedAmount);
        assertEq(contractUsdcBalanceBefore - USDC.balanceOf(address(ipRoyaltyVault)), expectedAmount);
        assertEq(contractLinkBalanceBefore - LINK.balanceOf(address(ipRoyaltyVault)), expectedAmount);
    }

    function test_IpRoyaltyVault_claimRevenueOnBehalf_GroupPool() public {
        uint256 royaltyAmount = 100000 * 10 ** 6;
        USDC.mint(address(2), royaltyAmount); // 100k USDC

        address groupId = groupingModule.registerGroup(address(evenSplitGroupPool));
        address rewardPool = ipAssetRegistry.getGroupRewardPool(groupId);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(groupId, address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(groupId));
        vm.stopPrank();

        // 1st payment is made to vault
        vm.startPrank(address(2));
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(groupId, address(2), address(USDC), royaltyAmount / 2);

        // 2nt payment is made to vault
        royaltyModule.payRoyaltyOnBehalf(groupId, address(2), address(USDC), royaltyAmount / 2);
        vm.stopPrank();

        uint256 userUsdcBalanceBefore = USDC.balanceOf(rewardPool);
        uint256 contractUsdcBalanceBefore = USDC.balanceOf(address(ipRoyaltyVault));

        uint256 expectedAmount = royaltyAmount;

        vm.expectEmit(true, true, true, true, address(ipRoyaltyVault));
        emit IIpRoyaltyVault.RevenueTokenClaimed(rewardPool, address(USDC), expectedAmount);

        vm.startPrank(address(2));
        groupingModule.collectRoyalties(groupId, address(USDC));

        assertEq(USDC.balanceOf(rewardPool) - userUsdcBalanceBefore, expectedAmount);
        assertEq(contractUsdcBalanceBefore - USDC.balanceOf(address(ipRoyaltyVault)), expectedAmount);
    }

    function test_IpRoyaltyVault_claimByTokenBatchAsSelf_revert_InvalidTargetIpId() public {
        // deploy vault
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(1), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(1)));
        vm.stopPrank();

        vm.expectRevert(Errors.IpRoyaltyVault__InvalidTargetIpId.selector);
        ipRoyaltyVault.claimByTokenBatchAsSelf(new address[](0), address(0));
    }

    function test_IpRoyaltyVault_claimByTokenBatchAsSelf_revert_VaultDoesNotBelongToAnAncestor() public {
        // deploy two vaults and send 30% of rts to another address
        uint256 royaltyAmount = 100000 * 10 ** 6;
        USDC.mint(address(2), royaltyAmount); // 100k USDC
        LINK.mint(address(2), royaltyAmount); // 100k LINK
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(2), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(2)));
        vm.stopPrank();

        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(3), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault3 = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(3)));
        vm.stopPrank();

        vm.prank(address(2));
        IERC20(address(ipRoyaltyVault)).transfer(address(ipRoyaltyVault3), 30e6);
        vm.stopPrank();

        // payment is made to vault
        vm.startPrank(address(2));
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(USDC), royaltyAmount);
        LINK.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(2), address(LINK), royaltyAmount);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(LINK);

        vm.startPrank(address(100));

        uint256 expectedAmount = (royaltyAmount * 30e6) / 100e6;

        vm.expectRevert(Errors.IpRoyaltyVault__VaultDoesNotBelongToAnAncestor.selector);
        ipRoyaltyVault3.claimByTokenBatchAsSelf(tokens, address(2));
    }

    function test_IpRoyaltyVault_claimByTokenBatchAsSelf() public {
        // deploy two vaults and send 30% of rts to another address
        uint256 royaltyAmount = 100000 * 10 ** 6;
        USDC.mint(address(1), royaltyAmount); // 100k USDC
        LINK.mint(address(1), royaltyAmount); // 100k LINK
        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(2), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(2)));
        vm.stopPrank();

        vm.startPrank(address(licensingModule));
        royaltyModule.onLicenseMinting(address(3), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        IpRoyaltyVault ipRoyaltyVault3 = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(address(3)));
        vm.stopPrank();

        vm.prank(address(2));
        IERC20(address(ipRoyaltyVault)).transfer(address(ipRoyaltyVault3), 30e6);
        vm.stopPrank();

        // mock parent-child relationship
        address[] memory parents = new address[](1);
        parents[0] = address(3);
        ipGraph.addParentIp(address(2), parents);

        // payment is made to vault
        vm.startPrank(address(1));
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(1), address(USDC), royaltyAmount);
        LINK.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(address(2), address(1), address(LINK), royaltyAmount);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(LINK);

        uint256 claimerUsdcBalanceBefore = USDC.balanceOf(address(ipRoyaltyVault3));
        uint256 claimerLinkBalanceBefore = LINK.balanceOf(address(ipRoyaltyVault3));
        //uint256 claimedUsdcBalanceBefore = USDC.balanceOf(address(ipRoyaltyVault));
        uint256 claimedLinkBalanceBefore = LINK.balanceOf(address(ipRoyaltyVault));
        //uint256 usdcClaimVaultBefore = ipRoyaltyVault.claimVaultAmount(address(USDC));
        //uint256 usdcPendingVaultBefore = ipRoyaltyVault3.pendingVaultAmount(address(USDC));

        vm.startPrank(address(100));

        uint256 expectedAmount = (royaltyAmount * 30e6) / 100e6;

        vm.expectEmit(true, true, true, true, address(ipRoyaltyVault));
        emit IIpRoyaltyVault.RevenueTokenClaimed(address(ipRoyaltyVault3), address(USDC), expectedAmount);

        vm.expectEmit(true, true, true, true, address(ipRoyaltyVault));
        emit IIpRoyaltyVault.RevenueTokenClaimed(address(ipRoyaltyVault3), address(LINK), expectedAmount);

        ipRoyaltyVault3.claimByTokenBatchAsSelf(tokens, address(2));

        assertEq(USDC.balanceOf(address(ipRoyaltyVault3)) - claimerUsdcBalanceBefore, expectedAmount);
        assertEq(LINK.balanceOf(address(ipRoyaltyVault3)) - claimerLinkBalanceBefore, expectedAmount);
        //assertEq(claimedUsdcBalanceBefore - USDC.balanceOf(address(ipRoyaltyVault)), expectedAmount);
        assertEq(claimedLinkBalanceBefore - LINK.balanceOf(address(ipRoyaltyVault)), expectedAmount);
        //assertEq(usdcClaimVaultBefore - ipRoyaltyVault.claimVaultAmount(address(USDC)), expectedAmount);
        //assertEq(ipRoyaltyVault.isClaimedAtSnapshot(1, address(ipRoyaltyVault3), address(USDC)), true);
        //assertEq(ipRoyaltyVault3.pendingVaultAmount(address(USDC)) - usdcPendingVaultBefore, expectedAmount);
    }
}
