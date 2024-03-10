// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {GoatV1Pair} from "../../contracts/exchange/GoatV1Pair.sol";
import {GoatV1Factory} from "../../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../../contracts/periphery/GoatRouterV1.sol";
import {GoatV1ERC20} from "../../contracts/exchange/GoatV1ERC20.sol";
import {MockWETH} from "../../contracts/mock/MockWETH.sol";
import {MockERC20} from "../../contracts/mock/MockERC20.sol";
import {GoatTypes} from "../../contracts/library/GoatTypes.sol";

abstract contract BaseTest is Test {
    GoatV1Pair public pair;
    GoatV1Factory public factory;
    GoatV1Router public router;
    GoatV1ERC20 public goatToken;
    MockWETH public weth;
    MockERC20 public token;

    //Users
    address public lp_1 = makeAddr("lp_1");
    address public swapper = makeAddr("swapper");

    struct AddLiquidityParams {
        address token;
        uint256 tokenDesired;
        uint256 wethDesired;
        uint256 tokenMin;
        uint256 wethMin;
        address to;
        uint256 deadline;
        GoatTypes.InitParams initParams;
    }

    AddLiquidityParams public addLiqParams;

    function setUp() public {
        vm.warp(300 days);
        weth = new MockWETH();
        token = new MockERC20();
        factory = new GoatV1Factory(address(weth));
        router = new GoatV1Router(address(factory), address(weth));

        // Mint tokens
    }

    function addLiquidityParams(bool initial, bool sendInitWeth) public returns (AddLiquidityParams memory) {
        weth.deposit{value: 100e18}();
        if (initial) {
            /* ------------------------------- SET PARAMS ------------------------------- */
            addLiqParams.token = address(token);
            addLiqParams.tokenDesired = 0;
            addLiqParams.wethDesired = 0;
            addLiqParams.tokenMin = 0;
            addLiqParams.wethMin = 0;
            addLiqParams.to = address(this);
            addLiqParams.deadline = block.timestamp + 1000;

            addLiqParams.initParams = GoatTypes.InitParams(10e18, 10e18, sendInitWeth ? 5e18 : 0, 1000e18);
        } else {
            addLiqParams.token = address(token);
            addLiqParams.tokenDesired = 100e18;
            addLiqParams.wethDesired = 1e18;
            addLiqParams.tokenMin = 0;
            addLiqParams.wethMin = 0;
            addLiqParams.to = address(this);
            addLiqParams.deadline = block.timestamp + 1000;

            addLiqParams.initParams = GoatTypes.InitParams(0, 0, 0, 0);
        }
        return addLiqParams;
    }

    function _addLiquidityAndConvertToAmm()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity, uint256 actualTokenAmountToSend)
    {
        addLiquidityParams(true, true);
        addLiqParams.initParams.initialEth = 10e18; // set all weth
        actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );
        token.approve(address(router), actualTokenAmountToSend);
        weth.approve(address(router), addLiqParams.initParams.initialEth);
        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidity(
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

    function _addLiquidityEthAndConvertToAmm()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity, uint256 actualTokenAmountToSend)
    {
        addLiquidityParams(true, true);
        addLiqParams.initParams.initialEth = 10e18; // set all weth
        actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);

        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidityETH{value: 10e18}(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function _addLiquidityWithSomeWeth()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity)
    {
        addLiquidityParams(true, true);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );
        token.approve(address(router), actualTokenAmountToSend);
        weth.approve(address(router), addLiqParams.initParams.initialEth);
        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidity(
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

    function _addLiquidityWithSomeEth()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity)
    {
        addLiquidityParams(true, true);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);

        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidityETH{value: 5e18}(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }

    function _addLiquidityWithoutWeth()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity)
    {
        addLiquidityParams(true, false);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );
        token.approve(address(router), actualTokenAmountToSend);
        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidity(
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

    function _addLiquidityWithoutEth()
        internal
        returns (uint256 tokenAmtUsed, uint256 wethAmtUsed, uint256 liquidity)
    {
        addLiquidityParams(true, false);
        uint256 actualTokenAmountToSend = router.getActualBootstrapTokenAmount(
            addLiqParams.initParams.virtualEth,
            addLiqParams.initParams.bootstrapEth,
            addLiqParams.initParams.initialEth,
            addLiqParams.initParams.initialTokenMatch
        );

        token.approve(address(router), actualTokenAmountToSend);

        (tokenAmtUsed, wethAmtUsed, liquidity) = router.addLiquidityETH{value: addLiqParams.initParams.initialEth}(
            addLiqParams.token,
            addLiqParams.tokenDesired,
            addLiqParams.tokenMin,
            addLiqParams.wethMin,
            addLiqParams.to,
            addLiqParams.deadline,
            addLiqParams.initParams
        );
    }
}
