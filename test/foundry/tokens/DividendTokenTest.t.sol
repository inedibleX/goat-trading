// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest, DividendToken, TokenFactory3} from "./BaseTokenTest.t.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract DividendTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Dividend Token";
    string private constant tokenSymbol = "DVT";

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenFactory3.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory3.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.VAULT, 5000, initParams
        );
        dividend = DividendToken(payable(token));
        pair = pool;
    }

    /* *********************************************** Dividend *********************************************** */

    function testDividendInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(dividend.owner(), users.owner);
        assertEq(dividend.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(dividend.balanceOf(pair), bootstrapTokenAmount);

        assertEq(dividend.totalSupply(), totalSupply);
        assertEq(dividend.name(), tokenName);
        assertEq(dividend.symbol(), tokenSymbol);
    }

    function _testDividendFunctionality() private {
        // 1. Make sure dividends can be added
        // 2. Make sure variables update correctly when that happens
        // 3. Make sure dividends update correctly when a transfer occurs
        // 4. Make sure dividends can be withdrawn correctly
    }

    function _testDividendPrivileged() private {
        // 1. test rewarder functionality
    }
}
