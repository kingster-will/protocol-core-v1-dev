// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// external
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// contracts
import { Errors } from "../../../../contracts/lib/Errors.sol";
import { IGroupingModule } from "../../../../contracts/interfaces/modules/grouping/IGroupingModule.sol";
import { PILFlavors } from "../../../../contracts/lib/PILFlavors.sol";
// test
import { MockEvenSplitGroupPool } from "../../mocks/grouping/MockEvenSplitGroupPool.sol";
import { MockERC721 } from "../../mocks/token/MockERC721.sol";
import { BaseTest } from "../../utils/BaseTest.t.sol";

contract GroupingModuleTest is BaseTest {
    // test register group
    // test add ip to group
    // test remove ip from group
    // test claim reward
    // test get claimable reward
    // test make derivative of group ipa
    // test recursive group ipa
    // test remove ipa from group ipa which has derivative
    using Strings for *;

    error ERC721NonexistentToken(uint256 tokenId);

    MockERC721 internal mockNft = new MockERC721("MockERC721");
    MockERC721 internal gatedNftFoo = new MockERC721{ salt: bytes32(uint256(1)) }("GatedNftFoo");
    MockERC721 internal gatedNftBar = new MockERC721{ salt: bytes32(uint256(2)) }("GatedNftBar");

    address public ipId1;
    address public ipId2;
    address public ipId3;
    address public ipId5;
    address public ipOwner1 = address(0x111);
    address public ipOwner2 = address(0x222);
    address public ipOwner3 = address(0x333);
    address public ipOwner5 = address(0x444);
    uint256 public tokenId1 = 1;
    uint256 public tokenId2 = 2;
    uint256 public tokenId3 = 3;
    uint256 public tokenId5 = 5;

    MockEvenSplitGroupPool public rewardPool;

    function setUp() public override {
        super.setUp();
        // Create IPAccounts
        mockNft.mintId(ipOwner1, tokenId1);
        mockNft.mintId(ipOwner2, tokenId2);
        mockNft.mintId(ipOwner3, tokenId3);
        mockNft.mintId(ipOwner5, tokenId5);

        ipId1 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId1);
        ipId2 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId2);
        ipId3 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId3);
        ipId5 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId5);

        vm.label(ipId1, "IPAccount1");
        vm.label(ipId2, "IPAccount2");
        vm.label(ipId3, "IPAccount3");
        vm.label(ipId5, "IPAccount5");

        rewardPool = new MockEvenSplitGroupPool();
        vm.prank(admin);
        groupingModule.whitelistGroupRewardPool(address(rewardPool));
    }

    function test_registerGroup() public {
        address expectedGroupId = ipAssetRegistry.ipId(block.chainid, address(groupNft), 0);
        vm.expectEmit();
        emit IGroupingModule.IPGroupRegistered(expectedGroupId, address(rewardPool));
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        assertEq(groupId, expectedGroupId);
        assertEq(ipAssetRegistry.getGroupRewardPool(groupId), address(rewardPool));
        assertEq(ipAssetRegistry.isRegisteredGroup(groupId), true);
        assertEq(ipAssetRegistry.totalMembers(groupId), 0);
    }

    function test_addIp() public {
        vm.warp(100);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        groupingModule.addIp(groupId, ipIds);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.totalMemberIPs(groupId), 2);
        assertEq(rewardPool.ipAddedTime(groupId, ipId1), 100);
    }

    function test_addIp_later_after_depositedReward() public {
        vm.warp(9999);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        groupingModule.addIp(groupId, ipIds);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.totalMemberIPs(groupId), 2);
        assertEq(rewardPool.ipAddedTime(groupId, ipId1), 9999);

        erc20.mint(alice, 100);
        erc20.approve(address(rewardPool), 100);
        rewardPool.depositReward(groupId, address(erc20), 100);

        vm.warp(10000);
        address[] memory ipIds2 = new address[](1);
        ipIds2[0] = ipId3;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds2);
        groupingModule.addIp(groupId, ipIds2);
        assertEq(ipAssetRegistry.totalMembers(groupId), 3);
        assertEq(rewardPool.totalMemberIPs(groupId), 3);
        assertEq(rewardPool.ipAddedTime(groupId, ipId3), 10000);
        (uint256 startPoolBalance, uint256 rewardDebt) = rewardPool.ipRewardInfo(groupId, address(erc20), ipId3);
        assertEq(startPoolBalance, 100);
        assertEq(rewardDebt, 0);

        (startPoolBalance, rewardDebt) = rewardPool.ipRewardInfo(groupId, address(erc20), ipId1);
        assertEq(startPoolBalance, 0);
        assertEq(rewardDebt, 0);

        (startPoolBalance, rewardDebt) = rewardPool.ipRewardInfo(groupId, address(erc20), ipId2);
        assertEq(startPoolBalance, 0);
        assertEq(rewardDebt, 0);
    }

    function test_removeIp() public {
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        address[] memory removeIpIds = new address[](1);
        removeIpIds[0] = ipId1;
        vm.expectEmit();
        emit IGroupingModule.RemovedIpFromGroup(groupId, removeIpIds);
        groupingModule.removeIp(groupId, removeIpIds);
    }

    function test_claimReward() public {
        vm.warp(100);
        vm.startPrank(alice);

        address groupId = groupingModule.registerGroup(address(rewardPool));
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.totalMemberIPs(groupId), 2);

        erc20.mint(alice, 100);
        erc20.approve(address(rewardPool), 100);
        rewardPool.depositReward(groupId, address(erc20), 100);
        assertEq(erc20.balanceOf(address(rewardPool)), 100);

        address[] memory claimIpIds = new address[](1);
        claimIpIds[0] = ipId1;

        assertEq(groupingModule.getClaimableReward(groupId, address(erc20), claimIpIds)[0], 50);

        vm.expectEmit();
        emit IGroupingModule.ClaimedReward(groupId, address(erc20), ipId1, 50);
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);
        assertEq(erc20.balanceOf(address(rewardPool)), 50);
        assertEq(erc20.balanceOf(ipId1), 50);
    }

    function test_addIp_after_registerDerivative() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLAP)
            })
        );

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = groupId;
        licenseTermsIds[0] = termsId;

        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "");
        vm.stopPrank();

        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        vm.prank(alice);
        groupingModule.addIp(groupId, ipIds);

        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.totalMemberIPs(groupId), 2);
        assertEq(rewardPool.ipAddedTime(groupId, ipId1), block.timestamp);
    }

    function test_removeIp_revert_after_registerDerivative() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLAP)
            })
        );

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = groupId;
        licenseTermsIds[0] = termsId;

        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "");
        vm.stopPrank();

        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        vm.prank(alice);
        groupingModule.addIp(groupId, ipIds);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.totalMemberIPs(groupId), 2);
        assertEq(rewardPool.ipAddedTime(groupId, ipId1), block.timestamp);

        address[] memory removeIpIds = new address[](1);
        removeIpIds[0] = ipId1;
        vm.expectRevert(abi.encodeWithSelector(Errors.GroupingModule__GroupIPHasDerivativeIps.selector, groupId));
        vm.prank(alice);
        groupingModule.removeIp(groupId, removeIpIds);
    }
}