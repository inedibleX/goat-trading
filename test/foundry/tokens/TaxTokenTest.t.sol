// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseTokenTest, TaxToken, TokenFactory} from "./BaseTokenTest.t.sol";

import {console2} from "forge-std/console2.sol";

import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";
import {GoatV1Pair} from "./../../../contracts/exchange/GoatV1Pair.sol";

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

        // as the the above transfer txn is assumed as sell txn so treasury should get the tax amount
        uint256 taxCollectedbal = plainTax.balanceOf(users.treasury);
        assertEq(taxCollectedbal, expectedTax, "Treasury should hold the taxes of failed sell txn");
        vm.warp(block.timestamp + 2);
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

        // as the last transfer txn is assumed as buy txn the tax should remain in contract
        assertEq(plainTax.balanceOf(address(plainTax)), expectedTax, "Contract should hold the taxes of buy txn");
    }

    function testPlainTaxOnTransfers() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        plainTax.setTaxes(users.alice, 100, 100);
        vm.stopPrank();
        uint256 aliceBalBefore = plainTax.balanceOf(users.alice);
        uint256 amount = 10e18;
        vm.startPrank(users.owner);
        plainTax.transfer(users.alice, amount);
        uint256 aliceBalAfter = plainTax.balanceOf(users.alice);
        uint256 tax = amount * 100 / 10000;

        assertEq(aliceBalAfter - aliceBalBefore, amount - tax, "Alice balance diff should be amount minus tax");

        amount = amount / 2;

        aliceBalBefore = aliceBalAfter;
        uint256 bobBalBefore = plainTax.balanceOf(users.bob);
        vm.startPrank(users.alice);
        plainTax.transfer(users.bob, amount);
        vm.stopPrank();
        tax = amount * 100 / 10000;
        aliceBalAfter = plainTax.balanceOf(users.alice);

        uint256 bobBalAfter = plainTax.balanceOf(users.bob);

        assertEq(aliceBalBefore - aliceBalAfter, amount, "Alice balance diff should be amount minus tax");

        assertEq(bobBalAfter - bobBalBefore, amount - tax, "Bob balance diff should be amount minus tax");

        vm.startPrank(users.owner);
        plainTax.setTaxes(users.alice, 0, 0);
        vm.stopPrank();

        aliceBalBefore = aliceBalAfter;
        vm.startPrank(users.bob);
        plainTax.transfer(users.alice, bobBalAfter);
        vm.stopPrank();
        aliceBalAfter = plainTax.balanceOf(users.alice);

        assertEq(aliceBalAfter - aliceBalBefore, bobBalAfter, "Alice balance diff should be bob's balance");
    }

    function testContractLockOnDexAddressCodeSizeZero() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        plainTax.transferTreasury(users.treasury);
        // set dex to an address with code size 0
        plainTax.changeDex(users.dex);
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
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.whale, block.timestamp
        );
        vm.stopPrank();
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
        uint256 pairTokenBalBefore = plainTax.balanceOf(pair);
        vm.startPrank(users.whale);
        // fund bob with some weth
        uint256 taxCollectedBalBefore = plainTax.balanceOf(address(plainTax));
        uint256 tax = amounts[1] * 100 / 10000;
        uint256 amountOutMin = amounts[1] - tax;
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.whale, block.timestamp
        );
        vm.stopPrank();
        uint256 taxCollectedBalAfter = plainTax.balanceOf(address(plainTax));
        uint256 swapperTokenBalAfter = plainTax.balanceOf(users.whale);
        uint256 pairTokenBalAfter = plainTax.balanceOf(pair);

        assertEq(taxCollectedBalAfter - taxCollectedBalBefore, tax, "Treasury balance should be tax amount");
        assertEq(pairTokenBalBefore - pairTokenBalAfter, swapperTokenBalAfter + tax);

        vm.warp(block.timestamp + 10 days);

        // update treasury bal before
        taxCollectedBalBefore = taxCollectedBalAfter;
        amountIn = 2e18;
        amounts = router.getAmountsOut(amountIn, path);
        tax = (amounts[1] * 1000) / 10000;
        amountOutMin = amounts[1] - tax;
        vm.startPrank(users.bob);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.bob, block.timestamp
        );
        vm.stopPrank();
        taxCollectedBalAfter = plainTax.balanceOf(address(plainTax));
        uint256 bobTaxTokenBal = plainTax.balanceOf(users.bob);
        tax = amounts[1] * 100 / 10000;

        assertEq(taxCollectedBalAfter - taxCollectedBalBefore, tax, "Treasury balance should be tax amount");
        assertEq(bobTaxTokenBal, amounts[1] - tax, "Bob tax token balance should be amount in minus tax");

        // SWAP TOKENS FOR WETH

        path[0] = address(plainTax);
        path[1] = address(router.WETH());

        amountIn = 10e18;
        amounts = router.getAmountsOut(amountIn - amountIn * 100 / 10000, path);

        uint256 treasuryWethBalBefore = weth.balanceOf(users.treasury);

        // increase time
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(users.bob);
        plainTax.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, (amounts[1] - (amounts[1] * 100 / 10000)), path, users.bob, block.timestamp
        );
        vm.stopPrank();
        uint256 treasuryWethBalAfter = weth.balanceOf(users.treasury);

        // Should swap tax for some amount of weth
        assertGt(
            treasuryWethBalAfter,
            treasuryWethBalBefore,
            "Treasury weth balance should be greater than treasury weth balance before"
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
