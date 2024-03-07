// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../../contracts/exchange/GoatV1Pair.sol";
import "../../../contracts/exchange/GoatV1Factory.sol";
import "../../../contracts/mock/MockWETH.sol";
import "../../../contracts/mock/MockERC20.sol";
import "../../../contracts/library/GoatTypes.sol";
import "../../../contracts/library/GoatLibrary.sol";
import "../../../contracts/library/GoatErrors.sol";

struct Users {
    address whale;
    address alice;
    address bob;
    address lp;
    address lp1;
    address treasury;
}

contract GoatExchangeTest is Test {
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint32 private constant _MAX_UINT32 = type(uint32).max;
    uint32 private constant _VESTING_PERIOD = 7 days;
    GoatV1Factory factory;
    GoatV1Pair pair;
    MockERC20 goat;
    MockWETH weth;
    Users users;

    function setUp() public {
        users = Users({
            whale: makeAddr("whale"),
            alice: makeAddr("alice"),
            bob: makeAddr("bob"),
            lp: makeAddr("lp"),
            lp1: makeAddr("lp1"),
            treasury: makeAddr("treasury")
        });
        vm.warp(300 days);

        vm.startPrank(users.whale);
        weth = new MockWETH();
        goat = new MockERC20();
        vm.stopPrank();
        vm.startPrank(users.treasury);
        factory = new GoatV1Factory(address(weth));
        vm.stopPrank();
    }

    function _fundMe(IERC20 token, address to, uint256 amount) public {
        vm.startPrank(users.whale);
        if (token == IERC20(address(weth))) {
            vm.deal(users.whale, amount);
            weth.deposit{value: amount}();
            weth.transfer(to, amount);
        } else {
            token.transfer(to, amount);
        }
        vm.stopPrank();
    }

    function _mintLiquidity(uint256 ethAmt, uint256 tokenAmt, address to) private {
        vm.deal(to, ethAmt);
        _fundMe(IERC20(goat), to, tokenAmt);
        vm.startPrank(to);
        weth.deposit{value: ethAmt}();
        weth.transfer(address(pair), ethAmt);
        goat.transfer(address(pair), tokenAmt);
        pair.mint(to);
        vm.stopPrank();
    }

    function _mintInitialLiquidity(GoatTypes.InitParams memory initParams, address to)
        private
        returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm)
    {
        (tokenAmtForPresale, tokenAmtForAmm) = GoatLibrary.getTokenAmountsForPresaleAndAmm(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );
        uint256 bootstrapTokenAmt = tokenAmtForPresale + tokenAmtForAmm;
        _fundMe(IERC20(address(goat)), to, bootstrapTokenAmt);
        vm.startPrank(to);
        address pairAddress = factory.createPair(address(goat), initParams);
        if (bootstrapTokenAmt != 0) {
            goat.transfer(pairAddress, bootstrapTokenAmt);
        }
        if (initParams.initialEth != 0) {
            vm.deal(to, initParams.initialEth);
            weth.deposit{value: initParams.initialEth}();
            weth.transfer(pairAddress, initParams.initialEth);
        }
        pair = GoatV1Pair(pairAddress);
        pair.mint(to);

        vm.stopPrank();
    }

    function testFactoryCreation() public {
        assertEq(factory.weth(), address(weth));
    }

    function testFactoryTreasury() public {
        assertEq(factory.treasury(), users.treasury);
    }

    function testPairCreation() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10, 10, 10, 10);
        address pairAddress = factory.createPair(address(goat), initParams);
        pair = GoatV1Pair(pairAddress);
        assertEq(pair.factory(), address(factory));
    }

    function testInitializeCallRevertByNonFactory() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10, 10, 10, 10);
        address pairAddress = factory.createPair(address(goat), initParams);
        pair = GoatV1Pair(pairAddress);

        vm.expectRevert(GoatErrors.GoatV1Forbidden.selector);
        pair.initialize(address(goat), address(weth), "weth-goat", initParams);
    }

    function testMintSuccessWithoutInitialEth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        uint256 initialLpBalance = pair.balanceOf(users.lp);
        assertEq(initialLpBalance, 100e18 - MINIMUM_LIQUIDITY);
        (uint256 reserveWeth, uint256 reserveToken) = pair.getReserves();

        assertEq(reserveWeth, initParams.virtualEth);
        assertEq(reserveToken, initParams.initialTokenMatch);

        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();

        // since we allow 25% withdrawls, fractional balance will be 1/4th of the total
        uint256 expectedFractionalBalance = initialLpBalance / 4;

        assertEq(initialLPInfo.liquidityProvider, users.lp);
        assertEq(initialLPInfo.fractionalBalance, expectedFractionalBalance);
        assertEq(initialLPInfo.lastWithdraw, 0);
        assertEq(initialLPInfo.withdrawalLeft, 4);
    }

    function testMintSuccessWithFullBootstrapEth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        (, uint256 tokenAmtForAmm) = _mintInitialLiquidity(initParams, users.lp);
        // since reserve eth will be 10e18 and reserveToken will be 250e18
        // sqrt of their product = 50e18
        uint256 expectedLp = 50e18 - MINIMUM_LIQUIDITY;
        uint256 initialLpBalance = pair.balanceOf(users.lp);
        assertEq(initialLpBalance, expectedLp);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();

        assertEq(reserveEth, initParams.bootstrapEth);
        assertEq(reserveToken, tokenAmtForAmm);

        uint256 vestingUntil = pair.vestingUntil();
        assertEq(vestingUntil, block.timestamp + _VESTING_PERIOD);
    }

    function testMintSuccessWithPartialBootstrapEth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // expected lp will be sqrt of initial token match and virtual eth
        // if weth sent is < bootstrap amount
        uint256 expectedLp = 100e18 - MINIMUM_LIQUIDITY;
        uint256 actualK = (uint256(initParams.virtualEth) * uint256(initParams.initialTokenMatch));

        uint256 initialLpBalance = pair.balanceOf(users.lp);
        assertEq(initialLpBalance, expectedLp);
        (uint256 virtualReserveEth, uint256 virtualReserveToken) = pair.getReserves();

        assertEq(virtualReserveEth, initParams.virtualEth + initParams.initialEth);
        uint256 expectedVirtualReserveToken = (actualK / (initParams.virtualEth + initParams.initialEth)) + 1;

        assertEq(virtualReserveToken, expectedVirtualReserveToken);

        uint256 vestingUntil = pair.vestingUntil();
        assertEq(vestingUntil, _MAX_UINT32);

        // check if initiallp info is updated correctly
        GoatTypes.InitialLPInfo memory lpInfo = pair.getInitialLPInfo();
        assertEq(lpInfo.initialWethAdded, initParams.initialEth);
    }

    function testMintRevertWithoutEnoughBootstrapTokenAmt() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;
        uint256 bootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );
        _fundMe(IERC20(address(goat)), users.lp, bootstrapTokenAmt);
        vm.startPrank(users.lp);
        address pairAddress = factory.createPair(address(goat), initParams);

        // send less token amount to the pair contract
        goat.transfer(pairAddress, bootstrapTokenAmt - 1);
        pair = GoatV1Pair(pairAddress);

        vm.expectRevert(GoatErrors.InsufficientTokenAmount.selector);
        pair.mint(users.lp);

        vm.stopPrank();
    }

    function testMintRevertWithExcessInitialWeth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        uint256 bootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        _fundMe(IERC20(address(goat)), users.lp, bootstrapTokenAmt);
        vm.deal(users.lp, 20e18);
        vm.startPrank(users.lp);
        address pairAddress = factory.createPair(address(goat), initParams);

        weth.deposit{value: 20e18}();
        // send less token amount to the pair contract
        goat.transfer(pairAddress, bootstrapTokenAmt);
        weth.transfer(pairAddress, 20e18);
        pair = GoatV1Pair(pairAddress);

        vm.expectRevert(GoatErrors.SupplyMoreThanBootstrapEth.selector);
        pair.mint(users.lp);

        vm.stopPrank();
    }

    function testMintRevertOnPresaleIfInitialLiquidityIsAlreadyThere() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        vm.startPrank(users.alice);
        vm.expectRevert(GoatErrors.PresalePeriod.selector);
        pair.mint(users.alice);
        vm.stopPrank();
    }

    function testTransferRevertOfInitialLiquidityProvider() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        vm.startPrank(users.lp);
        vm.expectRevert(GoatErrors.TransferFromInitialLpRestricted.selector);
        pair.transfer(users.bob, 1e18);
        vm.stopPrank();
    }

    function testPartialBurnSuccessForInitialLp() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // get initial lp info
        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();
        // burn 1/4th of the lp
        vm.startPrank(users.lp);

        uint256 totalSupplyBefore = pair.totalSupply();
        uint256 lpWethBalBefore = weth.balanceOf(users.lp);
        uint256 lpTokenBalanceBefore = goat.balanceOf(users.lp);

        uint256 warpTime = block.timestamp + 3 days;
        // increase block.timestamp so that initial lp can remove liquidity
        vm.warp(warpTime);
        pair.transfer(address(pair), initialLPInfo.fractionalBalance);
        pair.burn(users.lp);
        vm.stopPrank();

        uint256 totalSupplyAfter = pair.totalSupply();
        uint256 lpWethBalAfter = weth.balanceOf(users.lp);
        uint256 lpTokenBalanceAfter = goat.balanceOf(users.lp);

        GoatTypes.InitialLPInfo memory initialLPInfoAfterBurn = pair.getInitialLPInfo();

        assertEq(initialLPInfoAfterBurn.fractionalBalance, initialLPInfo.fractionalBalance);
        assertEq(initialLPInfoAfterBurn.lastWithdraw, block.timestamp);
        assertEq(initialLPInfoAfterBurn.withdrawalLeft, initialLPInfo.withdrawalLeft - 1);

        assertEq(totalSupplyBefore - totalSupplyAfter, initialLPInfo.fractionalBalance);

        // Using approx value because of initial liquidity mint for zero address
        assertApproxEqAbs(lpWethBalAfter - lpWethBalBefore, 2.5 ether, 0.0001 ether);
        assertApproxEqAbs(lpTokenBalanceAfter - lpTokenBalanceBefore, 62.5 ether, 0.0001 ether);
    }

    function testPartialBypassRevertFromInitialLp() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // burn 1/4th of the lp
        vm.startPrank(users.lp);

        uint256 warpTime = block.timestamp + 3 days;
        // increase block.timestamp so that initial lp can remove liquidity
        vm.warp(warpTime);
        uint256 totalBalance = pair.balanceOf(users.lp);
        vm.expectRevert(GoatErrors.BurnLimitExceeded.selector);
        // So even if burn is called for alice and actual tokens was
        // transferred by initial lp this call should fail because
        // from of last token recieved by the contract is saved and checked
        // when burn is called.
        pair.transfer(address(pair), totalBalance);
        vm.stopPrank();
    }

    function testInitialRevertOnTransferingMoreThanFractionalAmountToPair() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // try transferring more than 1/4th initial lp balance to the
        // pair contract
        vm.startPrank(users.lp);

        uint256 balance = pair.balanceOf(users.lp);
        vm.expectRevert(GoatErrors.BurnLimitExceeded.selector);
        pair.transfer(address(pair), balance);

        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();

        // lets try to revert by just adding 1 wei to fractional balance
        vm.expectRevert(GoatErrors.BurnLimitExceeded.selector);
        pair.transfer(address(pair), initialLPInfo.fractionalBalance + 1);

        vm.stopPrank();
    }

    function testPartialBurnRevertOnCooldownActive() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // get initial lp info
        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();

        vm.startPrank(users.lp);
        uint256 warpTime = block.timestamp + 3 days;
        // increase block.timestamp so that initial lp can remove liquidity
        vm.warp(warpTime);
        pair.transfer(address(pair), initialLPInfo.fractionalBalance);
        pair.burn(users.lp);

        // Withdraw cooldown active check
        vm.expectRevert(GoatErrors.WithdrawalCooldownActive.selector);
        pair.transfer(address(pair), initialLPInfo.fractionalBalance);
        vm.stopPrank();
    }

    function testPartialBurnRevertOnPresale() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // get initial lp info
        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();

        vm.startPrank(users.lp);
        uint256 warpTime = block.timestamp + 3 days;
        // increase block.timestamp so that initial lp can remove liquidity
        vm.warp(warpTime);
        pair.transfer(address(pair), initialLPInfo.fractionalBalance);

        // Should not allow liquidity burn on preslae period!
        vm.expectRevert(GoatErrors.PresalePeriod.selector);
        pair.burn(users.lp);

        vm.stopPrank();
    }

    function testPartialBurnRevertOnLimitExceeded() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // get initial lp info
        GoatTypes.InitialLPInfo memory initialLPInfo = pair.getInitialLPInfo();

        vm.startPrank(users.lp);
        uint256 warpTime = block.timestamp + 3 days;
        // increase block.timestamp so that initial lp can remove liquidity
        vm.warp(warpTime);
        // try to transfer should not be allowed and burn limit exceeded should be thrown
        uint256 withdrawLpAmount = initialLPInfo.fractionalBalance + 1e18;
        vm.expectRevert(GoatErrors.BurnLimitExceeded.selector);
        pair.transfer(address(pair), withdrawLpAmount);
        vm.stopPrank();
    }

    function testAddLpAfterPoolTurnsToAnAmm() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        _mintLiquidity(5e18, 125e18, users.bob);

        uint256 bobLpBalance = pair.balanceOf(users.bob);
        uint256 expectedLpMinted = 25e18;

        assertEq(bobLpBalance, expectedLpMinted);
    }

    function testBurnAfterLockPeriodForOtherLps() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        uint256 wethAmt = 5e18;
        uint256 tokenAmt = 125e18;

        _mintLiquidity(wethAmt, tokenAmt, users.bob);

        uint256 bobLpBalance = pair.balanceOf(users.bob);

        uint256 wethBalBefore = weth.balanceOf(users.bob);
        uint256 tokenBalBefore = goat.balanceOf(users.bob);

        uint256 warpTime = block.timestamp + 3 days;
        vm.warp(warpTime);

        vm.startPrank(users.bob);
        pair.transfer(address(pair), bobLpBalance);
        pair.burn(users.bob);

        uint256 wethBalAfter = weth.balanceOf(users.bob);
        uint256 tokenBalAfter = goat.balanceOf(users.bob);

        assertEq(wethBalAfter - wethBalBefore, wethAmt);
        assertEq(tokenBalAfter - tokenBalBefore, tokenAmt);
    }

    /* ------------------------------- SWAP TESTS ------------------------------ */
    function testSwapWhenPoolIsInPresale() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        vm.startPrank(users.alice);
        uint256 wethAmount = 5e18;
        // 5 eth should give you tokens almost ~333 in this case
        uint256 amountTokenOut = 333e18;
        uint256 amountWethOut = 0;
        uint256 wethWithFees = wethAmount * 10000 / 9901;
        vm.deal(users.alice, wethWithFees);
        weth.deposit{value: wethWithFees}();

        weth.transfer(address(pair), wethWithFees);
        pair.swap(amountTokenOut, amountWethOut, users.alice);
        vm.stopPrank();
    }

    function _swapWethForTokens(uint256 wethAmount, uint256 amountTokenOut, address to, uint8 shouldRevert)
        private
        returns (uint256)
    {
        vm.startPrank(to);
        // update weth amount to include fees
        uint256 wethWithFees = wethAmount * 10000 / 9901;
        vm.deal(to, wethWithFees);
        weth.deposit{value: wethWithFees}();
        weth.transfer(address(pair), wethWithFees);
        if (shouldRevert == 1) {
            vm.expectRevert(GoatErrors.MevDetected1.selector);
        } else if (shouldRevert == 2) {
            vm.expectRevert(GoatErrors.MevDetected2.selector);
        }
        pair.swap(amountTokenOut, 0, to);
        vm.stopPrank();
        return wethWithFees;
    }

    function _swapTokensForWeth(uint256 tokenAmount, uint256 amountWethOut, address to, uint256 shouldRevert) private {
        vm.startPrank(to);
        goat.transfer(address(pair), tokenAmount);
        if (shouldRevert == 1) {
            vm.expectRevert(GoatErrors.MevDetected1.selector);
        } else if (shouldRevert == 2) {
            vm.expectRevert(GoatErrors.MevDetected2.selector);
        }
        pair.swap(0, amountWethOut, to);
        vm.stopPrank();
    }

    function testSwapRevertMevType1() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        // using random amounts for in and out just for
        // identifying if mev is working
        // frontrun txn BUY
        _swapWethForTokens(1e18, 20e18, users.alice, 0);
        // user txn BUY
        _swapWethForTokens(1e18, 20e18, users.bob, 0);
        // sandwich txn SELL
        _swapTokensForWeth(2e18, 2e17, users.alice, 1);
    }

    function testSwapRevertMevType2() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        // normal buy
        _swapWethForTokens(1e18, 20e18, users.alice, 0);
        // normal buy
        _swapWethForTokens(1e18, 20e18, users.bob, 0);
        vm.warp(block.timestamp + 12);
        // frontRun txn SELL
        _swapTokensForWeth(10e18, 1e17, users.alice, 0);
        // user txn SELL
        _swapTokensForWeth(11e18, 1e17, users.bob, 0);
        // frontrunner buy
        _swapWethForTokens(1e18, 20e18, users.alice, 2);
    }

    function testSwapToChangePoolFromPresaleToAnAmm() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        uint256 lpBalance = pair.balanceOf(users.lp);
        uint256 expectedFractionalBalance = lpBalance / 4;
        GoatTypes.InitialLPInfo memory initialLPInfoBefore = pair.getInitialLPInfo();

        assertEq(initialLPInfoBefore.withdrawalLeft, 4);
        assertEq(expectedFractionalBalance, initialLPInfoBefore.fractionalBalance);

        vm.startPrank(users.alice);
        vm.deal(users.alice, 20e18);
        weth.deposit{value: 20e18}();
        uint256 amountTokenOut = 500e18;
        uint256 amountWethOut = 0;
        uint256 amountWeth = 10e18;
        uint256 wethAmtWithFees = (amountWeth * 10000) / 9901;
        weth.transfer(address(pair), wethAmtWithFees);
        pair.swap(amountTokenOut, amountWethOut, users.alice);
        vm.stopPrank();
        GoatTypes.InitialLPInfo memory initialLPInfoAfter = pair.getInitialLPInfo();
        lpBalance = pair.balanceOf(users.lp);
        expectedFractionalBalance = lpBalance / 4;
        assertEq(initialLPInfoAfter.withdrawalLeft, 4);
        assertEq(expectedFractionalBalance, initialLPInfoAfter.fractionalBalance);
    }

    struct LocalVars_ForSwap {
        uint256 wethForAmm;
        uint256 tokenAmountAtAmm;
        uint256 amountTokenOutFromPresale;
        uint256 amountTokenOutFromAmm;
        uint256 actualWeth;
        uint256 actualWethWithFees;
        uint256 actualK;
        uint256 desiredK;
        uint256 lpBalance;
        uint256 expectedLpBalance;
    }

    function testSwapToRecieveTokensFromBothPresaleAndAmm() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;
        LocalVars_ForSwap memory vars;

        _mintInitialLiquidity(initParams, users.lp);

        vm.startPrank(users.alice);
        vm.deal(users.alice, 20e18);
        weth.deposit{value: 20e18}();

        vars.wethForAmm = 2e18;
        vars.tokenAmountAtAmm = 250e18;
        vars.amountTokenOutFromPresale = 500e18;
        vars.amountTokenOutFromAmm =
            (vars.wethForAmm * vars.tokenAmountAtAmm) / (initParams.bootstrapEth + vars.wethForAmm);

        (uint256 virtualEthReserve, uint256 virtualTokenReserve) = pair.getReserves();
        vars.actualK = virtualEthReserve * virtualTokenReserve;
        vars.desiredK = uint256(initParams.virtualEth) * (initParams.initialTokenMatch);

        assertGe(vars.actualK, vars.desiredK);
        uint256 expectedLpBalance = Math.sqrt(uint256(initParams.virtualEth) * initParams.initialTokenMatch);
        expectedLpBalance -= MINIMUM_LIQUIDITY;
        uint256 lpBalance = pair.balanceOf(users.lp);

        assertEq(lpBalance, expectedLpBalance);

        uint256 amountTokenOut = vars.amountTokenOutFromAmm + vars.amountTokenOutFromPresale;
        uint256 amountWethOut = 0;
        uint256 actualWeth = 12e18;
        uint256 actualWethWithFees = (actualWeth * 10000) / 9901;

        weth.transfer(address(pair), actualWethWithFees);
        pair.swap(amountTokenOut, amountWethOut, users.alice);
        vm.stopPrank();

        // Since the pool has turned to an Amm now, the reserves are real.
        (uint256 realEthReserve, uint256 realTokenReserve) = pair.getReserves();

        vars.desiredK = vars.tokenAmountAtAmm * initParams.bootstrapEth;
        vars.actualK = realEthReserve * realTokenReserve;

        assertGe(vars.actualK, vars.desiredK);
        // at this point as pool has converted to an Amm the lp balance should be
        // equal to the sqrt of the product of the reserves
        expectedLpBalance = Math.sqrt(initParams.bootstrapEth * vars.tokenAmountAtAmm) - MINIMUM_LIQUIDITY;
        lpBalance = pair.balanceOf(users.lp);

        assertEq(lpBalance, expectedLpBalance);
    }

    function testSwapRevertSellTokenNotBoughtAtVesting() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        _fundMe(goat, users.alice, 1000e18);
        vm.startPrank(users.alice);
        goat.transfer(address(pair), 100e18);
        // As there is no eth in the pair contract this should revert
        vm.expectRevert(GoatErrors.InsufficientAmountOut.selector);
        pair.swap(0, 1e18, users.alice);
        vm.stopPrank();

        // Now let's add some eth to the pair contract
        vm.startPrank(users.alice);
        vm.deal(users.alice, 10e18);
        weth.deposit{value: 10e18}();
        weth.transfer(address(pair), 5e18);
        pair.swap(330e18, 0, users.alice);
        vm.stopPrank();

        _fundMe(goat, users.bob, 100e18);
        vm.startPrank(users.bob);
        goat.transfer(address(pair), 100e18);
        vm.expectRevert();
        pair.swap(0, 1e18, users.bob);
        vm.stopPrank();
    }

    /* ------------------------------- WITHDRAW FEES------------------------------ */

    function testWithdrawFeesSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;
        uint256 wethAmount = 10e18;
        _mintInitialLiquidity(initParams, users.lp);

        wethAmount = _swapWethForTokens(wethAmount, 100e18, users.alice, 0);
        uint256 fees = (wethAmount * 99) / 10000;
        uint256 totalLpFees = (fees * 40) / 100;
        uint256 totalSupply = pair.totalSupply();
        uint256 feesPerTokenStored = (totalLpFees * 1e18) / totalSupply;
        uint256 lpBalance = pair.balanceOf(users.lp);
        uint256 lpFees = (feesPerTokenStored * lpBalance) / 1e18;

        feesPerTokenStored = pair.feesPerTokenStored();

        uint256 lpWethBalBefore = weth.balanceOf(users.lp);
        vm.startPrank(users.lp);
        pair.withdrawFees(users.lp);
        vm.stopPrank();
        uint256 lpWethBalAfter = weth.balanceOf(users.lp);

        assertEq(lpWethBalAfter - lpWethBalBefore, lpFees);
    }

    function testFeesUpdateOnLpBalanceTransfer() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;
        _mintInitialLiquidity(initParams, users.lp);

        _mintLiquidity(10e18, 250e18, users.bob);
        _swapWethForTokens(10e18, 166e18, users.alice, 0);
        // increase timestamp
        uint256 warpTime = block.timestamp + 2 days;
        vm.warp(warpTime);
        vm.startPrank(users.bob);
        pair.transfer(users.lp1, 50e18);
        vm.stopPrank();

        uint256 feesPerTokenStored = pair.feesPerTokenStored();
        uint256 feesPerTokenPaidLp1 = pair.feesPerTokenPaid(users.lp1);

        // Fees per token paid for both sender and reciever should be updated
        assertEq(feesPerTokenStored, feesPerTokenPaidLp1);
        uint256 feesPerTokenPaidBob = pair.feesPerTokenPaid(users.bob);
        uint256 feesPerTokenPaidLp = pair.feesPerTokenPaid(users.lp);

        assertEq(feesPerTokenStored, feesPerTokenPaidBob);
        // Lp fees per token paid should not be updated here as he has not interacted yet
        assertEq(feesPerTokenPaidLp, 0);

        uint256 earnedBob = pair.earned(users.bob);
        uint256 earnedLp = pair.earned(users.lp);
        uint256 earnedAlice = pair.earned(users.alice);
        assertEq(earnedAlice, 0);
        // initial lp will get 1000 wei token less because of initial mint
        // As both lp's have almost same amount of lp token the fees should be
        // distributed equally deducting initial mint minimum liqudity fees which
        // comes out as 1 wei
        assertEq(earnedLp, earnedBob - 1);

        vm.startPrank(users.bob);
        pair.withdrawFees(users.bob);
        vm.stopPrank();

        vm.startPrank(users.lp);
        pair.withdrawFees(users.lp);
        vm.stopPrank();

        vm.startPrank(users.lp);
        pair.withdrawFees(users.lp1);
        vm.stopPrank();

        feesPerTokenPaidLp = pair.feesPerTokenPaid(users.lp);

        // Lp fees per token paid should be updated as he has withdrawn fees
        assertEq(feesPerTokenPaidLp, feesPerTokenStored);
    }

    /* ------------------------------- WITHDRAW EXCESS TOKEN TESTS ------------------------------ */
    function testWithdrawExcessTokenSuccess() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        uint256 wethAmount = 5e18;
        uint256 expectedTokenOut = (wethAmount * initParams.initialTokenMatch) / (initParams.virtualEth + wethAmount);
        uint256 wethAmountWithFees = (wethAmount * 10000) / 9901;
        uint256 lpFees = ((wethAmountWithFees - wethAmount) * 40 / 100);

        vm.startPrank(users.alice);
        vm.deal(users.alice, wethAmountWithFees);
        weth.deposit{value: wethAmountWithFees}();
        weth.transfer(address(pair), wethAmountWithFees);
        pair.swap(expectedTokenOut, 0, users.alice);
        vm.stopPrank();

        uint256 warpTime = block.timestamp + 32 days;
        vm.warp(warpTime);
        vm.startPrank(users.lp);
        pair.withdrawExcessToken();
        vm.stopPrank();

        // presale lp fees goes to reserves
        uint256 actualWethReserveInPool = wethAmount + lpFees;

        // at this point the pool has turned to an Amm
        // I need to check if the tokens in the pool match
        // up with what's needed in the pool

        (, uint256 tokenAmountForAmm) = GoatLibrary.getTokenAmountsForPresaleAndAmm(
            initParams.virtualEth, actualWethReserveInPool, 0, initParams.initialTokenMatch
        );

        (uint256 realEthReserve, uint256 realTokenReserve) = pair.getReserves();
        assertEq(actualWethReserveInPool, realEthReserve);

        assertEq(tokenAmountForAmm, realTokenReserve);
    }

    function testWithdrawExcessTokenPairRemovalIfReservesAreEmpty() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);
        address pairFromFactory = factory.getPool(address(goat));

        assertEq(pairFromFactory, address(pair));

        uint256 warpTime = block.timestamp + 32 days;
        vm.warp(warpTime);
        vm.startPrank(users.lp);
        pair.withdrawExcessToken();
        vm.stopPrank();

        pairFromFactory = factory.getPool(address(goat));
        assertEq(pairFromFactory, address(0));
    }

    function testRevertWithdrawExcessTokenDeadlineActive() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        vm.startPrank(users.lp);
        vm.expectRevert(GoatErrors.PresaleDeadlineActive.selector);
        pair.withdrawExcessToken();
        vm.stopPrank();
    }

    function testRevertWithdrawExcessTokenIfPoolIsAlreadyAnAmm() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // bypass genesis + 30 days
        uint256 warpTime = block.timestamp + 32 days;
        vm.warp(warpTime);

        vm.startPrank(users.lp);
        vm.expectRevert(GoatErrors.ActionNotAllowed.selector);
        pair.withdrawExcessToken();
        vm.stopPrank();
    }

    function testRevertWithdrawExcessTokenIfCallerIsNotInitialLp() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // bypass genesis + 30 days
        uint256 warpTime = block.timestamp + 32 days;
        vm.warp(warpTime);

        vm.startPrank(users.lp1);
        vm.expectRevert(GoatErrors.Unauthorized.selector);
        pair.withdrawExcessToken();
        vm.stopPrank();
    }

    /* ------------------------------- TAKEOVER TESTS ------------------------------ */
    function testRevertPoolTakeoverIfAlreadyAnAmm() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        initParams.initialEth = 0;
        vm.startPrank(users.lp1);
        vm.expectRevert(GoatErrors.ActionNotAllowed.selector);
        pair.takeOverPool(0, initParams);
        vm.stopPrank();
    }

    function testRevertPoolTakeOverWithNotEnoughWeth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        initParams.initialEth -= 1e18;
        vm.startPrank(users.lp1);
        // less than initial eth
        vm.expectRevert(GoatErrors.IncorrectWethAmount.selector);
        pair.takeOverPool(0, initParams);

        // more than initial eth
        initParams.initialEth += 2e18;
        vm.expectRevert(GoatErrors.IncorrectWethAmount.selector);
        pair.takeOverPool(0, initParams);
        vm.stopPrank();
    }

    function testRevertPoolTakeOverWithNotEnoughToken() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        vm.startPrank(users.lp1);
        vm.expectRevert(GoatErrors.InsufficientTakeoverTokenAmount.selector);
        pair.takeOverPool(749e18, initParams);
        vm.stopPrank();
    }

    function testRevertPoolTakeOverWithNotExactTokenNeededForNewInitParams() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 100e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 100e18;
        initParams.bootstrapEth = 10e18;

        _mintInitialLiquidity(initParams, users.lp);

        // change init params for takeover
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        uint256 takeOverBootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        _fundMe(goat, users.lp1, takeOverBootstrapTokenAmt);
        vm.startPrank(users.lp1);
        goat.approve(address(pair), takeOverBootstrapTokenAmt);
        vm.expectRevert(GoatErrors.IncorrectTokenAmount.selector);
        // sending token less than desired should revert
        pair.takeOverPool(takeOverBootstrapTokenAmt - 1, initParams);

        vm.expectRevert(GoatErrors.IncorrectTokenAmount.selector);
        // sending token more than desired should revert
        pair.takeOverPool(takeOverBootstrapTokenAmt + 1, initParams);
        vm.stopPrank();
    }

    function testPoolTakeOverSuccessWithoutWeth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 100e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 100e18;
        initParams.bootstrapEth = 10e18;

        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) = _mintInitialLiquidity(initParams, users.lp);

        uint256 lpPoolBalance = pair.balanceOf(users.lp);
        assertEq(lpPoolBalance, 100e18 - MINIMUM_LIQUIDITY);

        // change init params for takeover
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        uint256 takeOverBootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        uint256 lpTokenBalance = goat.balanceOf(users.lp);
        assertEq(lpTokenBalance, 0);

        _fundMe(goat, users.lp1, takeOverBootstrapTokenAmt);
        vm.startPrank(users.lp1);
        goat.approve(address(pair), takeOverBootstrapTokenAmt);
        pair.takeOverPool(takeOverBootstrapTokenAmt, initParams);
        vm.stopPrank();

        // lp goat balance should sum of presale and amm bal
        lpTokenBalance = goat.balanceOf(users.lp);
        assertEq(lpTokenBalance, (tokenAmtForPresale + tokenAmtForAmm));

        uint256 lp1PoolBalance = pair.balanceOf(users.lp1);
        assertEq(lp1PoolBalance, 100e18 - MINIMUM_LIQUIDITY);

        lpPoolBalance = pair.balanceOf(users.lp);
        assertEq(lpPoolBalance, 0);

        GoatTypes.InitialLPInfo memory lpInfo = pair.getInitialLPInfo();
        assertEq(lpInfo.liquidityProvider, users.lp1);
    }

    function testPoolTakeOverSuccessWithWeth() public {
        GoatTypes.InitParams memory initParams;
        initParams.virtualEth = 100e18;
        initParams.initialEth = 5e18;
        initParams.initialTokenMatch = 100e18;
        initParams.bootstrapEth = 10e18;

        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) = _mintInitialLiquidity(initParams, users.lp);

        uint256 lpPoolBalance = pair.balanceOf(users.lp);
        assertEq(lpPoolBalance, 100e18 - MINIMUM_LIQUIDITY);

        // change init params for takeover
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;
        uint256 takeOverBootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        uint256 lpTokenBalance = goat.balanceOf(users.lp);
        assertEq(lpTokenBalance, 0);

        uint256 lpWethBalance = weth.balanceOf(users.lp);

        _fundMe(goat, users.lp1, takeOverBootstrapTokenAmt);
        _fundMe(weth, users.lp1, initParams.initialEth);
        vm.startPrank(users.lp1);
        goat.approve(address(pair), takeOverBootstrapTokenAmt);
        weth.approve(address(pair), initParams.initialEth);
        pair.takeOverPool(takeOverBootstrapTokenAmt, initParams);
        vm.stopPrank();

        // lp goat balance should sum of presale and amm bal
        lpTokenBalance = goat.balanceOf(users.lp);
        assertEq(lpTokenBalance, (tokenAmtForPresale + tokenAmtForAmm));

        lpWethBalance = weth.balanceOf(users.lp);
        assertEq(lpWethBalance, initParams.initialEth);

        uint256 lp1PoolBalance = pair.balanceOf(users.lp1);
        assertEq(lp1PoolBalance, 100e18 - MINIMUM_LIQUIDITY);

        lpPoolBalance = pair.balanceOf(users.lp);
        assertEq(lpPoolBalance, 0);

        GoatTypes.InitialLPInfo memory lpInfo = pair.getInitialLPInfo();
        assertEq(lpInfo.liquidityProvider, users.lp1);
    }
}
