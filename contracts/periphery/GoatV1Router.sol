// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// library imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// local imports
import {GoatTypes} from "../library/GoatTypes.sol";
import {GoatV1Factory} from "../exchange/GoatV1Factory.sol";
import {GoatV1Pair} from "../exchange/GoatV1Pair.sol";
import {GoatErrors} from "../library/GoatErrors.sol";
import {GoatLibrary} from "../library/GoatLibrary.sol";
import {IWETH} from "../interfaces/IWETH.sol";

/**
 * @title Goat V1 Router
 * @notice Router for stateless execution of swaps and liquidity provision
 * @dev This contract is used for adding/removing liquidity, swapping tokens and withdrawing fees
 * @dev This contract is stateless and does not store any data
 * @author Goat Trading -- Chiranjibi Poudyal, Robert M.C. Forster
 */
contract GoatV1Router {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WETH;
    uint32 private constant MAX_UINT32 = type(uint32).max;
    uint8 private constant ZERO = 0;

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert GoatErrors.Expired();
        }
        _;
    }

    constructor(address factory_, address weth) {
        factory = factory_;
        WETH = weth;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****

    function addLiquidity(
        address token,
        uint256 tokenDesired,
        uint256 wethDesired,
        uint256 tokenMin,
        uint256 wethMin,
        address to,
        uint256 deadline,
        GoatTypes.InitParams memory initParams
    ) external ensure(deadline) returns (uint256, uint256, uint256) {
        GoatTypes.LocalVariables_AddLiquidity memory vars = _ensurePoolAndPrepareLiqudityParameters(
            token, tokenDesired, wethDesired, tokenMin, wethMin, initParams, false
        );

        IERC20(vars.token).safeTransferFrom(msg.sender, vars.pair, vars.actualTokenAmount);
        if (vars.wethAmount != 0) {
            IERC20(WETH).safeTransferFrom(msg.sender, vars.pair, vars.wethAmount);
        }
        vars.liquidity = GoatV1Pair(vars.pair).mint(to);
        if (vars.isNewPair) {
            vars.wethAmount =
                initParams.bootstrapEth == initParams.initialEth ? initParams.initialEth : initParams.virtualEth;
        }
        return (vars.tokenAmount, vars.wethAmount, vars.liquidity);
    }

    function addLiquidityETH(
        address token,
        uint256 tokenDesired,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline,
        GoatTypes.InitParams memory initParams
    ) external payable ensure(deadline) returns (uint256, uint256, uint256) {
        GoatTypes.LocalVariables_AddLiquidity memory vars =
            _ensurePoolAndPrepareLiqudityParameters(token, tokenDesired, msg.value, tokenMin, ethMin, initParams, true);
        IERC20(token).safeTransferFrom(msg.sender, vars.pair, vars.actualTokenAmount);
        if (vars.wethAmount != 0) {
            IWETH(WETH).deposit{value: vars.wethAmount}();
            IERC20(WETH).safeTransfer(vars.pair, vars.wethAmount);
        }

        vars.liquidity = GoatV1Pair(vars.pair).mint(to);
        // refund dust eth, if any
        if (msg.value > vars.wethAmount) {
            (bool success,) = payable(msg.sender).call{value: msg.value - vars.wethAmount}("");
            if (!success) {
                revert GoatErrors.EthTransferFailed();
            }
        }

        if (vars.isNewPair) {
            vars.wethAmount =
                initParams.bootstrapEth == initParams.initialEth ? initParams.initialEth : initParams.virtualEth;
        }
        return (vars.tokenAmount, vars.wethAmount, vars.liquidity);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 wethMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountWeth, uint256 amountToken) {
        address pair = GoatV1Factory(factory).getPool(token);

        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (amountWeth, amountToken) = GoatV1Pair(pair).burn(to);
        if (amountWeth < wethMin) {
            revert GoatErrors.InsufficientWethAmount();
        }
        if (amountToken < tokenMin) {
            revert GoatErrors.InsufficientTokenAmount();
        }
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountWeth, uint256 amountToken) {
        (amountWeth, amountToken) = removeLiquidity(token, liquidity, tokenMin, ethMin, address(this), deadline);
        IERC20(token).safeTransfer(to, amountToken);
        IWETH(WETH).withdraw(amountWeth);
        (bool success,) = to.call{value: amountWeth}("");
        if (!success) {
            revert GoatErrors.EthTransferFailed();
        }
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountWeth) {
        (amountWeth,) = removeLiquidity(token, liquidity, tokenMin, ethMin, address(this), deadline);
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountWeth);
        (bool success,) = to.call{value: amountWeth}("");
        if (!success) {
            revert GoatErrors.EthTransferFailed();
        }
    }

    /* ----------------------------- SWAP FUNCTIONS FOR FEE ON TRANSFER TOKENS ----------------------------- */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        if (path.length != 2) {
            revert GoatErrors.InvalidPath();
        }
        if (path[0] == WETH) {
            swapExactWethForTokensSupportingFeeOnTransferTokens(amountIn, amountOutMin, path[1], to, deadline);
        } else if (path[1] == WETH) {
            swapExactTokensForWethSupportingFeeOnTransferTokens(amountIn, amountOutMin, path[0], to, deadline);
        } else {
            revert GoatErrors.InvalidPath();
        }
    }

    function swapExactWethForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) public ensure(deadline) {
        IERC20(WETH).safeTransferFrom(msg.sender, address(GoatV1Factory(factory).getPool(token)), amountIn);
        _swapSupportingFeeOnTransferTokens(amountIn, amountOutMin, token, to, true);
    }

    function swapETHForExactTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        if (path.length != 2 || path[0] != WETH) {
            revert GoatErrors.InvalidPath();
        }

        IWETH(WETH).deposit{value: msg.value}();
        IERC20(WETH).safeTransfer(address(GoatV1Factory(factory).getPool(path[1])), msg.value);
        _swapSupportingFeeOnTransferTokens(msg.value, amountOutMin, path[1], to, true);
    }

    function swapExactTokensForWethSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) public ensure(deadline) {
        address pair = address(GoatV1Factory(factory).getPool(token));
        uint256 poolBalBefore = IERC20(token).balanceOf(pair);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountIn);
        uint256 poolBalAfter = IERC20(token).balanceOf(pair);
        amountIn = poolBalAfter - poolBalBefore;
        _swapSupportingFeeOnTransferTokens(amountIn, amountOutMin, token, to, false);
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        address pair = address(GoatV1Factory(factory).getPool(token));
        uint256 poolBalBefore = IERC20(token).balanceOf(pair);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountIn);
        uint256 poolBalAfter = IERC20(token).balanceOf(address(pair));
        amountIn = poolBalAfter - poolBalBefore;
        _swapSupportingFeeOnTransferTokens(amountIn, amountOutMin, token, address(this), false);
        uint256 amountOut = IWETH(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(amountOut);
        payable(to).transfer(amountOut);
    }

    /* ----------------------------- SWAP FUNCTIONS  ----------------------------- */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        if (amounts[1] < amountOutMin) {
            revert GoatErrors.InsufficientOutputAmount();
        }

        if (path[0] == WETH) {
            swapExactWethForTokens(amountIn, amounts[1], path[1], to, deadline);
        } else {
            swapExactTokensForWeth(amountIn, amounts[1], path[0], to, deadline);
        }
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert GoatErrors.ExcessiveInputAmount();
        }

        if (path[0] == WETH) {
            amounts[1] = swapExactWethForTokens(amounts[0], amountOut, path[1], to, deadline);
        } else {
            amounts[1] = swapExactTokensForWeth(amounts[0], amountOut, path[0], to, deadline);
        }
    }

    function swapExactWethForTokens(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        public
        ensure(deadline)
        returns (uint256 amountTokenOut)
    {
        GoatV1Pair pair;
        (amountTokenOut, pair) = _getAmountTokenOut(amountIn, amountOutMin, token);
        IERC20(WETH).safeTransferFrom(msg.sender, address(pair), amountIn);
        pair.swap(ZERO, amountTokenOut, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256 amountTokenOut)
    {
        if (path.length != 2 || path[0] != WETH) {
            revert GoatErrors.InvalidPath();
        }

        GoatV1Pair pair;
        (amountTokenOut, pair) = _getAmountTokenOut(msg.value, amountOutMin, path[1]);
        IWETH(WETH).deposit{value: msg.value}();
        IERC20(WETH).safeTransfer(address(pair), msg.value);
        pair.swap(0, amountTokenOut, to);
    }

    function swapExactTokensForWeth(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        public
        ensure(deadline)
        returns (uint256 amountWethOut)
    {
        if (amountIn == 0) {
            revert GoatErrors.InsufficientInputAmount();
        }
        GoatV1Pair pair;
        (amountWethOut, pair) = _getAmountWethOut(amountIn, amountOutMin, token);
        IERC20(token).safeTransferFrom(msg.sender, address(pair), amountIn);
        pair.swap(amountWethOut, 0, to);
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external
        ensure(deadline)
        returns (uint256 amountWethOut)
    {
        if (amountIn == 0) {
            revert GoatErrors.InsufficientInputAmount();
        }
        GoatV1Pair pair;
        (amountWethOut, pair) = _getAmountWethOut(amountIn, amountOutMin, token);
        IERC20(token).safeTransferFrom(msg.sender, address(pair), amountIn);
        pair.swap(amountWethOut, 0, address(this));

        uint256 amountOut = IWETH(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(amountOut);
        payable(to).transfer(amountOut);
    }

    /* ------------------------------ WITHDRAW FEES ----------------------------- */
    function withdrawFees(address token, address to) external {
        if (to == address(0)) {
            revert GoatErrors.ZeroAddress();
        }
        GoatV1Pair pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));

        if (address(pair) == address(0)) {
            revert GoatErrors.GoatPoolDoesNotExist();
        }
        pair.withdrawFees(to);
    }

    /* --------------------------- INTERNAL FUNCTIONS --------------------------- */
    function _swapSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        bool isWethIn
    ) internal {
        GoatV1Pair pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        // Even though we have checked the balance before we need to user amount inupt
        // as the balance might have changed due to sell of taxes
        (, uint112 reserveToken) = pair.getStateInfoAmm();
        uint256 amountInput;
        if (isWethIn) {
            amountInput = amountIn;
        } else {
            amountInput = IERC20(token).balanceOf(address(pair)) - reserveToken;
        }
        (uint256 amountOutput,) = isWethIn
            ? _getAmountTokenOut(amountInput, amountOutMin, token)
            : _getAmountWethOut(amountInput, amountOutMin, token);
        pair.swap(isWethIn ? 0 : amountOutput, isWethIn ? amountOutput : 0, to);
    }

    function _addLiquidity(
        address token,
        uint256 tokenDesired,
        uint256 wethDesired,
        uint256 tokenMin,
        uint256 wethMin,
        GoatTypes.InitParams memory initParams
    ) internal returns (uint256, uint256, bool) {
        GoatTypes.LocalVariables_AddLiquidity memory vars;
        GoatV1Pair pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        if (address(pair) == address(0)) {
            // First time liquidity provider
            pair = GoatV1Pair(GoatV1Factory(factory).createPair(token, initParams));
            vars.isNewPair = true;
        }

        if (vars.isNewPair) {
            if (initParams.initialEth < initParams.bootstrapEth) {
                /**
                 * @dev if it's a first mint and pool is not directly converting to AMM,
                 * initialTokenMatch and virtualEth is used for liquidity calculation
                 */
                (vars.tokenAmount, vars.wethAmount) = (initParams.initialTokenMatch, initParams.virtualEth);
            } else {
                vars.actualTokenAmount = GoatLibrary.getBootstrapTokenAmountForAmm(
                    initParams.virtualEth, initParams.bootstrapEth, initParams.initialTokenMatch
                );
                /**
                 * @dev if it's a first mint and pool is directly converting to AMM,
                 * actual calculated token amount and real weth is used for liquidity calculation
                 */
                (vars.tokenAmount, vars.wethAmount) = (vars.actualTokenAmount, initParams.initialEth);
            }
        } else {
            /**
             * @dev This block is accessed after the presale period is over and the pool is converted to AMM
             */
            (uint256 wethReserve, uint256 tokenReserve,) = pair.getReserves();
            uint256 tokenAmountOptimal = GoatLibrary.quote(wethDesired, wethReserve, tokenReserve);
            if (tokenAmountOptimal <= tokenDesired) {
                if (tokenAmountOptimal < tokenMin) {
                    revert GoatErrors.InsufficientTokenAmount();
                }
                (vars.tokenAmount, vars.wethAmount) = (tokenAmountOptimal, wethDesired);
            } else {
                uint256 wethAmountOptimal = GoatLibrary.quote(tokenDesired, tokenReserve, wethReserve);
                assert(wethAmountOptimal <= wethDesired);
                if (wethAmountOptimal < wethMin) {
                    revert GoatErrors.InsufficientWethAmount();
                }
                (vars.tokenAmount, vars.wethAmount) = (tokenDesired, wethAmountOptimal);
            }
        }
        return (vars.tokenAmount, vars.wethAmount, vars.isNewPair);
    }

    function _ensurePoolAndPrepareLiqudityParameters(
        address token,
        uint256 tokenDesired,
        uint256 wethDesired,
        uint256 tokenMin,
        uint256 wethMin,
        GoatTypes.InitParams memory initParams,
        bool isEth
    ) internal returns (GoatTypes.LocalVariables_AddLiquidity memory vars) {
        if (token == WETH || token == address(0)) {
            revert GoatErrors.WrongToken();
        }
        vars.token = token;
        (vars.tokenAmount, vars.wethAmount, vars.isNewPair) =
            _addLiquidity(token, tokenDesired, wethDesired, tokenMin, wethMin, initParams);

        if (vars.isNewPair) {
            // only for the first time
            vars.wethAmount = Math.min(initParams.initialEth, initParams.bootstrapEth);
            vars.actualTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
                initParams.virtualEth, initParams.bootstrapEth, vars.wethAmount, initParams.initialTokenMatch
            );
        } else {
            vars.actualTokenAmount = vars.tokenAmount;
        }
        if (isEth && wethDesired != vars.wethAmount) {
            revert GoatErrors.InvalidEthAmount();
        }
        vars.pair = GoatV1Factory(factory).getPool(vars.token);
    }

    function _getAmountTokenOut(uint256 amountIn, uint256 amountOutMin, address token)
        internal
        view
        returns (uint256 amountTokenOut, GoatV1Pair pair)
    {
        if (amountIn == 0) {
            revert GoatErrors.InsufficientInputAmount();
        }
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        if (address(pair) == address(0)) {
            revert GoatErrors.GoatPoolDoesNotExist();
        }
        if (pair.vestingUntil() != MAX_UINT32) {
            /**
             * @dev If pool is not in presale period, then it's in AMM mode
             * Normal amountOut calculation is done with real reserves
             */
            (uint112 reserveEth, uint112 reserveToken) = pair.getStateInfoAmm();
            amountTokenOut = GoatLibrary.getTokenAmountOutAmm(amountIn, reserveEth, reserveToken);
        } else {
            /**
             * @dev If pool is in presale period,
             * amountOut calculation is done with inflated reserves and initParams
             */
            (
                vars.reserveEth,
                vars.reserveToken,
                vars.virtualEth,
                vars.initialTokenMatch,
                vars.bootstrapEth,
                vars.virtualToken
            ) = pair.getStateInfoForPresale();

            uint256 tokenAmountForAmm =
                GoatLibrary.getBootstrapTokenAmountForAmm(vars.virtualEth, vars.bootstrapEth, vars.initialTokenMatch);
            amountTokenOut = GoatLibrary.getTokenAmountOutPresale(
                amountIn,
                vars.virtualEth,
                vars.reserveEth,
                vars.bootstrapEth,
                vars.reserveToken,
                vars.virtualToken,
                tokenAmountForAmm
            );
        }
        if (amountTokenOut < amountOutMin) {
            revert GoatErrors.InsufficientAmountOut();
        }
    }

    function _getAmountWethOut(uint256 amountIn, uint256 amountOutMin, address token)
        internal
        view
        returns (uint256 amountWethOut, GoatV1Pair pair)
    {
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        if (pair == GoatV1Pair(address(0))) {
            revert GoatErrors.GoatPoolDoesNotExist();
        }
        if (pair.vestingUntil() != type(uint32).max) {
            (uint112 reserveEth, uint112 reserveToken) = pair.getStateInfoAmm();
            amountWethOut = GoatLibrary.getWethAmountOutAmm(amountIn, reserveEth, reserveToken);
        } else {
            (vars.reserveEth, vars.reserveToken, vars.virtualEth,,, vars.virtualToken) = pair.getStateInfoForPresale();

            amountWethOut = GoatLibrary.getWethAmountOutPresale(
                amountIn, vars.reserveEth, vars.reserveToken, vars.virtualEth, vars.virtualToken
            );
        }
        if (amountWethOut < amountOutMin) {
            revert GoatErrors.InsufficientAmountOut();
        }
    }

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB) {
        return GoatLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        //path[0] is the input token and path[1] is the output token
        if (path.length != 2) revert GoatErrors.InvalidPath(); // only allow swap in one pool for now
        if (path[0] != WETH && path[1] != WETH) {
            // One of the token should be WETH
            revert GoatErrors.InvalidPath();
        }
        address token = path[0] == WETH ? path[1] : path[0];
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        if (path[0] == WETH) {
            // Token in is WETH
            (uint256 amountOut,) = _getAmountTokenOut(amountIn, 0, token);
            amounts[1] = amountOut;
        } else {
            // Token out is WETH
            (uint256 amountOut,) = _getAmountWethOut(amountIn, 0, token);
            amounts[1] = amountOut;
        }
    }

    function getTokenAmountOut(uint256 amountWethIn, address token) external view returns (uint256 tokenAmountOut) {
        (tokenAmountOut,) = _getAmountTokenOut(amountWethIn, 0, token);
    }

    function getWethAmountOut(uint256 amountTokenIn, address token) external view returns (uint256 wethAmountOut) {
        (wethAmountOut,) = _getAmountWethOut(amountTokenIn, 0, token);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        if (path.length != 2) revert GoatErrors.InvalidPath(); // only allow swap in one pool for now
        if (path[0] != WETH && path[1] != WETH) {
            // One of the token should be WETH
            revert GoatErrors.InvalidPath();
        }
        address token = path[0] == WETH ? path[1] : path[0];
        amounts = new uint256[](2);
        amounts[1] = amountOut;
        if (path[0] == WETH) {
            // Token in is WETH so, we ned to figure how much wethIn is needed for desired token amountOut
            uint256 amountIn = getWethAmountIn(amountOut, token);
            amounts[0] = amountIn;
        } else {
            // Token out is WETH, so we need to figure out how much tokenIn is needed for desired weth amountOut
            uint256 amountIn = getTokenAmountIn(amountOut, token);
            amounts[0] = amountIn;
        }
    }

    function getTokenAmountIn(uint256 wethAmountOut, address token) public view returns (uint256 tokenAmountIn) {
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        GoatV1Pair pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        if (address(pair) == address(0)) {
            revert GoatErrors.GoatPoolDoesNotExist();
        }
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();

        tokenAmountIn = GoatLibrary.getTokenAmountIn(
            wethAmountOut, vars.reserveEth, vars.reserveToken, vars.virtualEth, vars.virtualToken, pair.vestingUntil()
        );
    }

    function getWethAmountIn(uint256 tokenAmountOut, address token) public view returns (uint256 wethAmountIn) {
        GoatTypes.LocalVariables_PairStateInfo memory vars;
        GoatV1Pair pair = GoatV1Pair(GoatV1Factory(factory).getPool(token));
        if (address(pair) == address(0)) {
            revert GoatErrors.GoatPoolDoesNotExist();
        }
        (
            vars.reserveEth,
            vars.reserveToken,
            vars.virtualEth,
            vars.initialTokenMatch,
            vars.bootstrapEth,
            vars.virtualToken
        ) = pair.getStateInfoForPresale();

        wethAmountIn = GoatLibrary.getWethAmountIn(
            tokenAmountOut,
            vars.virtualEth,
            vars.virtualToken,
            vars.reserveEth,
            vars.reserveToken,
            vars.bootstrapEth,
            vars.initialTokenMatch,
            pair.vestingUntil()
        );
    }

    function getActualBootstrapTokenAmount(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) public pure returns (uint256 actualTokenAmount) {
        return GoatLibrary.getActualBootstrapTokenAmount(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
    }
}
