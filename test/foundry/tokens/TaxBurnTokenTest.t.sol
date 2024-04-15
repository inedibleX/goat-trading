// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest, TokenFactory2, TaxBurnToken} from "./BaseTokenTest.t.sol";
import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";
// Taxburn tokens:
// 1. Tokens are burned on tax
// 2. Privileged

contract TaxBurnTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Tax Burn Token";
    string private constant tokenSymbol = "TBT";

    function createTokenAndAddLiquidity(
        GoatTypes.InitParams memory initParams,
        RevertType revertType,
        uint256 burnPercent
    ) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.InitialBurnPercent) {
            vm.expectRevert();
        }
        (address token, address pool) = tokenFactory2.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.TAXBURN, burnPercent, initParams
        );

        taxburn = TaxBurnToken(token);
        pair = pool;
    }

    function testTaxBurnInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        uint256 burnPercent = 5000;

        createTokenAndAddLiquidity(initParams, RevertType.None, burnPercent);

        assertEq(taxburn.owner(), users.owner);
        assertEq(taxburn.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(taxburn.balanceOf(pair), bootstrapTokenAmount);

        assertEq(taxburn.totalSupply(), totalSupply);
        assertEq(taxburn.name(), tokenName);
        assertEq(taxburn.symbol(), tokenSymbol);
        assertEq(taxburn.burnPercent(), burnPercent);
    }

    function testTaxBurnTokenLaunch() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        // This should revert
        createTokenAndAddLiquidity(initParams, RevertType.InitialBurnPercent, 100000);

        // This should not revert
        createTokenAndAddLiquidity(initParams, RevertType.None, 1000);

        assertEq(taxburn.owner(), users.owner);
        assertEq(taxburn.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(taxburn.balanceOf(pair), bootstrapTokenAmount);
    }

    function testTaxBurnUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        // This should not revert
        createTokenAndAddLiquidity(initParams, RevertType.None, 5000);
        uint256 totalSupplyBefore = taxburn.totalSupply();

        uint256 taxAccrued = taxburn.balanceOf(address(taxburn));
        assertEq(taxAccrued, 0);
        vm.startPrank(users.owner);
        taxburn.transferTreasury(users.treasury);
        taxburn.changeDex(address(router));
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(router.WETH());
        path[1] = address(taxburn);
        uint256 amountIn = 12e18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        vm.startPrank(users.whale);
        // fund bob with some weth
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactWethForTokens(amountIn, amounts[1], address(taxburn), users.whale, block.timestamp);
        vm.stopPrank();

        // 1% tax on buy
        uint256 taxCollected = amounts[1] / 100;
        // as tax share for burn is 50%
        uint256 taxBurned = taxCollected / 2;

        // tax for treasury should be collected in token contract address.
        assertEq(taxburn.balanceOf(address(taxburn)), taxCollected - taxBurned);
        uint256 totalSupplyAfter = taxburn.totalSupply();

        assertEq(totalSupplyAfter, totalSupplyBefore - taxBurned);
    }

    function testChangeBurnPercentRevertOnNewPercentGreaterThanDivisor() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        // This should not revert
        createTokenAndAddLiquidity(initParams, RevertType.None, 5000);
        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.NewBurnPercentTooHigh.selector);
        taxburn.changeBurnPercent(100000);
        vm.stopPrank();
    }

    function testChangeBurnPercentSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        uint256 burnPercent = 5000;
        // This should not revert
        createTokenAndAddLiquidity(initParams, RevertType.None, burnPercent);
        assertEq(taxburn.burnPercent(), burnPercent);

        burnPercent = 6000;
        vm.startPrank(users.owner);
        taxburn.changeBurnPercent(burnPercent);
        vm.stopPrank();

        assertEq(taxburn.burnPercent(), burnPercent);
    }
}
