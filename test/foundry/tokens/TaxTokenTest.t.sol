// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseTokenTest, TaxToken, TokenFactory, console2} from "./BaseTokenTest.t.sol";

import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract TaxTokenTest is BaseTokenTest {
    // Test all functionality of plain tax tokens

    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Tax Token";
    string private constant tokenSymbol = "TT1";

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenFactory.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.TAX, 1000, initParams
        );

        plainTax = TaxToken(token);
        pair = pool;
    }

    function testTaxTokenInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.owner(), users.owner);
        assertEq(plainTax.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(plainTax.balanceOf(pair), bootstrapTokenAmount);

        assertEq(plainTax.totalSupply(), totalSupply);
        assertEq(plainTax.name(), tokenName);
        assertEq(plainTax.symbol(), tokenSymbol);
    }

    function testCreatePlainTaxTokenSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        uint256 pairBalance = plainTax.balanceOf(pair);
        uint256 ownerBalance = plainTax.balanceOf(users.owner);

        uint256 ownerLpBalance = IERC20(pair).balanceOf(users.owner);
        uint256 expectedLpBal = Math.sqrt(uint256(initParams.virtualEth) * initParams.initialTokenMatch) - 1000;

        assertEq(pairBalance, bootstrapTokenAmount, "Pair balance should be equal to bootstrap token amount");
        assertEq(
            ownerBalance,
            totalSupply - bootstrapTokenAmount,
            "Owner balance should be equal to total supply minus bootstrap token amount"
        );
        assertEq(ownerLpBalance, expectedLpBal);

        address treasury = plainTax.treasury();
        address dex = plainTax.dex();
        address owner = plainTax.owner();

        assertEq(treasury, users.owner, "Treasury should be owner");
        assertEq(dex, address(0), "Dex should be address(0)");
        assertEq(owner, users.owner, "Owner should be owner");
    }

    function testCreateTokenRevertOnInitialEthNonZero() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 100;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.NonZeroInitialEth);
    }

    function testTransferTreasurySuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.treasury(), users.owner, "Treasury should be owner");

        vm.startPrank(users.owner);
        plainTax.transferTreasury(users.treasury);
        vm.stopPrank();

        address treasury = plainTax.treasury();
        assertEq(treasury, users.treasury, "Treasury should be treasury");
    }

    function testTransferTreasuryRevertNotOwner() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.treasury(), users.owner, "Treasury should be owner");

        vm.startPrank(users.bob);
        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        plainTax.transferTreasury(users.treasury);
        vm.stopPrank();
    }

    function testChangeMinSellSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.minSell(), 0.1 ether, "Min sell should be 0");

        vm.startPrank(users.owner);
        plainTax.changeMinSell(1 ether);
        vm.stopPrank();

        assertEq(plainTax.minSell(), 1 ether, "Min sell should be 100");
    }

    function testChangeMinSellRevertOnNotOwnerOrTreasury() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.minSell(), 0.1 ether, "Min sell should be 0");

        vm.startPrank(users.bob);
        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        plainTax.changeMinSell(1 ether);
        vm.stopPrank();
    }

    function testChangeDexSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.dex(), address(0), "Dex should be address(0)");

        vm.startPrank(users.owner);
        plainTax.changeDex(address(router));
        vm.stopPrank();

        assertEq(plainTax.dex(), address(router), "Dex should be whale");
    }

    function testChangeDexRevertOnNotOwnerOrTreasury() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.dex(), address(0), "Dex should be address(0)");

        vm.startPrank(users.bob);
        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        plainTax.changeDex(users.whale);
        vm.stopPrank();
    }

    function testSetTaxesSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.buyTax(pair), 100, "Buy tax should be 100");
        assertEq(plainTax.sellTax(pair), 100, "Sell tax should be 100");

        vm.startPrank(users.owner);
        plainTax.setTaxes(pair, 200, 200);
        vm.stopPrank();

        assertEq(plainTax.buyTax(pair), 200, "Buy tax should be 200");
        assertEq(plainTax.sellTax(pair), 200, "Sell tax should be 200");
    }

    function testSetTaxesRevertOnNotOwner() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(plainTax.buyTax(pair), 100, "Buy tax should be 100");
        assertEq(plainTax.sellTax(pair), 100, "Sell tax should be 100");
        vm.startPrank(users.owner);
        plainTax.transferTreasury(users.treasury);
        vm.stopPrank();

        vm.startPrank(users.treasury);
        vm.expectRevert("Ownable: caller is not the owner");
        plainTax.setTaxes(pair, 200, 200);
        vm.stopPrank();
    }

    function testTaxTransferSuccessWithNecessaryUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        plainTax.transferTreasury(users.treasury);
        plainTax.changeDex(address(router));
        plainTax.setTaxes(users.dex, 200, 200);
        uint256 transferAmount = 10e18;
        plainTax.transfer(users.dex, transferAmount);
        vm.stopPrank();

        uint256 expectedTax = transferAmount * 200 / 10000;

        assertEq(
            plainTax.balanceOf(users.dex),
            transferAmount - expectedTax,
            "Dex balance should be transfer amount minus tax"
        );
        uint256 taxContractBal = plainTax.balanceOf(address(plainTax));
        assertEq(taxContractBal, expectedTax, "Treasury balance should be tax amount");

        transferAmount = 5e18;
        vm.startPrank(users.dex);
        plainTax.transfer(users.bob, transferAmount);
        vm.stopPrank();

        expectedTax = transferAmount * 200 / 10000;

        assertEq(
            plainTax.balanceOf(users.bob),
            transferAmount - expectedTax,
            "Dex balance should be transfer amount minus tax"
        );

        assertEq(
            plainTax.balanceOf(address(plainTax)) - taxContractBal, expectedTax, "Treasury balance should be tax amount"
        );
    }

    function testSellTaxesSuccessWithNecessaryUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        plainTax.transferTreasury(users.treasury);
        plainTax.changeDex(address(router));
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(router.WETH());
        path[1] = address(plainTax);
        uint256 amountIn = 12e18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        vm.startPrank(users.whale);
        // fund bob with some weth
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactWethForTokens(amountIn, amounts[1], address(plainTax), users.whale, block.timestamp);
        vm.stopPrank();

        amountIn = 2e18;
        amounts = router.getAmountsOut(amountIn, path);

        vm.startPrank(users.bob);
        weth.approve(address(router), amountIn);
        router.swapExactWethForTokens(amountIn, amounts[1], address(plainTax), users.bob, block.timestamp);
        vm.stopPrank();
        uint256 bobTaxTokenBal = plainTax.balanceOf(users.bob);
        uint256 tax = amounts[1] * 100 / 10000;

        assertEq(bobTaxTokenBal, amounts[1] - tax, "Bob tax token balance should be amount in minus tax");

        uint256 amountToSell = plainTax.balanceOf(address(plainTax));
        router.getAmountsOut(amountToSell, path);

        uint256 taxBalBefore = plainTax.balanceOf(address(plainTax));
        path[0] = address(plainTax);
        path[1] = address(router.WETH());
        amounts = router.getAmountsOut(taxBalBefore, path);

        uint256 totalEthValue = amounts[1];

        uint256 actualAmountOut = taxBalBefore * 0.1 ether / totalEthValue;

        tax = actualAmountOut * 100 / 10000;

        // change timestamp to bypass vesting period
        vm.warp(block.timestamp + 10 days);
        vm.startPrank(users.owner);
        plainTax.transfer(users.alice, 10e18);
        vm.stopPrank();
        uint256 taxBalAfter = plainTax.balanceOf(address(plainTax));

        uint256 treasuryBalAfter = weth.balanceOf(users.treasury);
        assertGe(treasuryBalAfter, 0.1 ether);

        assertEq(
            taxBalAfter,
            taxBalBefore - actualAmountOut + tax,
            "Tax balance should be tax balance before minus actual amount out"
        );
    }

    function testSetTaxSuccessWithNecessaryUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        plainTax.setTaxes(users.bob, 200, 200);
        vm.stopPrank();
        bool taxed = plainTax.taxed(users.bob);
        assertTrue(taxed, "Bob should be taxed");

        uint256 buyTax = plainTax.buyTax(users.bob);
        uint256 sellTax = plainTax.sellTax(users.bob);

        assertEq(buyTax, 200, "Buy tax should be 200");
        assertEq(sellTax, 200, "Sell tax should be 200");

        vm.startPrank(users.owner);
        plainTax.setTaxes(users.bob, 0, 0);
        vm.stopPrank();
        taxed = plainTax.taxed(users.bob);
        assertFalse(taxed, "Bob should not be taxed");

        buyTax = plainTax.buyTax(users.bob);
        sellTax = plainTax.sellTax(users.bob);

        assertEq(buyTax, 0, "Buy tax should be 200");
        assertEq(sellTax, 0, "Sell tax should be 200");
    }
}
