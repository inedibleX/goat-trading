// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseTest} from "../BaseTest.t.sol";
import {GoatErrors} from "../../../contracts/library/GoatErrors.sol";
import {GoatV1Pair} from "../../../contracts/exchange/GoatV1Pair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";

contract GoatV1RouterTest is BaseTest {
    function testConstructor() public {
        assertEq(address(router.FACTORY()), address(factory));
        assertEq(address(router.WETH()), address(weth));
    }

    /* ------------------------------ SUCCESS TESTS ADD LIQUIDITY ----------------------------- */
    function testAddLiquditySuccessFirstWithoutWeth() public {
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = _addLiquidityWithoutWeth();
        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 expectedLiquidity = Math.sqrt(10e18 * 1000e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        // erc20 changes
        assertEq(pair.totalSupply(), userLiquidity + 1000);
        assertEq(token.balanceOf(address(pair)), 750e18);
        assertEq(weth.balanceOf(address(pair)), 0);
        //Returned values check
        assertEq(tokenAmtUsed, 1000e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);

        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 10e18); // actually we have 0 ETH but we have to show virtual ETH in reserve
        assertEq(reserveToken, 1000e18);
    }

    function testAddLiquiditySuccessFirstWithSomeWeth() public {
        // get the actual amount with view function
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = _addLiquidityWithSomeWeth();

        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 expectedLiquidity = Math.sqrt(10e18 * 1000e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        assertEq(pair.totalSupply(), userLiquidity + 1000);
        //SIMPLE AMM LOGIC
        uint256 numerator = 5e18 * 1000e18;
        uint256 denominator = 10e18 + 5e18;
        uint256 tokenAmtOut = numerator / denominator;
        uint256 expectedBalInPair = 750e18 - tokenAmtOut;
        assertEq(token.balanceOf(address(pair)), expectedBalInPair);
        assertEq(weth.balanceOf(address(pair)), 5e18);
        // Returned values check
        assertEq(tokenAmtUsed, 1000e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 15e18); // 10e18 virtual + 5e18 actual
            // expected = 1000000000000000000000 - 333333333333333333333  =  666666666666666666667
            // actual=  666666666666666666666
            // uint256 expectedReserveToken = 1000e18 - tokenAmtOut;
            // assertEq(reserveToken, expectedReserveToken);
    }

    function testAddLiquiditySuccessFirstWithAllWeth() public {
        // get the actual amount with view function
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity, uint256 actualTokenAmountToSend) =
            _addLiquidityAndConvertToAmm();

        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        /**
         * @dev if user sends all weth system will automatically get coverted to AMM
         * 10e18 is a real weth reserve and 250e18 is tokens reserve
         * At this point there is nothing vitual in the system
         */
        uint256 expectedLiquidity = Math.sqrt(10e18 * 250e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        assertEq(pair.totalSupply(), userLiquidity + 1000);

        uint256 tokenAmtOut = actualTokenAmountToSend - 250e18; // 750e18 - 250e18 = 500e18
        uint256 expectedBalInPair = actualTokenAmountToSend - tokenAmtOut; // 750e18 - 500e18 = 250e18
        assertEq(token.balanceOf(address(pair)), expectedBalInPair);
        assertEq(weth.balanceOf(address(pair)), 10e18);
        // Returned values check
        assertEq(tokenAmtUsed, 250e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 10e18);
        assertEq(reserveToken, 250e18);
    }

    function testAddLiqudityEthSuccessFirstWithoutEth() public {
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = _addLiquidityWithoutEth();
        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 expectedLiquidity = Math.sqrt(10e18 * 1000e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        assertEq(pair.totalSupply(), userLiquidity + 1000);
        assertEq(token.balanceOf(address(pair)), 750e18);
        assertEq(weth.balanceOf(address(pair)), 0);
        //Returned values check
        assertEq(tokenAmtUsed, 1000e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 10e18); // actually we have 0 ETH but we have to show virtual ETH in reserve
        assertEq(reserveToken, 1000e18);
    }

    function testAddLiqudityEthSuccessFirstWithSomeEth() public {
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = _addLiquidityWithSomeEth();

        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 expectedLiquidity = Math.sqrt(10e18 * 1000e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        assertEq(pair.totalSupply(), userLiquidity + 1000);
        //SIMPLE AMM LOGIC
        uint256 numerator = 5e18 * 1000e18;
        uint256 denominator = 10e18 + 5e18;
        uint256 tokenAmtOut = numerator / denominator;
        uint256 expectedBalInPair = 750e18 - tokenAmtOut;
        assertEq(token.balanceOf(address(pair)), expectedBalInPair);
        assertEq(weth.balanceOf(address(pair)), 5e18);
        // Returned values check
        assertEq(tokenAmtUsed, 1000e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);

        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 15e18); // 10e18 virtual + 5e18 actual
            // expected = 1000000000000000000000 - 333333333333333333333  = 666666666666666666667
            // actual=  666666666666666666666
            // uint256 expectedReserveToken = 1000e18 - tokenAmtOut;
            // assertEq(reserveToken, expectedReserveToken);
    }

    function testAddLiqudityEthSuccessFirstWithAllEth() public {
        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity, uint256 actualTokenAmountToSend) =
            _addLiquidityEthAndConvertToAmm();
        // check how much liqudity is minted to the LP
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        /**
         * @dev if user sends all weth system will automatically get coverted to AMM
         * 10e18 is a real weth reserve and 250e18 is tokens reserve
         * At this point there is nothing vitual in the system
         */
        uint256 expectedLiquidity = Math.sqrt(10e18 * 250e18) - 1000;
        uint256 userLiquidity = pair.balanceOf(addLiqParams.to);
        assertEq(userLiquidity, expectedLiquidity);
        assertEq(pair.totalSupply(), userLiquidity + 1000);

        uint256 tokenAmtOut = actualTokenAmountToSend - 250e18; // 750e18 - 250e18 = 500e18
        uint256 expectedBalInPair = actualTokenAmountToSend - tokenAmtOut; // 750e18 - 500e18 = 250e18
        assertEq(token.balanceOf(address(pair)), expectedBalInPair);
        assertEq(weth.balanceOf(address(pair)), 10e18);
        // Returned values check
        assertEq(tokenAmtUsed, 250e18);
        assertEq(wethAmtUsed, 10e18);
        assertEq(liquidity, expectedLiquidity);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, 10e18);
        assertEq(reserveToken, 250e18);
    }

    function testAddLiquidityWethAfterPesale() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 lpTotalSupply = pair.totalSupply();
        //AT THIS POINT PRESALE IS ENDED
        addLiqParams = addLiquidityParams(false, false); // new params
        // mint tokens to lp
        token.mint(lp_1, 100e18);
        weth.transfer(lp_1, 1e18);
        // Lp provides liqudity
        vm.startPrank(lp_1);
        token.approve(address(router), 100e18);
        weth.approve(address(router), 1e18);
        addLiqParams.to = lp_1; // change to lp
        // (uint256 reserveEth, uint256 reserveToken) = pair.getReserves(); // get reserves before adding liquidity to check for Lp minted later

        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = router.addLiquidity(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
        vm.stopPrank();

        // checks
        assertEq(weth.balanceOf(address(pair)), 11e18); // 10e18 + 1e18
        uint256 optimalTokenAmt = (1e18 * 250e18) / 10e18; // calculate optimal token amount using current reserves
        assertEq(token.balanceOf(address(pair)), 250e18 + optimalTokenAmt);

        // check liquidity
        //TODO: I'm using hardcoded reseves beacasue of stack to deep error, need to change it later wit local vars
        uint256 amtWeth = token.balanceOf(address(pair)) - 10e18; // balance - reserve
        uint256 amtToken = token.balanceOf(address(pair)) - 250e18; // balance - reserve

        uint256 expectedLiquidity = Math.min((amtWeth * lpTotalSupply) / 10e18, (amtToken * lpTotalSupply) / 250e18);
        assertEq(pair.balanceOf(lp_1), expectedLiquidity);
    }

    /* ------------------- CHECK PAIR STATE AFTER ADDLIQUIDITY ------------------ */

    function testCheckPairStateAfterAddLiquidityIfWethSentIsZero() public {
        _addLiquidityWithoutWeth();

        // check  state of pair
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        (
            uint112 reserveEth,
            uint112 reserveToken,
            uint112 virtualEth,
            uint112 initialTokenMatch,
            uint256 bootstrapEth,
            uint256 virtualToken
        ) = pair.getStateInfoForPresale();

        assertEq(reserveEth, 0); // this is a raw reserve, so it reflect the balance, virtual eth is set in getReserves
        assertEq(reserveToken, 750e18);
        assertEq(virtualEth, 10e18);
        assertEq(initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), type(uint32).max);
        assertEq(bootstrapEth, 10e18);
        assertEq(virtualToken, 250e18);
        assertEq(pair.getPresaleBalance(addLiqParams.to), 0);
        GoatTypes.InitialLPInfo memory lpInfo = pair.getInitialLPInfo();
        assertEq(lpInfo.liquidityProvider, addLiqParams.to);
        assertEq(lpInfo.fractionalBalance, 25e18 - 250);
        assertEq(lpInfo.withdrawalLeft, 4);
        assertEq(lpInfo.lastWithdraw, 0);
    }

    function testAddLiqudityEthAfterPresale() public {
        _addLiquidityEthAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(addLiqParams.token));
        uint256 lpTotalSupply = pair.totalSupply();
        //AT THIS POINT PRESALE IS ENDED
        addLiqParams = addLiquidityParams(false, false); // new params
        // mint tokens to lp
        token.mint(lp_1, 100e18);
        vm.deal(lp_1, 1e18);
        // Lp provides liqudity
        vm.startPrank(lp_1);
        token.approve(address(router), 100e18);
        addLiqParams.to = lp_1; // change to lp
        // (uint256 reserveEth, uint256 reserveToken) = pair.getReserves(); // get reserves before adding liquidity to check for Lp minted later

        (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity) = router.addLiquidityETH{value: 1e18}(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
        vm.stopPrank();

        // checks
        assertEq(weth.balanceOf(address(pair)), 11e18); // 10e18 + 1e18
        uint256 optimalTokenAmt = (1e18 * 250e18) / 10e18; // calculate optimal token amount using current reserves
        assertEq(token.balanceOf(address(pair)), 250e18 + optimalTokenAmt);

        // check liquidity
        //TODO: I'm using hardcoded reseves beacasue of stack to deep error, need to change it later wit local vars
        uint256 amtWeth = token.balanceOf(address(pair)) - 10e18; // balance - reserve
        uint256 amtToken = token.balanceOf(address(pair)) - 250e18; // balance - reserve

        uint256 expectedLiquidity = Math.min((amtWeth * lpTotalSupply) / 10e18, (amtToken * lpTotalSupply) / 250e18);
        assertEq(pair.balanceOf(lp_1), expectedLiquidity);
        assertEq(lp_1.balance, 0); // No balance left
    }

    /* ------------------------------ REVERTS TESTS ADD LIQUIDITY AT ROUTER LEVEL----------------------------- */

    function testRevertIfTokenIsWeth() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false);
        addLiqParams.token = address(weth);
        token.approve(address(router), addLiqParams.tokenDesired);
        weth.approve(address(router), addLiqParams.wethDesired);
        vm.expectRevert(GoatErrors.WrongToken.selector);
        router.addLiquidity(
            address(weth),
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function testRevertIfTokenIsZeroAddress() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false);
        addLiqParams.token = address(weth);
        token.approve(address(router), addLiqParams.tokenDesired);
        weth.approve(address(router), addLiqParams.wethDesired);
        vm.expectRevert(GoatErrors.WrongToken.selector);
        router.addLiquidity(
            address(0),
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function testRevertIfDeadlineIsPassed() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false);
        vm.expectRevert(GoatErrors.Expired.selector);
        router.addLiquidity(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            block.timestamp - 1,
            addLiqParams.initParams
        );
    }

    function testRevertIfNotEnoughTokenIsApprovedToRouter() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend - 1);
        vm.expectRevert("ERC20: insufficient allowance"); // erc20 revert
        router.addLiquidity(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function testRevertIfNotEnoughEthIsSent() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, true);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);
        vm.expectRevert(GoatErrors.InvalidEthAmount.selector);
        router.addLiquidityETH{value: addLiqParams.initParams.initialEth - 1}(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function testRevertIfInitialAmountIsSetToZeroButSomeEthIsSent() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false); // no initial eth
        addLiqParams.initParams.initialEth = 0;
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);
        vm.expectRevert(); // throw panic revert
        router.addLiquidityETH{value: 1e18}( // some eth is sent which is not needed
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    /* ------------------------------ REVERTS TESTS ADD LIQUIDITY AT PAIR LEVEL----------------------------- */

    function testRevertIfAddLiquidityInPresalePeriod() public {
        BaseTest.AddLiquidityParams memory addLiqParams = addLiquidityParams(true, false);

        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);
        router.addLiquidity(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
        // Still in presale period
        // Try to add liquidity again
        addLiqParams = addLiquidityParams(false, false);
        token.mint(lp_1, 100e18);
        weth.transfer(lp_1, 1e18);
        vm.startPrank(lp_1);
        token.approve(address(router), addLiqParams.tokenDesired);
        weth.approve(address(router), addLiqParams.wethDesired);
        vm.expectRevert(GoatErrors.PresalePeriod.selector);
        router.addLiquidity(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.wethDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
        vm.stopPrank();
    }

    /* ------------------------------- REMOVE LIQUDITY SUCCESS TESTS ------------------------------- */

    function testRemoveLiquiditySuccess() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));

        uint256 balanceToken = token.balanceOf(address(pair));
        uint256 balanceEth = weth.balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();
        uint256 userLiquidity = pair.balanceOf(address(this));
        pair.approve(address(router), userLiquidity);
        // remove liquidity
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        uint256 fractionalLiquidity = userLiquidity / 4;
        (uint256 amountWeth, uint256 amountToken) =
            router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        uint256 expectedWeth = (fractionalLiquidity * balanceEth) / totalSupply;
        uint256 expectedToken = (fractionalLiquidity * balanceToken) / totalSupply;
        assertEq(amountWeth, expectedWeth);
        assertEq(amountToken, expectedToken);
        assertEq(pair.balanceOf(address(this)), userLiquidity - fractionalLiquidity);
        uint256 currentTotalSupply = totalSupply - fractionalLiquidity;
        assertEq(pair.totalSupply(), currentTotalSupply);
        assertEq(token.balanceOf(address(pair)), balanceToken - expectedToken);
        assertEq(weth.balanceOf(address(pair)), balanceEth - expectedWeth);

        assertEq(weth.balanceOf(lp_1), expectedWeth);
        assertEq(token.balanceOf(lp_1), expectedToken);
    }

    function testRemoveLiquidityEth() public {
        _addLiquidityEthAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 balanceToken = token.balanceOf(address(pair));
        uint256 balanceEth = weth.balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();
        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 userEthBalBefore = lp_1.balance;
        pair.approve(address(router), userLiquidity);
        // remove liquidity
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        uint256 fractionalLiquidity = userLiquidity / 4;
        (uint256 amountWeth, uint256 amountToken) =
            router.removeLiquidityETH(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        uint256 expectedEth = (fractionalLiquidity * balanceEth) / totalSupply;
        uint256 expectedToken = (fractionalLiquidity * balanceToken) / totalSupply;
        assertEq(amountWeth, expectedEth);
        assertEq(amountToken, expectedToken);
        assertEq(pair.balanceOf(address(this)), userLiquidity - fractionalLiquidity);
        uint256 currentTotalSupply = totalSupply - fractionalLiquidity;
        assertEq(pair.totalSupply(), currentTotalSupply);
        assertEq(lp_1.balance, userEthBalBefore + expectedEth);
        assertEq(token.balanceOf(lp_1), expectedToken);
    }

    function testRemoveLiquidityUpdateFeesForLpIfSwapIsDone() public {
        /**
         * @dev lp add initial liqudity and someone swaps before presale ends, the initial Lp should be able
         *     to claim his fees from swap after the presale ends
         */
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 5e18);

        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        uint256 amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();

        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 fractionalLiquidity = userLiquidity / 4;
        pair.approve(address(router), fractionalLiquidity);
        // forward time to remove lock
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        uint256 lpfeess = (fees * 40) / 100;
        uint256 feePerTokenStored = (lpfeess * 1e18) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), feePerTokenStored);
        vm.warp(block.timestamp + 2 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        // check fees
        uint256 totalLpFees = (fees * 40) / 100;
        assertEq(pair.getPendingLiquidityFees(), totalLpFees);
        uint256 lpFees = pair.lpFees(address(this));

        assertEq(totalLpFees - 1, lpFees);
    }

    function testRemoveLiquidityAllInFourWeeks() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 fractionalLiquidity = userLiquidity / 4;
        pair.approve(address(router), userLiquidity);
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        // See what happens when he tries to remove liqudity without reaching cooldown end
        vm.warp(block.timestamp + 7 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
        vm.warp(block.timestamp + 7 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        vm.warp(block.timestamp + 7 days);
        uint256 userLastRemainingLiquidity = pair.balanceOf(address(this));

        router.removeLiquidity(address(token), userLastRemainingLiquidity, 0, 0, lp_1, block.timestamp);

        uint256 expectedTokenBalAfterAllRemoval = 250e18;
        uint256 expectedEthBalAfterAllRemoval = 10e18;
        //@dev we have 1000 liquidity minted to zero addresss so removed < expected
        assertLt(token.balanceOf(lp_1), expectedTokenBalAfterAllRemoval);
        assertLt(weth.balanceOf(lp_1), expectedEthBalAfterAllRemoval);
    }

    /* ------------------------------ REVERTS TESTS REMOVE LIQUIDITY ----------------------------- */

    function testRevertIfRemoveLiquidityInPresale() public {
        _addLiquidityWithSomeWeth();
        vm.warp(block.timestamp + 2 days); // forward time to remove lock
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 fractionalLiquidity = pair.balanceOf(address(this)) / 4;
        pair.approve(address(router), fractionalLiquidity);
        vm.expectRevert(GoatErrors.PresalePeriod.selector);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    function testRevertIfRemoveLiquidityInLockPeriod() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 fractionalLiquidity = pair.balanceOf(address(this)) / 4;
        pair.approve(address(router), fractionalLiquidity);
        vm.expectRevert(GoatErrors.LiquidityLocked.selector);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    function testRevertIfRemoveLiquidityEthInPresale() public {
        _addLiquidityWithSomeEth();
        vm.warp(block.timestamp + 2 days); // forward time to remove lock
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 fractionalLiquidity = pair.balanceOf(address(this)) / 4;
        pair.approve(address(router), fractionalLiquidity);
        vm.expectRevert(GoatErrors.PresalePeriod.selector);
        router.removeLiquidityETH(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    function testRevertIfRemoveLiquidityEthInLockPeriod() public {
        _addLiquidityEthAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 fractionalLiquidity = pair.balanceOf(address(this)) / 4;
        pair.approve(address(router), fractionalLiquidity);
        vm.expectRevert(GoatErrors.LiquidityLocked.selector);
        router.removeLiquidityETH(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    function testRevertIfRemoveLiquidityDuringCooldown() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 fractionalLiquidity = userLiquidity / 4;
        pair.approve(address(router), fractionalLiquidity);
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        // See what happens when he tries to remove liqudity without reaching cooldown end
        vm.warp(block.timestamp + 6 days);
        pair.approve(address(router), fractionalLiquidity);
        vm.expectRevert(GoatErrors.WithdrawalCooldownActive.selector);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    function testRemoveLiquidityRevertIfLastWithdrawIsLessThanBalanceOfLp() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 fractionalLiquidity = userLiquidity / 4;
        pair.approve(address(router), userLiquidity);
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        vm.warp(block.timestamp + 7 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
        vm.warp(block.timestamp + 7 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);

        vm.warp(block.timestamp + 7 days);

        uint256 userLastRemainingLiquidity = pair.balanceOf(address(this));
        // sending 1 wei less than actual balance should cause revert
        fractionalLiquidity = userLastRemainingLiquidity - 1;

        vm.expectRevert(GoatErrors.ShouldWithdrawAllBalance.selector);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
    }

    /* ------------------------------- SWAP TESTS WETH-TOKEN------------------------------ */

    function testSwapWethToTokenSuccessInPresaleWithoutInitialWeth() public {
        _addLiquidityWithoutWeth();
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        uint256 amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        //calculate amt out after deducting fee
        uint256 numerator = (5e18 - fees) * (250e18 + 750e18);
        uint256 denominator = (0 + 10e18) + (5e18 - fees);
        uint256 expectedAmountOut = numerator / denominator;
        assertEq(amountOut, expectedAmountOut);
    }

    function testCheckStateAfterSwapWethToTokenSuccessInPresaleWithoutInitialWeth() public {
        _addLiquidityWithoutWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        uint256 amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;
        assertEq(token.balanceOf(swapper), amountOut);
        assertEq(weth.balanceOf(swapper), 0);
        // Checks if fees are updated
        assertEq(pair.getPendingLiquidityFees(), 0); // 40% of fees
        assertEq(pair.getPendingProtocolFees(), (fees * 60) / 100); // 60% of fees
        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        uint256 amountIn = 5e18;
        uint256 reserveOld = 750e18;
        assertEq(vars.reserveEth, amountIn - protocolFee);
        assertEq(vars.reserveToken, reserveOld - amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), type(uint32).max);
        assertEq(vars.bootstrapEth, 10e18);
        assertEq(vars.virtualToken, 250e18);
    }

    function testSwapWethToTokenSuccessInPresaleWithSomeInitialWeth() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();

        weth.transfer(swapper, 2e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 2e18);
        uint256 amountOut = router.swapWethForExactTokens(
            2e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (2e18 * 99) / 10000; // 1% fee
        uint256 numerator = (2e18 - fees) * (vars.virtualToken + vars.reserveToken);
        uint256 denominator = (vars.reserveEth + vars.virtualEth) + (2e18 - fees);
        uint256 expectedAmountOut = numerator / denominator;
        assertEq(amountOut, expectedAmountOut);
    }

    function testCheckStateAfterSwapWethToTokenSuccessInPresaleWithSomeInitialWeth() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 2e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 2e18);
        uint256 amountOut = router.swapWethForExactTokens(
            2e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (2e18 * 99) / 10000; // 1% fee
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;

        assertEq(token.balanceOf(swapper), amountOut);
        assertEq(weth.balanceOf(swapper), 0);
        // Checks if fees are updated
        assertEq(pair.getPendingLiquidityFees(), 0);
        assertEq(pair.getPendingProtocolFees(), protocolFee); // 60% of fees
        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        uint256 amountIn = 2e18;
        uint256 ethReserveOld = 5e18; // intial eth send by first Lp(no fee is charge when intializing with some weth)
        uint256 reserveOld = 416666666666666666667; // 750e18 - 333333333333333333333
        assertEq(vars.reserveEth, ethReserveOld + amountIn - protocolFee);
        assertEq(vars.reserveToken, reserveOld - amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), type(uint32).max);
    }

    function testSwapWethToTokenSuccessInPresaleWithAllInitialWeth() public {
        _addLiquidityAndConvertToAmm(); // convert directly to amm
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        uint256 amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        uint256 numerator = (5e18 - fees) * (250e18);
        uint256 denominator = 10e18 + (5e18 - fees);
        uint256 expectedAmountOut = numerator / denominator;
        assertEq(amountOut, expectedAmountOut);
    }

    function testCheckStateAfterSwapWethToTokenSuccessInPresaleWithAllInitialWeth() public {
        _addLiquidityAndConvertToAmm(); // convert directly to amm
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        uint256 amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        assertEq(token.balanceOf(swapper), amountOut);
        assertEq(weth.balanceOf(swapper), 0);
        // Checks if fees are updated
        assertEq(fees, pair.getPendingLiquidityFees() + pair.getPendingProtocolFees());
        assertEq(pair.getPendingLiquidityFees(), (fees * 40) / 100); // 40% of fees
        assertEq(pair.getPendingProtocolFees(), (fees * 60) / 100); // 60% of fees
        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        uint256 amountIn = 5e18;
        uint256 reserveOld = 250e18;
        uint256 ethReserveOld = 10e18; // intial eth send by first Lp
        assertEq(vars.reserveEth, ethReserveOld + amountIn - fees);
        assertEq(vars.reserveToken, reserveOld - amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), block.timestamp + 7 days);
        uint256 userPresaleBalance = pair.getPresaleBalance(swapper);
        assertEq(userPresaleBalance, amountOut);
    }

    function testSwapWethToTokenAndConvertPresaleToAmmFailWithExactBootstrapAmountBecauseOfFees() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        /**
         * @dev even after providing  5e18 making the eth balanace in pair == bootstrap Amount,
         * the fees will be deducted from the amountIn and
         * the actual amountIn will be less making the bootstrap amount < reserveEth(not balance Weth)
         */
        assertEq(pair.vestingUntil(), type(uint32).max);
    }

    function testSwapWethToTokenAndConvertPresaleToAmm() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        weth.transfer(swapper, 10e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 10e18);
        uint256 amountOut = router.swapWethForExactTokens(
            10e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        // Now pool is converted to AMM
        assertEq(pair.vestingUntil(), block.timestamp + 7 days); // vesting period is set
        /**
         * @dev only 5e18 + fees, is needed to make the reserveEth == bootstrapEth and convert the pool to AMM
         * remaining will be swapped in a AMM with actual reserves
         */
        uint256 amtIn = 10e18;
        uint256 amountWithFee = (amtIn * 9901) / 10000; // 1% fee
        uint256 wethForAmm = vars.reserveEth + amountWithFee - vars.bootstrapEth;
        // Amount out for presale
        uint256 wethForPresale = amountWithFee - wethForAmm;
        uint256 numerator = wethForPresale * (vars.virtualToken + vars.reserveToken);
        uint256 denominator = vars.virtualEth + vars.reserveEth + wethForPresale;
        uint256 expectedAmountOutPresale = numerator / denominator;
        // Amount out for AMM
        uint256 reserveTokenForAmm = 250e18;
        numerator = wethForAmm * reserveTokenForAmm;
        denominator = vars.bootstrapEth + wethForAmm;
        uint256 expectedAmountOutAmm = numerator / denominator;
        assertEq(amountOut, expectedAmountOutPresale + expectedAmountOutAmm);
        assertEq(token.balanceOf(swapper), amountOut);
        assertEq(weth.balanceOf(address(pair)), 15e18);
        assertGt(token.balanceOf(address(pair)), 150e18);
    }

    function testSwapWethToTokenShouldNotSetPresaleBalanceIfVestingIsEnded() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.warp(block.timestamp + 31 days); // forward time to end vesting
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        router.swapWethForExactTokens(5e18, 0, address(token), swapper, block.timestamp);
        vm.stopPrank();
        assertEq(pair.getPresaleBalance(swapper), 0);
    }

    function testAddLiqudityForNormalUser() public {
        _addLiquidityAndConvertToAmm();

        address normalLp = address(0x123);
        weth.transfer(normalLp, 5e18);

        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        (uint256 wethReserve, uint256 tokenReserve) = pair.getReserves();
        uint256 quoteToken = GoatLibrary.quote(5e18, wethReserve, tokenReserve);
        token.mint(normalLp, quoteToken);
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(
            0, // virtualEth
            0, // bootstrapEth
            0, // initialEth
            0 // initialTokenMatch
        );
        uint256 totalSupply = pair.totalSupply();
        vm.startPrank(normalLp);
        weth.approve(address(router), 5e18);
        token.approve(address(router), quoteToken);
        (,, uint256 liquidity) =
            router.addLiquidity(address(token), quoteToken, 5e18, 0, 0, normalLp, block.timestamp, initParams);
        uint256 liquidityUsingWeth = (5e18 * totalSupply) / wethReserve;
        uint256 liquidityUsingToken = (quoteToken * totalSupply) / tokenReserve;
        uint256 expectedLiquidity = liquidityUsingWeth < liquidityUsingToken ? liquidityUsingWeth : liquidityUsingToken; // min
        assertEq(liquidity, expectedLiquidity);

        vm.stopPrank();
    }

    function testProtocolFeesTransferToTreasuryAfteCertainAmount() public {
        // Change the treasury address
        address newTreasury = makeAddr("treasury");
        factory.setTreasury(newTreasury);
        vm.startPrank(newTreasury);
        factory.acceptTreasury();
        vm.stopPrank();

        _addLiquidityAndConvertToAmm();
        weth.transfer(swapper, 50e18);
        vm.startPrank(swapper);
        weth.approve(address(router), 50e18);
        //Swap large amount to met the reuired 0.1 treshold
        router.swapWethForExactTokens(50e18, 0, address(token), swapper, block.timestamp);
        vm.stopPrank();
        uint256 fees = (50e18 * 99) / 10000; // 1% fee
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;
        uint256 treasuryBalAfterFee = weth.balanceOf(newTreasury);
        assertEq(treasuryBalAfterFee, protocolFee);
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        assertEq(pair.getPendingProtocolFees(), 0);
        assertEq(pair.getPendingLiquidityFees(), liquidityFee);
    }

    /* ---------------------------- SWAP WETH-TOKEN REVERT TESTS --------------------------- */

    function testSwapWethToTokenRevertsIfPoolDoesNotExist() public {
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        vm.expectRevert(GoatErrors.GoatPoolDoesNotExist.selector);
        router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapWethToTokenRevertIfAmountOutLessThenExpected() public {
        _addLiquidityWithSomeWeth();
        weth.transfer(swapper, 5e18); // send some weth to swapper
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        vm.expectRevert(GoatErrors.InsufficientAmountOut.selector);
        router.swapWethForExactTokens(
            5e18,
            300e18, // amountOutMin is set higher
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    /* -------------------------- SWAP TEST ETH-TOKEN -------------------------- */
    function testSwapEthToTokenSuccess() public {
        _addLiquidityWithoutWeth();
        vm.deal(swapper, 5e18); // send some eth to swapper
        vm.startPrank(swapper);
        uint256 amountOut = router.swapExactETHForTokens{value: 5e18}(0, address(token), swapper, block.timestamp);
        vm.stopPrank();
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        //calculate amt out after deducting fee
        uint256 numerator = (5e18 - fees) * (250e18 + 750e18);
        uint256 denominator = (0 + 10e18) + (5e18 - fees);
        uint256 expectedAmountOut = numerator / denominator;
        assertEq(amountOut, expectedAmountOut);
    }

    function testSwapEthToTokenRevertIfZeroValueProvided() public {
        _addLiquidityWithoutWeth();
        vm.deal(swapper, 5e18); // send some eth to swapper
        vm.startPrank(swapper);
        // More value,less amountIn
        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        uint256 amountOut = router.swapExactETHForTokens{value: 0}(0, address(token), swapper, block.timestamp);
        vm.stopPrank();
    }

    //@note: these two tests should be enough, because all other functionality is same and we already tested it

    /* -------------------------- SWAP TEST TOKEN-WETH -------------------------- */
    function _swapWethToToken() internal returns (uint256 amountOut) {
        weth.transfer(swapper, 5e18);
        vm.startPrank(swapper);
        weth.approve(address(router), 5e18);
        amountOut = router.swapWethForExactTokens(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapTokenToWethSuccessInPresaleWithoutInitialWeth() public {
        /**
         * @dev to swap from token to weth, user should have bought in in a presale period and vest until 30 days
         * No exteral tokens sell is allowed until vesting period is passed
         */
        _addLiquidityWithoutWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        uint256 feesBefore = pair.getPendingLiquidityFees() + pair.getPendingProtocolFees();
        uint256 protocolFeesBefore = pair.getPendingProtocolFees();
        assert(feesBefore > 0); // should have some fees
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();

        uint256 fees = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 feesAfter = feesBefore + fees;
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;
        assertEq(pair.getPendingLiquidityFees(), 0);
        assertEq(pair.getPendingProtocolFees(), protocolFeesBefore + protocolFee);

        assertEq(pair.getPendingLiquidityFees() + pair.getPendingProtocolFees(), feesAfter - liquidityFee);

        // Check expected amout out to actual amount out
        uint256 feesOnFirstSwap = (5e18 * 99) / 10000; // 1% fee
        uint256 liquidityFeeOnFirstSwap = (feesOnFirstSwap * 40) / 100;
        uint256 protocolFeeOnFirstSwap = feesOnFirstSwap - liquidityFeeOnFirstSwap;

        uint256 wethReserveAfterFirstSwap = 5e18 - protocolFeeOnFirstSwap; // 5e18 - protocolFeeOnFirstSwap
        uint256 numerator = amountOut * (10e18 + wethReserveAfterFirstSwap); // amountIn * virtualEth + reserveEth
        uint256 denominator = (250e18 + 418873950703989833116) + amountOut; // virtualToken + reserveToken + amountIn
        uint256 expectedAmountWethOut = numerator / denominator;
        expectedAmountWethOut = (expectedAmountWethOut * 9901) / 10000; // 1% fee
        assertEq(amountWethOut, expectedAmountWethOut);
    }

    function testCheckStateAfterSwapTokenToWethSuccessInPresaleWithoutInitialWeth() public {
        _addLiquidityWithoutWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));

        uint256 amountOut = _swapWethToToken();
        assertEq(pair.getPresaleBalance(swapper), amountOut);
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();

        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        //Fees charged on first swap
        uint256 feesOnFirstSwap = (5e18 * 99) / 10000; // 1% fee
        uint256 liquidityFeeOnFirstSwap = (feesOnFirstSwap * 40) / 100;
        uint256 protocolFeeOnFirstSwap = feesOnFirstSwap - liquidityFeeOnFirstSwap;
        uint256 wethReserveAfterFirstSwap = 5e18 - protocolFeeOnFirstSwap;
        // Fee charged on this swap
        uint256 feesAmountOut = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 liquidityFeeOnCurrentSwap = (feesAmountOut * 40) / 100;
        uint256 protocolFeeOnCurrentSwap = feesAmountOut - liquidityFeeOnCurrentSwap;
        uint256 reserveTokenBefore = 418873950703989833116;
        assertEq(vars.reserveEth, wethReserveAfterFirstSwap - amountWethOut - protocolFeeOnCurrentSwap);
        assertEq(vars.reserveToken, reserveTokenBefore + amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), type(uint32).max);
        assertEq(vars.bootstrapEth, 10e18);
        assertEq(vars.virtualToken, 250e18);
        uint256 userPresaleBalance = pair.getPresaleBalance(swapper);
        assertEq(userPresaleBalance, 0);
    }

    function testSwapTokenToWethSuccessInPresaleWithSomeInitialWeth() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        uint256 liquidityFeesbefore = pair.getPendingLiquidityFees();
        uint256 protocolFeesBefore = pair.getPendingProtocolFees();

        uint256 feesBefore = pair.getPendingLiquidityFees() + pair.getPendingProtocolFees();
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();

        uint256 fees = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;
        uint256 feesAfter = feesBefore + protocolFee;
        assertEq(pair.getPendingLiquidityFees(), 0); // no liquidity fees on presale
        assertEq(pair.getPendingProtocolFees(), protocolFeesBefore + protocolFee);

        assertEq(pair.getPendingLiquidityFees() + pair.getPendingProtocolFees(), feesAfter);
        //@dev fee is only charged on swap not on initial deposit
        uint256 feeOnFirstSwap = (5e18 * 99) / 10000;
        uint256 liquidityFeeOnFirstSwap = (feeOnFirstSwap * 40) / 100;
        uint256 protocolFeeOnFirstSwap = feeOnFirstSwap - liquidityFeeOnFirstSwap;
        uint256 wethReserveAfterFirstActualSwap = 10e18 - protocolFeeOnFirstSwap; // only protocol fee is charged on presale
        uint256 numerator = amountOut * (10e18 + wethReserveAfterFirstActualSwap);
        uint256 denominator = (250e18 + 251240570411769128594) + amountOut; // we have 251 token reserve,this is just a wei's to become AMM
        uint256 expectedAmountWethOut = numerator / denominator;
        expectedAmountWethOut = (expectedAmountWethOut * 9901) / 10000; // 1% fee
        assertEq(amountWethOut, expectedAmountWethOut);
    }

    function testCheckStateAfterSwapTokenToWethSuccessInPresaleWithSomeInitialWeth() public {
        _addLiquidityWithSomeWeth();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        assertEq(pair.getPresaleBalance(swapper), amountOut);
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        // Fees charge on first swap
        uint256 feeOnFirstSwap = (5e18 * 99) / 10000;
        uint256 liquidityFeeOnFirstSwap = (feeOnFirstSwap * 40) / 100;
        uint256 protocolFeeOnFirstSwap = feeOnFirstSwap - liquidityFeeOnFirstSwap;
        uint256 wethReserveAfterFirstActualSwap = 10e18 - protocolFeeOnFirstSwap; // only protocol fee is charged on presale
        //Fee charged on this current swap in on amountWethOut
        uint256 feesAmountOut = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 liqudityFeeOnCurrentSwap = (feesAmountOut * 40) / 100;
        uint256 protocolFeeOnCurrentSwap = feesAmountOut - liqudityFeeOnCurrentSwap;

        uint256 reserveTokenBefore = 251240570411769128594;
        assertEq(vars.reserveEth, wethReserveAfterFirstActualSwap - amountWethOut - protocolFeeOnCurrentSwap);
        assertEq(vars.reserveToken, reserveTokenBefore + amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), type(uint32).max);
        assertEq(vars.bootstrapEth, 10e18);
        assertEq(vars.virtualToken, 250e18);
        uint256 userPresaleBalance = pair.getPresaleBalance(swapper);
        assertEq(userPresaleBalance, 0);
    }

    function testSwapTokenToWethSuccessInAmm() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        uint256 liquidityFeesbefore = pair.getPendingLiquidityFees();
        uint256 protocolFeesBefore = pair.getPendingProtocolFees();
        uint256 feesBefore = pair.getPendingLiquidityFees() + pair.getPendingProtocolFees();
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();

        uint256 fees = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;
        uint256 feesAfter = feesBefore + fees;
        assertEq(pair.getPendingLiquidityFees(), liquidityFeesbefore + liquidityFee);
        assertEq(pair.getPendingProtocolFees(), protocolFeesBefore + protocolFee);

        assertEq(pair.getPendingLiquidityFees() + pair.getPendingProtocolFees(), feesAfter);
        //@dev We do have a different amountOut calculation for AMM
        uint256 wethReserveAfterFirstActualSwap = 15e18 - (5e18 * 99) / 10000; // 5e18 - fees
        uint256 numerator = amountOut * wethReserveAfterFirstActualSwap; // amountIn  * reserveEth
        uint256 denominator = (167218487675997458279 + amountOut);
        //@dev 167218487675997458279 is the reserveToken after the first swap, i.e swap 5e18 weth for 250e18 tokens
        uint256 expectedAmountWethOut = numerator / denominator;
        expectedAmountWethOut = (expectedAmountWethOut * 9901) / 10000; // 1% fee

        assertEq(amountWethOut, expectedAmountWethOut);
    }

    function testCheckStateAfterSwapTokenToWethSuccessInAmm() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        // First swap fees
        uint256 fees = (5e18 * 99) / 10000; // 1% fee
        uint256 liquidityFee = (fees * 40) / 100;
        uint256 protocolFee = fees - liquidityFee;

        assertEq(pair.getPresaleBalance(swapper), amountOut);
        // Now swap token to weth
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        uint256 amountWethOut = router.swapExactTokensForWeth(
            amountOut, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        uint256 scale = 1e18;
        uint256 expectedFeePerToken = (pair.getPendingLiquidityFees() * scale) / pair.totalSupply();
        assertEq(pair.feesPerTokenStored(), expectedFeePerToken);
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();
        // current swap fees
        uint256 feesAmountOut = (amountWethOut * 10000) / 9901 - amountWethOut;
        uint256 liquidityFeeOnCurrentSwap = (feesAmountOut * 40) / 100;
        uint256 protocolFeeOnCurrentSwap = feesAmountOut - liquidityFeeOnCurrentSwap;

        uint256 wethReserveAfterFirstActualSwap = 15e18 - fees;
        uint256 reserveTokenBefore = 167218487675997458279;

        assertEq(vars.reserveEth, wethReserveAfterFirstActualSwap - amountWethOut - feesAmountOut);
        assertEq(vars.reserveToken, reserveTokenBefore + amountOut);
        assertEq(vars.virtualEth, 10e18);
        assertEq(vars.initialTokenMatch, 1000e18);
        assertEq(pair.vestingUntil(), block.timestamp + 7 days);
        uint256 userPresaleBalance = pair.getPresaleBalance(swapper);
        assertEq(userPresaleBalance, 0);
        assertEq(pair.getPendingLiquidityFees(), liquidityFee + liquidityFeeOnCurrentSwap);
        assertEq(pair.getPendingProtocolFees(), protocolFee + protocolFeeOnCurrentSwap);
    }

    function testSwapTokenToWethShouldNotSetPresaleBalanceIfVestingIsEnded() public {
        _addLiquidityAndConvertToAmm();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 amountOut = _swapWethToToken();
        vm.warp(block.timestamp + 31 days); // forward time to end vesting
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        router.swapExactTokensForWeth(
            amountOut, // amountIn
            0,
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
        assertEq(pair.getPresaleBalance(swapper), amountOut); // Old presale balance
    }

    function testSwapTokenToWethIsAllowedToEveryoneAfterVestingDuration() public {
        _addLiquidityAndConvertToAmm();
        uint256 timestamp = block.timestamp + 31 days;
        vm.warp(timestamp); // forward time to end vesting
        // Now swap token to weth
        token.mint(swapper, 100e18);
        vm.startPrank(swapper);
        token.approve(address(router), 100e18);
        router.swapExactTokensForWeth(
            100e18, // amountIn
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    /* ------------------------- TEST SWAP TOKEN-WETH REVERTS ------------------------ */

    function testSwapTokenToWethRevertIfPoolDoesNotExist() public {
        vm.startPrank(swapper);
        token.approve(address(router), 5e18);
        vm.expectRevert(GoatErrors.GoatPoolDoesNotExist.selector);
        router.swapExactTokensForWeth(
            5e18,
            0, // no slippage protection for now
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapTokenToWethRevertIfAmountOutLessThenExpected() public {
        _addLiquidityWithSomeWeth();
        uint256 amountOut = _swapWethToToken();
        vm.startPrank(swapper);
        token.approve(address(router), amountOut);
        vm.expectRevert(GoatErrors.InsufficientAmountOut.selector);
        router.swapExactTokensForWeth(
            amountOut,
            300e18, // amountOutMin is set higher
            address(token),
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapTokenToWethRevertIfTokenNotBoughtInPresale() public {
        /**
         * @notice The `to` address of params should hold the tokens bought in presale
         * If `to` address doesn't have a enough tokens bought in presale, the swap will revert because of underflow
         * Also note that the actual swapper and the `to` address can be different and it is upon the user to provide the correct address, if they provide others users address who holds the presale token balance, than the swap will not revert and actual user will loose the weth
         */
        _addLiquidityWithSomeWeth();
        token.mint(swapper, 100e18);
        vm.startPrank(swapper);
        token.approve(address(router), 100e18);
        vm.expectRevert(); // revert because of underflow
        router.swapExactTokensForWeth(
            100e18,
            0, // no slippage protection for now
            address(token),
            swapper, // this address should have some tokens bought in presale
            block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapTokenToWethRevertIfAmountInIsZero() public {
        _addLiquidityWithSomeWeth();
        token.mint(swapper, 100e18);
        vm.startPrank(swapper);
        token.approve(address(router), 100e18);
        vm.expectRevert(GoatErrors.InsufficientInputAmount.selector);
        router.swapExactTokensForWeth(
            0,
            0, // no slippage protection for now
            address(token),
            swapper, // this address should have some tokens bought in presale
            block.timestamp
        );
        vm.stopPrank();
    }

    /* --------------------------- WITHDRAW FEES TEST --------------------------- */

    function testWithdrawFeeSuccess() public {
        _addLiquidityAndConvertToAmm();
        _swapWethToToken();
        GoatV1Pair pair = GoatV1Pair(factory.getPool(address(token)));
        uint256 userLiquidity = pair.balanceOf(address(this));
        uint256 fractionalLiquidity = userLiquidity / 4;
        pair.approve(address(router), fractionalLiquidity);
        // forward time to remove lock
        vm.warp(block.timestamp + 2 days);
        router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, lp_1, block.timestamp);
        uint256 liquidityFee = pair.getPendingLiquidityFees();
        uint256 userFeeAccured = pair.lpFees(address(this));
        // Deduct 1 wei for minimum liquidity mint
        assertEq(liquidityFee - 1, userFeeAccured);
        uint256 balanceBefore = weth.balanceOf(address(this));
        router.withdrawFees(address(token), address(this));
        assertEq(weth.balanceOf(address(this)), balanceBefore + userFeeAccured);
        assertEq(pair.lpFees(address(this)), 0);

        // See what happens when he tries to remove liqudity again after 1 week
        vm.warp(block.timestamp + 7 days);
        uint256 balanceBefore2 = weth.balanceOf(address(this));
        pair.approve(address(router), fractionalLiquidity);
        (uint256 amountWethOut,) =
            router.removeLiquidity(address(token), fractionalLiquidity, 0, 0, address(this), block.timestamp);
        router.withdrawFees(address(token), address(this));
        assertEq(weth.balanceOf(address(this)), balanceBefore2 + amountWethOut); // No fees should be there
    }
}
