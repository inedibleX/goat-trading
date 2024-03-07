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
    }

    function testTokenAmountOut() public {
        uint256 amountWethIn = 12e18 + ((99 * 12e18) / 10000);
        uint256 expectedTokenAmountOut = 541646245915228818243;
        uint256 virtualEth = 10e18;
        uint256 reserveEth = 0;
        uint32 vestingUntil = type(uint32).max;
        uint256 bootStrapEth = 10e18;
        uint256 reserveToken = 750e18;
        uint256 reserveTokenForAmm = 250e18;
        uint256 virtualToken = 250e18;

        uint256 amountTokenOut = GoatLibrary.getTokenAmountOut(
            amountWethIn,
            virtualEth,
            reserveEth,
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
            reserveEth,
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
        uint256 reserveEth = 5e18;
        uint32 vestingUntil = type(uint32).max;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualToken = 250e18;

        uint256 amountWethOut = GoatLibrary.getWethAmountOut(
            amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken, vestingUntil
        );
        assertApproxEqRel(amountWethOut, expectedWethOut, 1e14);
    }
}
