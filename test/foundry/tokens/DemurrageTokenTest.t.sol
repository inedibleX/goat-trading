// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console2} from "forge-std/console2.sol";
import {BaseTokenTest, DemurrageToken, TokenFactory} from "./BaseTokenTest.t.sol";

import {TokenType, TokenErrors} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";

// Demurrage:
// 1. Tokens decay at the correct rate
// 2. Balance returns correctly
// 3. safeHavens don't decay
// 4. Updates occur correctly
// 5. Privileged

// windUp() slowly starts us special functionality, such as if a demurrage token is being switched to
// windDown() slowly winds down a token, such as if a lottery pot needs to be won
// Need to somehow make sure extra balances are saved. Probably need a function on every contract
// to call to other function on other contracts like getReward()
// maybe things like vault eth and lottery will wind down by buying tokens on the market and distributing?
// Probably want to decide on a final "clean" state that all tokens should get to
// Ya, don't have people calling old functions but rather have a constant taxshare system where we can clean slate
// with dividends, lottery, vaults

contract DemurrageTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Demurrage Token";
    string private constant tokenSymbol = "DMT";

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenErrors.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.DEMURRAGE, 1e12, initParams
        );

        demurrage = DemurrageToken(token);
        pair = pool;
    }
    // Transfers are the only specific functionality of demurrage so we don't need other tests.

    function testDemurrageInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(demurrage.owner(), users.owner);
        assertEq(demurrage.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(demurrage.balanceOf(pair), bootstrapTokenAmount);

        assertEq(demurrage.totalSupply(), totalSupply);
        assertEq(demurrage.name(), tokenName);
        assertEq(demurrage.symbol(), tokenSymbol);
        assertEq(demurrage.safeHavens(pair), true);
    }

    function testDemurrageUpdatesOnTransfer() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        demurrage.transfer(users.bob, 250e18);
        vm.stopPrank();
        console2.log("********************** Bob bal: ", demurrage.balanceOf(users.bob));
        uint256 elapsed = 1 days;
        vm.warp(block.timestamp + elapsed);
        console2.log(
            "***************** Bob bal after 1 days by just forwarding timestamp: ", demurrage.balanceOf(users.bob)
        );

        console2.log("\n******************** Transfer 100e18 tokens from Bob to Alice *********************");
        vm.startPrank(users.bob);
        demurrage.transfer(users.alice, 100e18);
        vm.stopPrank();

        console2.log("\n********************** Balance Check of bob and alice after transfer *********************");

        uint256 balanceOfBob = demurrage.balanceOf(users.bob);
        uint256 balanceOfAlice = demurrage.balanceOf(users.alice);
        uint256 balanceOfBeneficiary = demurrage.balanceOf(demurrage.beneficiary());

        console2.log("balanceOfBob: %e", balanceOfBob);
        console2.log("balanceOfAlice: %e", balanceOfAlice);

        console2.log("balance beneficiary: %e \n", balanceOfBeneficiary);

        uint256 expectedCumuDecay = elapsed * 250e18;
        uint256 expectedCumuPaid = 250e18 * 1e12 * elapsed / 1e18;

        assertEq(demurrage.lastGlobalUpdate(), block.timestamp);
        assertEq(demurrage.cumulativeDecaying(), expectedCumuDecay);

        assertEq(demurrage.lastUserUpdate(users.bob), block.timestamp);
        assertEq(demurrage.lastUserUpdate(users.alice), block.timestamp);

        assertEq(demurrage.lastUserDecaying(users.bob), expectedCumuDecay);
        assertEq(demurrage.lastUserDecaying(users.bob), expectedCumuDecay);

        assertEq(demurrage.cumulativeTokensPaid(), expectedCumuPaid);
        assertEq(demurrage.lastUserTokensPaid(users.bob), demurrage.cumulativeTokensPaid());
        assertEq(demurrage.lastUserTokensPaid(users.alice), demurrage.cumulativeTokensPaid());

        console2.log("\n********************** Fast forward by 1 day *********************");
        vm.warp(block.timestamp + elapsed);

        balanceOfBob = demurrage.balanceOf(users.bob);
        balanceOfAlice = demurrage.balanceOf(users.alice);
        balanceOfBeneficiary = demurrage.balanceOf(demurrage.beneficiary());

        console2.log("balanceOfBob: %e", balanceOfBob);
        console2.log("balanceOfAlice: %e", balanceOfAlice);

        console2.log("balance beneficiary: %e", balanceOfBeneficiary);
    }
}
