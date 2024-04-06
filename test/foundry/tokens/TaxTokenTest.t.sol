// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTokenTest, TaxToken, TokenFactory} from "./BaseTokenTest.t.sol";

import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract TaxTokenTest is BaseTokenTest {
    enum RevertType {
        None,
        NonZeroInitialEth
    }
    // Test all functionality of plain tax tokens

    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenFactory.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory.createToken(
            "TaxToken", "TT1", totalSupply, 100, 100, users.owner, TokenType.TAX, 1000, initParams
        );

        plainTax = TaxToken(token);
        pair = pool;
    }

    function testCreateTokenSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        uint256 pairBalance = plainTax.balanceOf(pair);
        uint256 ownerBalance = plainTax.balanceOf(users.owner);

        uint256 ownerLpBalance = IERC20(pair).balanceOf(users.owner);
        uint256 expectedLpBal = 100e18 - 1000;

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
        vm.expectRevert(TaxToken.OnlyOwnerOrTreasury.selector);
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
        vm.expectRevert(TaxToken.OnlyOwnerOrTreasury.selector);
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
        plainTax.changeDex(users.whale);
        vm.stopPrank();

        assertEq(plainTax.dex(), users.whale, "Dex should be whale");
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
        vm.expectRevert(TaxToken.OnlyOwnerOrTreasury.selector);
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

    // This tests only that balances are applied and removed correctly from addresses.
    // The actual updating for taxes to be given to a certain address is tested below
    function _testTaxTransfers() private {
        // 1. Transfer from one user to the next with no taxes
        // 2. Check that the above does not have taxes removed
        // 3. Transfer from one user to the next with buy taxes
        // 4. Check that update is done correctly on from/to
        // 5. Transfer from one user to the next with sell taxes
        // (one of the users above is taxed on buys, one on sells)
        // 6. Check that update is done correctly
    }

    function _testPlainTaxUpdates() private {
        // 1. Make sure that treasury got all of the deducted transfers
    }

    function _testPlainTaxSelling() private {
        // 1. Make sure selling works correctly before pool is in the right mode
        // 2. Update pool so selling should work
        // 3. Make sure selling works correctly once tokens can be sold
    }

    function _testPlainTaxPrivileged() private {
        // 1. Test that only owner can set taxes
        // 2. Test that owner or treasury can set treasury address
    }
}
