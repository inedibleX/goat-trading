// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {BaseTokenTest, VaultToken, TokenFactory3} from "./BaseTokenTest.t.sol";
import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";
import {TokenErrors} from "./../../../contracts/tokens/TokenErrors.sol";
// Vault token:
// 1. Taxes are added to the correct place
// 2. Token receives ether from sells
// 3. Ether rewards are calculated correctly and redeemed correctly

contract VaultTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Vault Token";
    string private constant tokenSymbol = "VTT";
    uint256 vaultPercent = 5000;

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenFactory3.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory3.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.VAULT, vaultPercent, initParams
        );
        vault = VaultToken(payable(token));
        pair = pool;
    }

    function testTaxTokenInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(vault.owner(), users.owner);
        assertEq(vault.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(vault.balanceOf(pair), bootstrapTokenAmount);

        assertEq(vault.totalSupply(), totalSupply);
        assertEq(vault.name(), tokenName);
        assertEq(vault.symbol(), tokenSymbol);

        assertEq(vault.vaultPercent(), vaultPercent);
    }

    function testVaultTaxCollectWithNecessaryUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        // Special functionality on vaults when selling, some Ether goes into the vault.
        vm.startPrank(users.owner);
        vault.transferTreasury(users.treasury);
        vault.changeDex(address(router));

        vault.setTaxes(users.dex, 200, 200);

        uint256 transferAmount = 20e18;

        vault.transfer(users.dex, transferAmount);

        vm.stopPrank();
        uint256 dexBal = vault.balanceOf(users.dex);
        uint256 tax = transferAmount * 200 / 10000;
        assertEq(transferAmount, dexBal + tax);
        assertEq(vault.balanceOf(users.treasury), tax);
    }

    function testVaultTaxCollectAndSellTaxTokenForEth() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        // Special functionality on vaults when selling, some Ether goes into the vault.
        vm.startPrank(users.owner);
        vault.transferTreasury(users.treasury);
        vault.changeDex(address(router));
        vm.stopPrank();

        uint256 pairTokenBalBefore = vault.balanceOf(pair);
        address[] memory path = new address[](2);
        path[0] = address(router.WETH());
        path[1] = address(vault);
        uint256 amountIn = 12e18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        vm.startPrank(users.whale);
        assertEq(vault.balanceOf(users.treasury), 0);
        // fund bob with some weth
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.whale, block.timestamp
        );
        vm.stopPrank();
        assertEq(
            vault.balanceOf(address(vault)),
            amounts[1] * 100 / 10000,
            "vault should collect the taxes on tax sell fail of buy txn"
        );

        amountIn = 2e18;
        amounts = router.getAmountsOut(amountIn, path);

        vm.startPrank(users.bob);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.bob, block.timestamp
        );
        vm.stopPrank();

        uint256 pairTokenBalAfter = vault.balanceOf(pair);

        uint256 totalTaxes = (pairTokenBalBefore - pairTokenBalAfter) * 100 / 10000;

        uint256 whaleTokenBalance = vault.balanceOf(users.whale);
        uint256 bobsTokenBalance = vault.balanceOf(users.bob);

        assertEq(pairTokenBalAfter + whaleTokenBalance + bobsTokenBalance + totalTaxes, pairTokenBalBefore);

        uint256 vaultEthBalBefore = address(vault).balance;
        uint256 treasuryEthBalBefore = users.treasury.balance;
        assertEq(vaultEthBalBefore, 0);

        assertEq(treasuryEthBalBefore, 0);

        // change timestamp to bypass vesting period
        vm.warp(block.timestamp + 10 days);

        path[0] = address(vault);
        path[1] = address(router.WETH());
        amountIn = 10e18;
        amounts = router.getAmountsOut(amountIn - amountIn * 100 / 10000, path);

        vm.startPrank(users.bob);
        vault.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, (amounts[1] - (amounts[1] * 100 / 10000)), path, users.bob, block.timestamp
        );
        vm.stopPrank();

        uint256 vaultEthBalAfter = address(vault).balance;
        uint256 treasuryEthBalAfter = users.treasury.balance;
        assertGe(vaultEthBalAfter, 1);

        // sometimes there can be 1 wei delta
        assertApproxEqRel(treasuryEthBalAfter, vaultEthBalAfter, 10000);
    }

    function testVaultRedeemAndUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        // Special functionality on vaults when selling, some Ether goes into the vault.
        vm.startPrank(users.owner);
        vault.transferTreasury(users.treasury);
        vault.changeDex(address(router));
        vm.stopPrank();

        uint256 pairTokenBalBefore = vault.balanceOf(pair);
        address[] memory path = new address[](2);
        path[0] = address(router.WETH());
        path[1] = address(vault);
        uint256 amountIn = 12e18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        vm.startPrank(users.whale);
        assertEq(vault.balanceOf(users.treasury), 0);
        // fund bob with some weth
        weth.transfer(users.bob, 20e18);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.whale, block.timestamp
        );
        vm.stopPrank();
        assertEq(
            vault.balanceOf(address(vault)),
            amounts[1] * 100 / 10000,
            "vault should collect the taxes on tax sell fail of buy txn"
        );

        amountIn = 2e18;
        amounts = router.getAmountsOut(amountIn, path);

        vm.startPrank(users.bob);
        weth.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amounts[1], path, users.bob, block.timestamp
        );
        vm.stopPrank();

        uint256 pairTokenBalAfter = vault.balanceOf(pair);

        uint256 totalTaxes = (pairTokenBalBefore - pairTokenBalAfter) * 100 / 10000;

        uint256 whaleTokenBalance = vault.balanceOf(users.whale);
        uint256 bobsTokenBalance = vault.balanceOf(users.bob);

        assertEq(
            pairTokenBalAfter + whaleTokenBalance + bobsTokenBalance + totalTaxes,
            pairTokenBalBefore,
            "Token out + taxes + current reserves should equal initial reserves"
        );

        uint256 vaultEthBalBefore = address(vault).balance;
        assertEq(vaultEthBalBefore, 0, "Vault should have no ether");

        // change timestamp to bypass vesting period
        vm.warp(block.timestamp + 10 days);

        path[0] = address(vault);
        path[1] = address(router.WETH());
        amountIn = 10e18;
        amounts = router.getAmountsOut(amountIn - amountIn * 100 / 10000, path);

        vm.startPrank(users.bob);
        vault.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, (amounts[1] - (amounts[1] * 100 / 10000)), path, users.bob, block.timestamp
        );
        vm.stopPrank();

        uint256 vaultEthBalAfter = address(vault).balance;
        assertGe(vaultEthBalAfter, 0);

        uint256 whaleTokenBalBefore = vault.balanceOf(users.whale);

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 expectedReturn = vaultEthBalAfter * whaleTokenBalBefore / totalSupplyBefore;
        uint256 whaleEthBalBefore = users.whale.balance;

        vaultEthBalBefore = vault.vaultEth();
        vm.startPrank(users.whale);
        vault.redeem(whaleTokenBalBefore);
        vm.stopPrank();
        vaultEthBalAfter = vault.vaultEth();

        uint256 whaleEthBalAfter = users.whale.balance;
        // should update the vault eth by difference of whale balance
        assertEq(
            vaultEthBalBefore - vaultEthBalAfter,
            whaleEthBalAfter - whaleEthBalBefore,
            "Vault eth should decrease by amount redeemed by the user"
        );
        assertApproxEqRel(whaleEthBalAfter - whaleEthBalBefore, expectedReturn, 1);

        whaleTokenBalance = vault.balanceOf(users.whale);
        assertEq(whaleTokenBalance, 0);

        uint256 totalSupplyAfter = vault.totalSupply();

        assertEq(totalSupplyBefore - whaleTokenBalBefore, totalSupplyAfter);
    }

    function testDepositEthAndUpdates() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        uint256 vaultEthBalBefore = address(vault).balance;
        uint256 vaultEthStored = vault.vaultEth();

        assertEq(vaultEthBalBefore, 0);
        assertEq(vaultEthStored, 0);

        vm.deal(users.bob, 10 ether);
        vm.startPrank(users.bob);
        vault.deposit{value: 10 ether}();
        vm.stopPrank();

        uint256 vaultEthBalAfter = address(vault).balance;
        uint256 vaultEthStoredAfter = vault.vaultEth();

        assertEq(vaultEthBalAfter, 10 ether);
        assertEq(vaultEthStoredAfter, 10 ether);
    }

    function testTokenEthValue() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        uint256 tokenEthValueBefore = vault.tokenEthValue(1e18);

        assertEq(tokenEthValueBefore, 0);

        vm.deal(users.bob, vault.totalSupply());

        vm.startPrank(users.bob);
        vault.deposit{value: vault.totalSupply()}();
        vm.stopPrank();

        uint256 tokenEthValueAfter = vault.tokenEthValue(1e18);

        assertEq(tokenEthValueAfter, 1 ether);
    }

    function testChangeVaultPercentSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        uint256 vaultPercentBefore = vault.vaultPercent();
        assertEq(vaultPercentBefore, 5000);

        vm.startPrank(users.owner);
        vault.changeVaultPercent(1000);
        vm.stopPrank();

        uint256 vaultPercentAfter = vault.vaultPercent();
        assertEq(vaultPercentAfter, 1000);
    }

    function testChangeVaultPercentRevertOnVaultPercentMoreThanDivisor() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);
        uint256 vaultPercentBefore = vault.vaultPercent();
        assertEq(vaultPercentBefore, 5000);

        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.NewVaultPercentTooHigh.selector);
        vault.changeVaultPercent(100000);
        vm.stopPrank();

        uint256 vaultPercentAfter = vault.vaultPercent();
        assertEq(vaultPercentAfter, 5000);
    }
}
