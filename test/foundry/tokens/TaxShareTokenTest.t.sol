// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseTokenTest, TokenFactory, TaxShareToken, console2} from "./BaseTokenTest.t.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenType} from "../../../contracts/tokens/TokenFactory2.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";

// Taxshare tokens:
// 1. When taxes occur half go to this and half to rewards
// 2. Rewards are added to balances correctly
// 3. Works correctly with Ether rewards
// 4. Earned and balance work correctly
// 5. Privileged

contract TaxShareTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e22;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Tax Share Token";
    string private constant tokenSymbol = "TST";
    uint256 taxSharePercent = 5000;

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenFactory.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory2.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.TAXSHARE, taxSharePercent, initParams
        );

        taxshare = TaxShareToken(payable(token));

        pair = pool;
    }

    function testTaxShareInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 10000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(taxshare.owner(), users.owner);
        assertEq(taxshare.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(taxshare.balanceOf(pair), bootstrapTokenAmount);

        assertEq(taxshare.totalSupply(), totalSupply);
        assertEq(taxshare.name(), tokenName);
        assertEq(taxshare.symbol(), tokenSymbol);

        assertEq(taxshare.sharePercent(), taxSharePercent);

        assertEq(taxshare.taxed(users.owner), false);
        assertEq(taxshare.buyTax(pair), 100);
        assertEq(taxshare.sellTax(pair), 100);
        assertEq(taxshare.taxed(pair), true);
    }

    function testCreateTaxShareTokenSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 10000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        uint256 pairBalance = taxshare.balanceOf(pair);
        uint256 ownerBalance = taxshare.balanceOf(users.owner);

        uint256 ownerLpBalance = IERC20(pair).balanceOf(users.owner);
        uint256 expectedLpBal = Math.sqrt(uint256(initParams.virtualEth) * initParams.initialTokenMatch) - 1000;

        assertEq(pairBalance, bootstrapTokenAmount, "Pair balance should be equal to bootstrap token amount");
        assertEq(
            ownerBalance,
            totalSupply - bootstrapTokenAmount,
            "Owner balance should be equal to total supply minus bootstrap token amount"
        );
        assertEq(ownerLpBalance, expectedLpBal);

        address treasury = taxshare.treasury();
        address dex = taxshare.dex();
        address owner = taxshare.owner();

        assertEq(treasury, users.owner, "Treasury should be owner");
        assertEq(dex, address(0), "Dex should be address(0)");
        assertEq(owner, users.owner, "Owner should be owner");
    }

    // Test all functionality of TaxShare tokens
    function testTaxShareSellTaxesSuccessWithNecessaryUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 10000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        taxshare.transferTreasury(users.treasury);
        taxshare.changeDex(address(router));
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(router.WETH());
        path[1] = address(taxshare);
        uint256 amountIn = 12e18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        vm.startPrank(users.whale);
        // fund bob with some weth
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.whale, block.timestamp
        );
        vm.stopPrank();

        amountIn = 2e18;
        amounts = router.getAmountsOut(amountIn, path);

        vm.startPrank(users.bob);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.bob, block.timestamp
        );
        vm.stopPrank();
        uint256 bobTaxTokenBal = taxshare.balanceOf(users.bob);
        uint256 tax = amounts[1] * 100 / 10000;

        // as bob balance will get tax share his balance should be greatoer than amount out - tax
        assertGt(bobTaxTokenBal, amounts[1] - tax, "Bob tax token balance should be greater than amount in minus tax");
    }

    function testTaxShareSetTaxWithUpdates() public {
        GoatTypes.InitParams memory initParams;

        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 10000e18;
        initParams.virtualEth = 10e18;
        RevertType revertType = RevertType.None;
        createTokenAndAddLiquidity(initParams, revertType);
        vm.startPrank(users.owner);
        taxshare.setTaxes(users.bob, 200, 200);
        vm.stopPrank();
        bool taxed = taxshare.taxed(users.bob);
        assertTrue(taxed, "Bob should be taxed");

        uint256 buyTax = taxshare.buyTax(users.bob);
        uint256 sellTax = taxshare.sellTax(users.bob);

        assertEq(buyTax, 200, "Buy tax should be 200");
        assertEq(sellTax, 200, "Sell tax should be 200");

        vm.startPrank(users.owner);
        taxshare.setTaxes(users.bob, 0, 0);
        vm.stopPrank();
        taxed = taxshare.taxed(users.bob);
        assertFalse(taxed, "Bob should not be taxed");

        buyTax = taxshare.buyTax(users.bob);
        sellTax = taxshare.sellTax(users.bob);

        assertEq(buyTax, 0, "Buy tax should be 200");
        assertEq(sellTax, 0, "Sell tax should be 200");
    }

    function testTaxSharePrivileged() private {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 10000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        vm.startPrank(users.bob);
        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        taxshare.changeSharePercent(1000);
        vm.stopPrank();
    }

    function testTaxShareChangeRevertOnNewValueAboveDivisor() private {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 10000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.NewVaultPercentTooHigh.selector);
        taxshare.changeSharePercent(100000);
        vm.stopPrank();
    }
}
