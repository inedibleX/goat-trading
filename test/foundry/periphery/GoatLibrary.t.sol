// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

// Local imports
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {GoatErrors} from "../../../contracts/library/GoatErrors.sol";

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

    function testQuoteRevertOnInsufficientLiquidity() public {
        uint256 amountA = 100;
        uint256 reserveA = 0;
        uint256 reserveB = 1000;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.quote(amountA, reserveA, reserveB);

        reserveA = 1000;
        reserveB = 0;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.quote(amountA, reserveA, reserveB);
    }

    function testQuoteRevertOnInsufficientInputAmount() public {
        uint256 amountA = 0;
        uint256 reserveA = 1000;
        uint256 reserveB = 1000;

        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        GoatLibrary.quote(amountA, reserveA, reserveB);
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

    function testGetTokenAmountOutReverts() public {
        uint256 amountWethIn = 0;
        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 0;
        uint32 vestingUntil = type(uint32).max;
        uint256 bootStrapEth = 10e18;
        uint256 reserveToken = 750e18;
        uint256 reserveTokenForAmm = 250e18;
        uint256 virtualToken = 250e18;

        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        GoatLibrary.getTokenAmountOut(
            amountWethIn,
            virtualEth,
            reserveWeth,
            vestingUntil,
            bootStrapEth,
            reserveToken,
            virtualToken,
            reserveTokenForAmm
        );
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

    function testWethAmountOutRevertWithInsufficientInputAmount() public {
        uint256 amountTokenIn = 0;
        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 5e18;
        uint32 vestingUntil = type(uint32).max;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualToken = 250e18;

        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        GoatLibrary.getWethAmountOut(amountTokenIn, reserveWeth, reserveToken, virtualEth, virtualToken, vestingUntil);
    }

    function testWethAmountOutRevertWithInsufficientLiquidity() public {
        uint256 amountTokenIn = 333300000000000000000;
        uint256 virtualEth = 10e18;
        uint256 reserveWeth = 0;
        uint32 vestingUntil = type(uint32).max;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualToken = 250e18;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOut(amountTokenIn, reserveWeth, reserveToken, virtualEth, virtualToken, vestingUntil);

        reserveWeth = 5e18;
        reserveToken = 0;
        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOut(amountTokenIn, reserveWeth, reserveToken, virtualEth, virtualToken, vestingUntil);
    }

    function testWethAmountOutAmm() public {
        uint256 reserveWeth = 10e18;
        uint256 reserveToken = 1000e18;

        uint256 amountTokenIn = 250e18;

        uint256 expectedWethOut = 2e18 * 9901 / 10000;
        uint256 amountWethOut = GoatLibrary.getWethAmountOutAmm(amountTokenIn, reserveWeth, reserveToken);
        assertEq(amountWethOut, expectedWethOut);
    }

    function testWethAmountOutAmmRevertInsufficientInputAmount() public {
        uint256 reserveWeth = 10e18;
        uint256 reserveToken = 1000e18;

        uint256 amountTokenIn = 0;
        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        GoatLibrary.getWethAmountOutAmm(amountTokenIn, reserveWeth, reserveToken);
    }

    function testWethAmountOutAmmRevertInsufficientLiquidity() public {
        uint256 reserveWeth = 10e18;
        uint256 reserveToken = 0;
        uint256 amountTokenIn = 250e18;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOutAmm(amountTokenIn, reserveWeth, reserveToken);

        reserveToken = 1000e18;
        reserveWeth = 0;
        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOutAmm(amountTokenIn, reserveWeth, reserveToken);
    }

    function testWethAmountOutPresale() public {
        uint256 amountTokenIn = 333e18;
        uint256 reserveEth = 5e18;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;

        uint256 expectedWethOut = 4945549500000000000;

        uint256 amountWethOut =
            GoatLibrary.getWethAmountOutPresale(amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken);

        // as 99 bps fees is considered we will receive slightly less 4.95e18
        assertEq(amountWethOut, expectedWethOut);
    }

    function testWethAmountOutPresaleRevertWithInsufficientInputAmount() public {
        uint256 amountTokenIn = 0;
        uint256 reserveEth = 5e18;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;

        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        GoatLibrary.getWethAmountOutPresale(amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken);
    }

    function testWethAmountOutPresaleRevertWithInsufficientLiquidity() public {
        uint256 amountTokenIn = 333e18;
        uint256 reserveEth = 0;
        uint256 reserveToken = 750e18 - amountTokenIn;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOutPresale(amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken);

        reserveEth = 5e18;
        reserveToken = 0;
        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountOutPresale(amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken);
    }

    function testTokenAmountForAmm() public {
        uint256 virtualEth = 10e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialTokenMatch = 1000e18;
        uint256 expectedTokenForAmm = 250e18;

        uint256 tokenAmtForAmm = GoatLibrary.getBootstrapTokenAmountForAmm(virtualEth, bootstrapEth, initialTokenMatch);
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
        (, uint256 ammAmt) = GoatLibrary.getTokenAmountsForPresaleAndAmm(1e3, 10e18, 0, 10e18);
        assertTrue(ammAmt != 0);
    }

    function testActualBootstrapAmount() public {
        uint256 virtualEth = 10e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialEth = 0;
        uint256 initialTokenMatch = 1000e18;
        uint256 expectedAmount = 750e18;

        uint256 actualBootstrapAmount =
            GoatLibrary.getActualBootstrapTokenAmount(virtualEth, bootstrapEth, initialEth, initialTokenMatch);

        assertEq(actualBootstrapAmount, expectedAmount);

        initialEth = 10e18;
        expectedAmount = 250e18;
        actualBootstrapAmount =
            GoatLibrary.getActualBootstrapTokenAmount(virtualEth, bootstrapEth, initialEth, initialTokenMatch);

        assertEq(actualBootstrapAmount, expectedAmount);
    }

    function testBootstrapAmountForPresaleAndAmm() public {
        uint256 virtualEth = 10e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialEth = 0;
        uint256 initialTokenMatch = 1000e18;
        uint256 amountForPresale = 500e18;
        uint256 amountForAmm = 250e18;

        (uint256 presaleAmount, uint256 ammAmount) =
            GoatLibrary.getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
        assertEq(presaleAmount, amountForPresale);
        assertEq(ammAmount, amountForAmm);

        initialEth = 10e18;
        amountForPresale = 0;
        amountForAmm = 250e18;

        (presaleAmount, ammAmount) =
            GoatLibrary.getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
        assertEq(presaleAmount, amountForPresale);
        assertEq(ammAmount, amountForAmm);
    }

    function testGetTokenAmountIn() public {
        uint256 wethAmountOut = 2e18;
        uint256 reserveEth = 5e18;
        uint256 reserveToken = 750e18 - 333e18;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint32 vestingUntil = type(uint32).max;
        uint256 actualWethOut = wethAmountOut * 10000 / 9901;
        uint256 numerator = actualWethOut * (virtualToken + reserveToken);
        uint256 denominator = virtualEth + reserveEth - actualWethOut;
        uint256 expectedAmountIn = numerator / denominator;

        uint256 tokenAmountIn = GoatLibrary.getTokenAmountIn(
            wethAmountOut, reserveEth, reserveToken, virtualEth, virtualToken, vestingUntil
        );
        assertEq(tokenAmountIn, expectedAmountIn);
    }

    function testGetTokenAmountInRevertWithInsufficientLiqudity() public {
        uint256 wethAmountOut = 1000;
        uint256 reserveEth = 0;
        uint256 reserveToken = 750e18;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint32 vestingUntil = type(uint32).max;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getTokenAmountIn(wethAmountOut, reserveEth, reserveToken, virtualEth, virtualToken, vestingUntil);
    }

    function testGetTokenAmountInRevertWithInsufficientOutputAmount() public {
        uint256 wethAmountOut = 0;
        uint256 reserveEth = 0;
        uint256 reserveToken = 750e18;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint32 vestingUntil = type(uint32).max;

        vm.expectRevert(GoatErrors.InsufficientOutputAmount.selector);
        GoatLibrary.getTokenAmountIn(wethAmountOut, reserveEth, reserveToken, virtualEth, virtualToken, vestingUntil);
    }

    function testGetWethAmountIn() public {
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint256 reserveWeth = 0;
        uint256 reserveToken = 750e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialTokenMatch = 1000e18;
        uint256 vestingUntil = type(uint32).max;

        uint256 tokenAmountOut = 500e18;

        // BUY FROM PRESALE ONLY
        uint256 actualWethIn = 10e18;
        uint256 expectedWethAmountIn = (actualWethIn * 10000) / 9901;

        uint256 wethAmountIn = GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            virtualEth,
            virtualToken,
            reserveWeth,
            reserveToken,
            bootstrapEth,
            initialTokenMatch,
            vestingUntil
        );

        assertApproxEqRel(wethAmountIn, expectedWethAmountIn, 1);

        // BUY FROM PRESALE AND AMM
        tokenAmountOut = 541666666666666666667;
        actualWethIn = 12e18;
        expectedWethAmountIn = (actualWethIn * 10000) / 9901;

        wethAmountIn = GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            virtualEth,
            virtualToken,
            reserveWeth,
            reserveToken,
            bootstrapEth,
            initialTokenMatch,
            vestingUntil
        );

        assertApproxEqRel(wethAmountIn, expectedWethAmountIn, 1);

        // BUY FROM AMM ONLY
        reserveToken = 250e18;
        vestingUntil = block.timestamp;
        tokenAmountOut = 41666666666666666667;
        reserveWeth = 10e18;

        actualWethIn = 2e18;
        expectedWethAmountIn = (actualWethIn * 10000) / 9901;

        wethAmountIn = GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            virtualEth,
            virtualToken,
            reserveWeth,
            reserveToken,
            bootstrapEth,
            initialTokenMatch,
            vestingUntil
        );

        assertApproxEqRel(wethAmountIn, expectedWethAmountIn, 1);
    }

    function testGetWethAmountInRevertWithInsufficientOutputAmount() public {
        uint256 tokenAmountOut = 0;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint256 reserveWeth = 0;
        uint256 reserveToken = 750e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialTokenMatch = 1000e18;
        uint256 vestingUntil = type(uint32).max;

        vm.expectRevert(GoatErrors.InsufficientOutputAmount.selector);
        GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            virtualEth,
            virtualToken,
            reserveWeth,
            reserveToken,
            bootstrapEth,
            initialTokenMatch,
            vestingUntil
        );
    }

    function testGetWethAmountInRevertWithInsufficientLiquidity() public {
        uint256 tokenAmountOut = 751e18;
        uint256 virtualEth = 10e18;
        uint256 virtualToken = 250e18;
        uint256 reserveWeth = 0;
        uint256 reserveToken = 750e18;
        uint256 bootstrapEth = 10e18;
        uint256 initialTokenMatch = 1000e18;
        uint256 vestingUntil = type(uint32).max;

        vm.expectRevert(GoatErrors.InsufficientLiquidity.selector);
        GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            virtualEth,
            virtualToken,
            reserveWeth,
            reserveToken,
            bootstrapEth,
            initialTokenMatch,
            vestingUntil
        );
    }
}
