// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// external
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC6551AccountLib } from "erc6551/lib/ERC6551AccountLib.sol";
// contracts
import { Errors } from "contracts/lib/Errors.sol";
import { ArbitrationPolicySP } from "contracts/modules/dispute/policies/ArbitrationPolicySP.sol";
// test
import { BaseTest } from "test/foundry/utils/BaseTest.t.sol";
import { TestProxyHelper } from "test/foundry/utils/TestProxyHelper.sol";

contract TestArbitrationPolicySP is BaseTest {
    event GovernanceWithdrew(uint256 amount);

    address internal ipAccount1 = address(0x111000aaa);

    address public ipAddr;
    address internal arbitrationRelayer;

    function setUp() public override {
        super.setUp();

        arbitrationRelayer = u.relayer;

        USDC.mint(ipAccount1, 10000 * 10 ** 6);

        registerSelectedPILicenseTerms_Commercial({
            selectionName: "cheap_flexible",
            transferable: true,
            derivatives: true,
            reciprocal: false,
            commercialRevShare: 10,
            mintingFee: 0
        });

        mockNFT.mintId(u.admin, 0);

        address expectedAddr = ERC6551AccountLib.computeAddress(
            address(erc6551Registry),
            address(ipAccountImpl),
            ipAccountRegistry.IP_ACCOUNT_SALT(),
            block.chainid,
            address(mockNFT),
            0
        );
        vm.label(expectedAddr, "IPAccount0");

        vm.startPrank(u.admin);
        ipAddr = ipAssetRegistry.register(block.chainid, address(mockNFT), 0);

        licensingModule.attachLicenseTerms(ipAddr, address(pilTemplate), getSelectedPILicenseTermsId("cheap_flexible"));

        // set arbitration policy
        vm.startPrank(ipAddr);
        disputeModule.setArbitrationPolicy(ipAddr, address(arbitrationPolicySP));
        vm.stopPrank();
    }

    function test_ArbitrationPolicySP_constructor_ZeroDisputeModule() public {
        address disputeModule = address(0);
        address paymentToken = address(1);
        uint256 arbitrationPrice = 1000;
        address governance = address(3);

        vm.expectRevert(Errors.ArbitrationPolicySP__ZeroDisputeModule.selector);
        // NOTE: Not using proxy since error is thrown in constructor
        new ArbitrationPolicySP(disputeModule, paymentToken, arbitrationPrice);
    }

    function test_ArbitrationPolicySP_constructor_ZeroPaymentToken() public {
        address disputeModule = address(1);
        address paymentToken = address(0);
        uint256 arbitrationPrice = 1000;
        address governance = address(3);

        vm.expectRevert(Errors.ArbitrationPolicySP__ZeroPaymentToken.selector);
        // NOTE: Not using proxy since error is thrown in constructor
        new ArbitrationPolicySP(disputeModule, paymentToken, arbitrationPrice);
    }

    function test_ArbitrationPolicySP_constructor() public {
        address disputeModule = address(1);
        address paymentToken = address(2);
        uint256 arbitrationPrice = 1000;

        // NOTE: Not using proxy since error is thrown in constructor
        ArbitrationPolicySP arbitrationPolicySP = new ArbitrationPolicySP(
            disputeModule,
            paymentToken,
            arbitrationPrice
        );

        assertEq(address(arbitrationPolicySP.DISPUTE_MODULE()), disputeModule);
        assertEq(address(arbitrationPolicySP.PAYMENT_TOKEN()), paymentToken);
        assertEq(arbitrationPolicySP.ARBITRATION_PRICE(), arbitrationPrice);
    }

    function test_ArbitrationPolicySP_initialize_revert_ZeroAccessManager() public {
        address disputeModule = address(1);
        address paymentToken = address(2);
        uint256 arbitrationPrice = 1000;

        address impl = address(new ArbitrationPolicySP(address(disputeModule), paymentToken, arbitrationPrice));

        vm.expectRevert(Errors.ArbitrationPolicySP__ZeroAccessManager.selector);
        arbitrationPolicySP = ArbitrationPolicySP(
            TestProxyHelper.deployUUPSProxy(
                impl,
                abi.encodeCall(ArbitrationPolicySP.initialize, (address(0), TREASURY_ADDRESS))
            )
        );
    }

    function test_ArbitrationPolicySP_initialize_revert_ZeroTreasury() public {
        address disputeModule = address(1);
        address paymentToken = address(2);
        address accessManager = address(3);
        uint256 arbitrationPrice = 1000;

        address impl = address(new ArbitrationPolicySP(address(disputeModule), paymentToken, arbitrationPrice));

        vm.expectRevert(Errors.ArbitrationPolicySP__ZeroTreasury.selector);
        arbitrationPolicySP = ArbitrationPolicySP(
            TestProxyHelper.deployUUPSProxy(
                impl,
                abi.encodeCall(ArbitrationPolicySP.initialize, (accessManager, address(0)))
            )
        );
    }

    function test_ArbitrationPolicySP_setTreasury_revert_ZeroTreasury() public {
        vm.startPrank(u.admin);
        vm.expectRevert(Errors.ArbitrationPolicySP__ZeroTreasury.selector);
        arbitrationPolicySP.setTreasury(address(0));
    }

    function test_ArbitrationPolicySP_setTreasury() public {
        address newTreasuryAddress = address(1);

        vm.startPrank(u.admin);
        assertEq(arbitrationPolicySP.treasury(), TREASURY_ADDRESS);
        arbitrationPolicySP.setTreasury(newTreasuryAddress);
        assertEq(arbitrationPolicySP.treasury(), newTreasuryAddress);
    }

    function test_ArbitrationPolicySP_onRaiseDispute_NotDisputeModule() public {
        vm.expectRevert(Errors.ArbitrationPolicySP__NotDisputeModule.selector);
        arbitrationPolicySP.onRaiseDispute(address(1), new bytes(0));
    }

    function test_ArbitrationPolicySP_onRaiseDispute() public {
        address caller = ipAccount1;
        vm.startPrank(caller);
        USDC.approve(address(arbitrationPolicySP), ARBITRATION_PRICE);
        vm.stopPrank();

        USDC.mint(caller, 10000 * 10 ** 6);

        vm.startPrank(address(disputeModule));

        uint256 userUSDCBalBefore = USDC.balanceOf(caller);
        uint256 arbitrationContractBalBefore = USDC.balanceOf(address(arbitrationPolicySP));

        arbitrationPolicySP.onRaiseDispute(caller, new bytes(0));

        uint256 userUSDCBalAfter = USDC.balanceOf(caller);
        uint256 arbitrationContractBalAfter = USDC.balanceOf(address(arbitrationPolicySP));

        assertEq(userUSDCBalBefore - userUSDCBalAfter, ARBITRATION_PRICE);
        assertEq(arbitrationContractBalAfter - arbitrationContractBalBefore, ARBITRATION_PRICE);
    }

    function test_ArbitrationPolicySP_onDisputeJudgement_NotDisputeModule() public {
        vm.expectRevert(Errors.ArbitrationPolicySP__NotDisputeModule.selector);
        arbitrationPolicySP.onDisputeJudgement(1, true, new bytes(0));
    }

    function test_ArbitrationPolicySP_onDisputeJudgement_True() public {
        // raise dispute
        vm.startPrank(ipAccount1);
        IERC20(USDC).approve(address(arbitrationPolicySP), ARBITRATION_PRICE);
        disputeModule.raiseDispute(ipAddr, string("urlExample"), "PLAGIARISM", "");
        vm.stopPrank();

        // set dispute judgement
        uint256 ipAccount1USDCBalanceBefore = USDC.balanceOf(ipAccount1);
        uint256 arbitrationPolicySPUSDCBalanceBefore = USDC.balanceOf(address(arbitrationPolicySP));

        vm.startPrank(arbitrationRelayer);
        disputeModule.setDisputeJudgement(1, true, "");

        uint256 ipAccount1USDCBalanceAfter = USDC.balanceOf(ipAccount1);
        uint256 arbitrationPolicySPUSDCBalanceAfter = USDC.balanceOf(address(arbitrationPolicySP));

        assertEq(ipAccount1USDCBalanceAfter - ipAccount1USDCBalanceBefore, ARBITRATION_PRICE);
        assertEq(arbitrationPolicySPUSDCBalanceBefore - arbitrationPolicySPUSDCBalanceAfter, ARBITRATION_PRICE);
    }

    function test_ArbitrationPolicySP_onDisputeJudgement_False() public {
        // raise dispute
        vm.startPrank(ipAccount1);
        IERC20(USDC).approve(address(arbitrationPolicySP), ARBITRATION_PRICE);
        disputeModule.raiseDispute(ipAddr, string("urlExample"), "PLAGIARISM", "");
        vm.stopPrank();

        // set dispute judgement
        uint256 ipAccount1USDCBalanceBefore = USDC.balanceOf(ipAccount1);
        uint256 arbitrationPolicySPUSDCBalanceBefore = USDC.balanceOf(address(arbitrationPolicySP));
        uint256 treasuryUSDCBalanceBefore = USDC.balanceOf(TREASURY_ADDRESS);

        vm.startPrank(arbitrationRelayer);
        disputeModule.setDisputeJudgement(1, false, "");

        uint256 ipAccount1USDCBalanceAfter = USDC.balanceOf(ipAccount1);
        uint256 arbitrationPolicySPUSDCBalanceAfter = USDC.balanceOf(address(arbitrationPolicySP));
        uint256 treasuryUSDCBalanceAfter = USDC.balanceOf(TREASURY_ADDRESS);

        assertEq(ipAccount1USDCBalanceAfter - ipAccount1USDCBalanceBefore, 0);
        assertEq(arbitrationPolicySPUSDCBalanceBefore - arbitrationPolicySPUSDCBalanceAfter, ARBITRATION_PRICE);
        assertEq(treasuryUSDCBalanceAfter - treasuryUSDCBalanceBefore, ARBITRATION_PRICE);
    }

    function test_ArbitrationPolicySP_onDisputeCancel_NotDisputeModule() public {
        vm.expectRevert(Errors.ArbitrationPolicySP__NotDisputeModule.selector);
        arbitrationPolicySP.onDisputeCancel(address(1), 1, new bytes(0));
    }
}
