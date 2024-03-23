// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

// Local imports
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";

struct Users {
    address whale;
    address alice;
    address bob;
    address lp;
    address lp1;
    address treasury;
}

contract GoatLibraryTest is Test {
    Users public users;

    function setUp() public {
        users = Users({
            whale: makeAddr("whale"),
            alice: makeAddr("alice"),
            bob: makeAddr("bob"),
            lp: makeAddr("lp"),
            lp1: makeAddr("lp1"),
            treasury: makeAddr("treasury")
        });
    }

    function testQuote() public {
        uint256 amountA = 100;
        uint256 reserveA = 1000;
        uint256 reserveB = 1000;
        uint256 amountB = GoatLibrary.quote(amountA, reserveA, reserveB);
        assertEq(amountB, 100);

        amountA = 1e18;
        reserveA = 100e18;
        reserveB = 10000e18;

        amountB = GoatLibrary.quote(amountA, reserveA, reserveB);
        assertEq(amountB, 100e18);

        amountA = 100e18;
        reserveA = 600e18;
        reserveB = 1000e18;

        amountB = GoatLibrary.quote(amountA, reserveA, reserveB);
        assertEq(amountB, 166666666666666666666);

        amountB = 166666666666666666667;
        reserveA = 600e18;
        reserveB = 1000e18;

        amountA = GoatLibrary.quote(amountB, reserveB, reserveA);
        assertEq(amountA, 100e18);
    }

    function testTokenAmountOut() public {
        uint256 amountWethIn = 12e18 + ((99 * 12e18) / 10000);
        uint256 expectedTokenAmountOut = 541646245915228818243;
        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 0;
        uint32 vestingUntil = type(uint32).max;
        uint256 bootStrapEth = 10e18;
        uint256 reserveToken = 750e18;
        uint256 reserveTokenForAmm = 250e18;
        uint256 virtualToken = 250e18;

        uint256 amountTokenOut = GoatLibrary.getTokenAmountOut(
            amountWethIn,
            virtualEth,
            reserveWeth,
            vestingUntil,
            bootStrapEth,
            reserveToken,
            virtualToken,
            reserveTokenForAmm
        );
        assertEq(amountTokenOut, expectedTokenAmountOut);
        amountWethIn = 5e18 + ((99 * 5e18) / 10000);
        // this is approx value
        expectedTokenAmountOut = 333300000000000000000;
        amountTokenOut = GoatLibrary.getTokenAmountOut(
            amountWethIn,
            virtualEth,
            reserveWeth,
            vestingUntil,
            bootStrapEth,
            reserveToken,
            virtualToken,
            reserveTokenForAmm
        );
        // 0.1% delta
        assertApproxEqRel(amountTokenOut, expectedTokenAmountOut, 1e15);
    }

    function testWethAmountOut() public {
        uint256 amountTokenIn = 333300000000000000000;
        // considering 1 % fees which is 5 e16
        uint256 expectedWethOut = 495e16;

        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 5e18;
        uint32 vestingUntil = type(uint32).max;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualToken = 250e18;

        uint256 amountWethOut = GoatLibrary.getWethAmountOut(
            amountTokenIn, reserveWeth, reserveToken, virtualEth, virtualToken, vestingUntil
        );
        assertApproxEqRel(amountWethOut, expectedWethOut, 1e14);
    }

    function testTokenAmountForAmm() public {
        uint256 virtualEth = 10e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialTokenMatch = 1000e18;
        uint256 expectedTokenForAmm = 250e18;

        uint256 tokenAmtForAmm = GoatLibrary.getTokenAmountForAmm(virtualEth, bootstrapEth, initialTokenMatch);
        assertEq(tokenAmtForAmm, expectedTokenForAmm);
    }

    function testTokenAmountOutForAmm() public {
        uint256 amountWethIn = 10e18;
        uint256 amountWethInWithFees = (amountWethIn * 10000) / 9901;
        uint256 reserveWeth = 10e18;
        uint256 reserveToken = 1000e18;
        uint256 expectedAmount = 500e18;

        uint256 tokenAmountOut = GoatLibrary.getTokenAmountOutAmm(amountWethInWithFees, reserveWeth, reserveToken);

        assertApproxEqRel(tokenAmountOut, expectedAmount, 10);
    }

    function testTokenAmountOutPresale() public {
        uint256 amountWethIn = 5e18;
        uint256 amountWethInWithFees = (amountWethIn * 10000) / 9901;
        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 0;
        uint256 bootStrapEth = 10e18;
        uint256 reserveToken = 750e18;
        uint256 virtualToken = 250e18;
        uint256 reserveTokenForAmm = 250e18;
        uint256 expectedAmount = 333333333333333333333;

        uint256 tokenAmountOut = GoatLibrary.getTokenAmountOutPresale(
            amountWethInWithFees, virtualEth, reserveWeth, bootStrapEth, reserveToken, virtualToken, reserveTokenForAmm
        );

        assertApproxEqRel(tokenAmountOut, expectedAmount, 10);

        amountWethIn = 12e18;
        amountWethInWithFees = (amountWethIn * 10000) / 9901;
        // 500e18 from presale and 41.6666666666666666667e18 from amm
        expectedAmount = 541666666666666666667;
        tokenAmountOut = GoatLibrary.getTokenAmountOutPresale(
            amountWethInWithFees, virtualEth, reserveWeth, bootStrapEth, reserveToken, virtualToken, reserveTokenForAmm
        );
        assertApproxEqRel(tokenAmountOut, expectedAmount, 10);
    }

    function testTokenPresaleAmm(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) public {
        virtualEth = bound(virtualEth, 1e18, 10000e18);
        bootstrapEth = bound(bootstrapEth, 1e18, 10000e18);
        initialEth = bound(initialEth, 0, bootstrapEth);
        initialTokenMatch = bound(initialTokenMatch, 1e18, 1000000000000000e18);
        GoatLibrary.getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
    }

    function testTokenAmt(uint256 virtualEth, uint256 bootstrapEth, uint256 initialEth, uint256 initialTokenMatch)
        public
    {
        // virtualEth = bound(virtualEth, 1e9, 1000e18);
        // bootstrapEth = bound(bootstrapEth, 1e10, 1000e18);
        // initialEth = bound(initialEth, 0, bootstrapEth);
        // initialTokenMatch = bound(initialTokenMatch, 1e12, 1000000000000000e18);
        // (, uint256 ammAmt) =
        //     GoatLibrary.getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);

        (, uint256 ammAmt) = GoatLibrary.getTokenAmountsForPresaleAndAmm(1e3, 10e18, 0, 10e18);
        assertTrue(ammAmt != 0);
    }
}
