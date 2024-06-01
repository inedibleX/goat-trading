// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {LotteryToken} from "./../../../contracts/tokens/LotteryToken.sol";
import {LotteryTokenMaster} from "./../../../contracts/tokens/LotteryTokenMaster.sol";
import {MockWETH} from "./../../../contracts/mock/MockWETH.sol";
import {GoatV1Factory} from "./../../../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Pair} from "./../../../contracts/exchange/GoatV1Pair.sol";
import {GoatTypes} from "./../../../contracts/library/GoatTypes.sol";
import {TokenErrors} from "./../../../contracts/tokens/library/TokenErrors.sol";

struct Users {
    address alice;
    address beneficiary;
    address bob;
    address dex;
    address owner;
    address rewarder;
    address treasury;
    address whale;
}

contract LotteryTokenTest is Test {
    uint256 internal constant _DIVISOR = 10_000;
    MockWETH weth;
    GoatV1Factory factory;
    LotteryTokenMaster master;
    LotteryToken token;
    Users users;
    GoatV1Pair pair;

    function setUp() public {
        users = Users({
            alice: makeAddr("alice"),
            beneficiary: makeAddr("beneficiary"),
            bob: makeAddr("bob"),
            dex: makeAddr("dex"),
            owner: makeAddr("owner"),
            rewarder: makeAddr("rewarder"),
            treasury: makeAddr("treasury"),
            whale: makeAddr("whale")
        });
        weth = new MockWETH();
        factory = new GoatV1Factory(address(weth), new address[](0), new address[](0));
        master = new LotteryTokenMaster(address(factory), address(weth));
    }

    struct LotteryTokenInitValues {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 winChance;
        uint256 potPercent;
        uint256 maxWinMultiplier;
        uint256 buyTax;
        uint256 sellTax;
    }

    function _createLotteryToken(LotteryTokenInitValues memory values) internal {
        values.name = "Lottery";
        values.symbol = "LOT";

        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 1e19;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = uint112(values.totalSupply);
        initParams.virtualEth = 1e19;
        vm.startPrank(users.owner);
        (address tokenAddress, address pairAddress) = master.createLotteryToken(
            values.name,
            values.symbol,
            values.totalSupply,
            values.winChance,
            values.potPercent,
            values.maxWinMultiplier,
            values.buyTax,
            values.sellTax,
            initParams
        );
        vm.stopPrank();

        token = LotteryToken(tokenAddress);
        pair = GoatV1Pair(pairAddress);
    }

    function testLotteryTokenCreation() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        // Check token balances
        uint256 balanceOfOwner = token.balanceOf(users.owner);
        uint256 balanceOfPair = token.balanceOf(address(pair));
        assertEq(values.totalSupply, token.totalSupply());
        assertEq(values.totalSupply, balanceOfOwner + balanceOfPair);

        // check liquidity balance
        uint256 lpBal = pair.balanceOf(users.owner);
        uint256 lpTotalSupply = pair.totalSupply();
        uint256 minLiquidity = pair.MINIMUM_LIQUIDITY();
        assertEq(lpBal, (lpTotalSupply - minLiquidity));

        // check lottery specific values
        assertEq(values.winChance, master.winChances(address(token)));
        assertEq(values.potPercent, token.potPercent());

        // check owner and treasury
        assertEq(users.owner, token.owner());
        assertEq(users.owner, token.treasury());

        // check taxes
        assertEq(values.buyTax, token.buyTax(address(pair)));
        assertEq(values.sellTax, token.sellTax(address(pair)));

        // check lottery token master
        assertEq(address(master), token.lotteryMaster());
    }

    function testLotteryTokenCreationRevertOnInvalidWinChance() public {
        LotteryTokenInitValues memory values;
        values.winChance = 1_000_001;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.InvalidWinChance.selector);
        master.createLotteryToken(
            "Lottery",
            "LOT",
            values.totalSupply,
            values.winChance,
            values.potPercent,
            values.maxWinMultiplier,
            values.buyTax,
            values.sellTax,
            GoatTypes.InitParams(0, 0, 0, 0)
        );
        vm.stopPrank();
    }

    function testLotteryTokenCreationRevertOnPoolTokenAmountTooLow() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.TokenAmountForPoolTooLow.selector);
        master.createLotteryToken(
            "Lottery",
            "LOT",
            values.totalSupply,
            values.winChance,
            values.potPercent,
            values.maxWinMultiplier,
            values.buyTax,
            values.sellTax,
            GoatTypes.InitParams(10 ether, 10 ether, 0, 10 ether)
        );
        vm.stopPrank();
    }

    function testUpkeepSuccessWithWinner() public {
        vm.roll(1000);
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);
        uint256 transferAmount = 100e18;
        uint256 taxAmount = (transferAmount * values.buyTax) / _DIVISOR;
        uint256 potShare = (taxAmount * values.potPercent) / _DIVISOR;

        vm.startPrank(users.owner);
        token.setTaxes(users.owner, 200, 200);
        token.transfer(users.alice, transferAmount);
        vm.stopPrank();
        uint256 aliceBalanceBefore = token.balanceOf(users.alice);
        vm.roll(block.number + 32);
        master.upkeep(10);
        uint256 aliceBalanceAfter = token.balanceOf(users.alice);

        uint256 expectedPayout = (transferAmount * values.maxWinMultiplier) / _DIVISOR;
        expectedPayout = expectedPayout > potShare ? potShare : expectedPayout;

        assertEq(aliceBalanceAfter, aliceBalanceBefore + expectedPayout);
    }

    function testUpkeepSuccessWithoutWinner() public {
        vm.roll(1000);
        LotteryTokenInitValues memory values;
        values.winChance = 50_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        // 10%
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        vm.startPrank(users.owner);
        token.setTaxes(users.owner, 200, 200);
        token.transfer(users.alice, 100e18);
        token.transfer(users.bob, 100e18);
        vm.stopPrank();
        uint256 aliceBalanceBefore = token.balanceOf(users.alice);
        uint256 bobBalanceBefore = token.balanceOf(users.bob);
        vm.roll(block.number + 32);
        uint256 entryIndexBefore = master.entryIndex();
        master.upkeep(10);

        uint256 aliceBalanceAfter = token.balanceOf(users.alice);
        uint256 bobBalanceAfter = token.balanceOf(users.bob);
        uint256 entryIndexAfter = master.entryIndex();

        assertGt(entryIndexAfter, entryIndexBefore);

        // as there will be no winner bob balance should remain same
        assertEq(bobBalanceAfter, bobBalanceBefore);
        // as there will be no winner alice balance should remain same
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
    }

    function testPayWinnerRevertOnInvalidCaller() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        vm.startPrank(users.alice);
        vm.expectRevert(TokenErrors.OnlyLotteryMaster.selector);
        token.payWinner(users.alice, 100e18);
        vm.stopPrank();
    }

    function testChangePotPercentRevertOnInvalidCaller() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        vm.startPrank(users.alice);
        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        token.changePotPercent(1000);
        vm.stopPrank();
    }

    function testChangePotPercentRevertOnNewPercentTooHigh() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        vm.startPrank(users.owner);
        vm.expectRevert(TokenErrors.NewPotPercentTooHigh.selector);
        token.changePotPercent(100000);
        vm.stopPrank();
    }

    function testChangePotPercentSuccess() public {
        LotteryTokenInitValues memory values;
        values.winChance = 500_000;
        values.potPercent = 5000;
        values.totalSupply = 1e25;
        values.maxWinMultiplier = 100;
        values.buyTax = 200;
        values.sellTax = 200;

        _createLotteryToken(values);

        assertEq(token.potPercent(), values.potPercent);

        // update pot percent
        values.potPercent = 1000;
        vm.startPrank(users.owner);
        token.changePotPercent(values.potPercent);
        vm.stopPrank();

        assertEq(token.potPercent(), values.potPercent);
    }
}
