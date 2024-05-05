// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {GoatTypes} from "./../library/GoatTypes.sol";

interface IGoatV1Router {
    function WETH() external view returns (address);
    function FACTORY() external view returns (address);

    /* ----------------------------- ADD LIQUIDITY ----------------------------- */

    function addLiquidity(
        address token,
        uint256 tokenDesired,
        uint256 wethDesired,
        uint256 tokenMin,
        uint256 wethMin,
        address to,
        uint256 deadline,
        GoatTypes.InitParams memory initParams
    ) external returns (uint256, uint256, uint256);

    function addLiquidityETH(
        address token,
        uint256 tokenDesired,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline,
        GoatTypes.InitParams memory initParams
    ) external payable returns (uint256, uint256, uint256);

    /* ----------------------------- REMOVE LIQUIDITY ----------------------------- */
    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 wethMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountWeth, uint256 amountToken);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountWeth, uint256 amountToken);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountWeth);

    /* ----------------------------- SWAP FUNCTIONS FOR FEE ON TRANSFER TOKENS ----------------------------- */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactWethForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external;

    function swapETHForExactTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForWethSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external;

    /* ----------------------------- SWAP FUNCTIONS  ----------------------------- */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactWethForTokens(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external
        returns (uint256 amountTokenOut);

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256 amountTokenOut);

    function swapExactTokensForWeth(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external
        returns (uint256 amountWethOut);

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external
        returns (uint256 amountWethOut);

    /* ------------------------------ WITHDRAW FEES ----------------------------- */
    function withdrawFees(address token, address to) external;

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB);

    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts);

    function getTokenAmountOut(uint256 amountWethIn, address token) external view returns (uint256 tokenAmountOut);

    function getWethAmountOut(uint256 amountTokenIn, address token) external view returns (uint256 wethAmountOut);

    function getAmountsIn(uint256 amountOut, address[] memory path) external view returns (uint256[] memory amounts);

    function getTokenAmountIn(uint256 wethAmountOut, address token) external view returns (uint256 tokenAmountIn);

    function getWethAmountIn(uint256 tokenAmountOut, address token) external view returns (uint256 wethAmountIn);

    function getActualBootstrapTokenAmount(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) external pure returns (uint256 actualTokenAmount);
}
