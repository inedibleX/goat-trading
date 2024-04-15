// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {BaseTokenTest, DemurrageToken, TokenFactory} from "./BaseTokenTest.t.sol";

import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

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
            vm.expectRevert(TokenFactory.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.DEMURRAGE, 1000, initParams
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
    }

    function testDemurrage() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        // Make sure token amounts are updated correctly when transferred (whether that's altered or unaltered).
        _testDemurrageTransfers();
        _testDemurragePrivileged();
    }

    function _testDemurrageTransfers() private {
        // 1. Test transfer from one to another normally and make sure updates are made correctly
        // 2. Test transfer above with safe havens and make sure the same
        // 2. Make sure transfer that is more than the balance completely fails
        // 3. Make sure transfer that is more than the balance only after decay succeeds but only gives balance amount
    }

    function _testDemurragePrivileged() private {
        // 1. Test owner and beneficiary can change what they should change
        // 2. Make sure all variables are change correctly when things are adjusted (such as decay implemented if something is becoming safe haven)
    }
}
