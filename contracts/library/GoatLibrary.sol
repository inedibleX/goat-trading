// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Local Imports
import {GoatTypes} from "./GoatTypes.sol";
import {GoatErrors} from "./GoatErrors.sol";

/**
 * @title Goat Library
 * @notice Library for Goat periphery contracts.
 * @author Goat Trading -- Chiranjibi Poudyal, Robert M.C. Forster
 */
library GoatLibrary {
    ///@notice given some amount of asset and pair reserves,
    /// @return amountB an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert GoatErrors.InsufficientInputAmount();
        if (reserveA == 0 || reserveB == 0) revert GoatErrors.InsufficientLiquidity();

        amountB = (amountA * reserveB) / reserveA;
    }

    function getBootstrapTokenAmountForAmm(uint256 virtualEth, uint256 bootstrapEth, uint256 initialTokenMatch)
        internal
        pure
        returns (uint256 tokenAmtForAmm)
    {
        uint256 k = virtualEth * initialTokenMatch;
        uint256 totalEth = virtualEth + bootstrapEth;
        tokenAmtForAmm = (k * bootstrapEth) / (totalEth * totalEth);
    }

    function getTokenAmountOutAmm(uint256 amountWethIn, uint256 reserveEth, uint256 reserveToken)
        internal
        pure
        returns (uint256 amountTokenOut)
    {
        // 99 bps for fees
        uint256 actualWethIn = amountWethIn * 9901;

        uint256 numerator = actualWethIn * reserveToken;
        uint256 denominator = reserveEth * 10000 + actualWethIn;

        amountTokenOut = numerator / denominator;
    }

    function getTokenAmountOutPresale(
        uint256 amountWethIn,
        uint256 virtualEth,
        uint256 reserveEth,
        uint256 bootStrapEth,
        uint256 reserveToken,
        uint256 virtualToken,
        uint256 reserveTokenForAmm
    ) internal pure returns (uint256 amountTokenOut) {
        uint256 actualWethIn = (amountWethIn * 9901) / 10000;

        uint256 wethForAmm;
        uint256 wethForPresale;
        uint256 amountTokenOutPresale;
        uint256 amountTokenOutAmm;

        if (reserveEth + actualWethIn > bootStrapEth) {
            wethForAmm = (reserveEth + actualWethIn) - bootStrapEth;
        }
        wethForPresale = (actualWethIn - wethForAmm) * 10000;
        uint256 numerator = wethForPresale * (virtualToken + reserveToken);
        uint256 denominator = (reserveEth + virtualEth) * 10000 + wethForPresale;
        amountTokenOutPresale = numerator / denominator;

        if (wethForAmm > 0) {
            wethForAmm = wethForAmm * 10000;
            numerator = wethForAmm * reserveTokenForAmm;
            denominator = bootStrapEth * 10000 + wethForAmm;
            amountTokenOutAmm = numerator / denominator;
        }
        amountTokenOut = amountTokenOutPresale + amountTokenOutAmm;
    }

    function getTokenAmountOut(
        uint256 amountWethIn,
        uint256 virtualEth,
        uint256 reserveEth,
        uint32 vestingUntil,
        uint256 bootStrapEth,
        uint256 reserveToken,
        uint256 virtualToken,
        uint256 reserveTokenForAmm
    ) internal pure returns (uint256 amountTokenOut) {
        if (amountWethIn == 0) revert GoatErrors.InsufficientInputAmount();
        GoatTypes.LocalVariables_TokenAmountOutInfo memory vars;

        // 99 bps is considered as fees
        vars.actualWethIn = amountWethIn * 9901;

        if (vestingUntil != type(uint32).max) {
            // amm logic
            vars.numerator = vars.actualWethIn * reserveToken;
            vars.denominator = reserveEth * 10000 + vars.actualWethIn;
            vars.amountTokenOutAmm = vars.numerator / vars.denominator;
        } else {
            // Scale actual weth down
            vars.actualWethIn = vars.actualWethIn / 10000;

            if (reserveEth + vars.actualWethIn > bootStrapEth) {
                vars.wethForAmm = (reserveEth + vars.actualWethIn) - bootStrapEth;
            }
            vars.wethForPresale = (vars.actualWethIn - vars.wethForAmm) * 10000;
            vars.numerator = vars.wethForPresale * (virtualToken + reserveToken);
            vars.denominator = (reserveEth + virtualEth) * 10000 + vars.wethForPresale;
            vars.amountTokenOutPresale = vars.numerator / vars.denominator;

            if (vars.wethForAmm > 0) {
                vars.wethForAmm = vars.wethForAmm * 10000;
                vars.numerator = vars.wethForAmm * reserveTokenForAmm;
                vars.denominator = bootStrapEth * 10000 + vars.wethForAmm;
                vars.amountTokenOutAmm = vars.numerator / vars.denominator;
            }
        }
        amountTokenOut = vars.amountTokenOutPresale + vars.amountTokenOutAmm;
    }

    function getWethAmountOutAmm(uint256 amountTokenIn, uint256 reserveEth, uint256 reserveToken)
        internal
        pure
        returns (uint256 amountWethOut)
    {
        if (amountTokenIn == 0) revert GoatErrors.InsufficientInputAmount();
        if (reserveEth == 0 || reserveToken == 0) revert GoatErrors.InsufficientLiquidity();

        amountTokenIn = amountTokenIn * 10000;
        uint256 numerator;
        uint256 denominator;
        uint256 actualAmountWethOut;
        // amm logic
        numerator = amountTokenIn * reserveEth;
        denominator = reserveToken * 10000 + amountTokenIn;
        actualAmountWethOut = numerator / denominator;
        // 0.99% fee on WETH
        amountWethOut = (actualAmountWethOut * 9901) / 10000;
    }

    function getWethAmountOutPresale(
        uint256 amountTokenIn,
        uint256 reserveEth,
        uint256 reserveToken,
        uint256 virtualEth,
        uint256 virtualToken
    ) internal pure returns (uint256 amountWethOut) {
        if (amountTokenIn == 0) revert GoatErrors.InsufficientInputAmount();
        if (reserveEth == 0 || reserveToken == 0) revert GoatErrors.InsufficientLiquidity();
        amountTokenIn = amountTokenIn * 10000;
        uint256 numerator;
        uint256 denominator;
        uint256 actualAmountWETHOut;
        numerator = amountTokenIn * (virtualEth + reserveEth);
        denominator = (virtualToken + reserveToken) * 10000 + amountTokenIn;
        actualAmountWETHOut = numerator / denominator;
        // 0.99% fee on WETH
        amountWethOut = (actualAmountWETHOut * 9901) / 10000;
    }

    ///@notice given amount of token in and pool reserves
    /// @return amountWethOut an equivalent amount of the other asset
    function getWethAmountOut(
        uint256 amountTokenIn,
        uint256 reserveEth,
        uint256 reserveToken,
        uint256 virtualEth,
        uint256 virtualToken,
        uint32 vestingUntil
    ) internal pure returns (uint256 amountWethOut) {
        if (amountTokenIn == 0) revert GoatErrors.InsufficientInputAmount();
        if (reserveEth == 0 || reserveToken == 0) revert GoatErrors.InsufficientLiquidity();
        if (vestingUntil != type(uint32).max) {
            amountWethOut = getWethAmountOutAmm(amountTokenIn, reserveEth, reserveToken);
        } else {
            amountWethOut = getWethAmountOutPresale(amountTokenIn, reserveEth, reserveToken, virtualEth, virtualToken);
        }
    }

    function getActualBootstrapTokenAmount(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) internal pure returns (uint256 actualTokenAmount) {
        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) =
            _getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
        actualTokenAmount = tokenAmtForPresale + tokenAmtForAmm;
    }

    function getTokenAmountsForPresaleAndAmm(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) internal pure returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) {
        (tokenAmtForPresale, tokenAmtForAmm) =
            _getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, initialEth, initialTokenMatch);
    }

    function _getTokenAmountsForPresaleAndAmm(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) private pure returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) {
        uint256 k = virtualEth * initialTokenMatch;
        tokenAmtForPresale = initialTokenMatch - (k / (virtualEth + bootstrapEth));
        uint256 totalEth = virtualEth + bootstrapEth;
        tokenAmtForAmm = (k * bootstrapEth) / (totalEth * totalEth);

        if (initialEth != 0) {
            uint256 numerator = (initialEth * initialTokenMatch);
            uint256 denominator = virtualEth + initialEth;
            uint256 tokenAmountOut = numerator / denominator;
            tokenAmtForPresale -= tokenAmountOut;
        }
    }

    function getTokenAmountIn(
        uint256 wethAmountOut,
        uint256 reserveEth,
        uint256 reserveToken,
        uint256 virtualEth,
        uint256 virtualToken,
        uint32 vestingUntil
    ) internal pure returns (uint256 amountTokenIn) {
        // scale by 10000 to avoid rounding errors
        uint256 actualWethOut = ((wethAmountOut * 10000) / 9901);
        if (wethAmountOut == 0) revert GoatErrors.InsufficientOutputAmount();
        if (actualWethOut > reserveEth) revert GoatErrors.InsufficientLiquidity();
        uint256 numerator;
        uint256 denominator;
        // scale actual weth out by 10000
        actualWethOut = actualWethOut * 10000;
        if (vestingUntil == type(uint32).max) {
            numerator = actualWethOut * (virtualToken + reserveToken);
            denominator = (virtualEth + reserveEth) * 10000 - actualWethOut;
        } else {
            numerator = actualWethOut * reserveToken;
            denominator = reserveEth * 10000 - actualWethOut;
        }
        amountTokenIn = numerator / denominator;
    }

    function getWethAmountIn(
        uint256 tokenAmountOut,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 reserveWeth,
        uint256 reserveToken,
        uint256 bootstrapEth,
        uint256 initialTokenMatch,
        uint256 vestingUntil
    ) internal pure returns (uint256 amountWethIn) {
        //
        uint256 tokenAmountOutAmm;
        uint256 tokenAmountOutPresale;
        uint256 tokenReserveAmm;
        uint256 amtWethInAmm;
        uint256 amtWethInPresale;

        if (tokenAmountOut == 0) revert GoatErrors.InsufficientOutputAmount();
        if (tokenAmountOut > reserveToken) revert GoatErrors.InsufficientLiquidity();
        bool isPresale = vestingUntil == type(uint32).max;

        if (isPresale) {
            (, tokenReserveAmm) =
                _getTokenAmountsForPresaleAndAmm(virtualEth, bootstrapEth, bootstrapEth, initialTokenMatch);
            if (tokenAmountOut > (reserveToken - tokenReserveAmm)) {
                tokenAmountOutAmm = tokenAmountOut - (reserveToken - tokenReserveAmm);
                tokenAmountOutPresale = tokenAmountOut - tokenAmountOutAmm;
                amtWethInPresale = bootstrapEth - reserveWeth;
            } else {
                tokenAmountOutPresale = tokenAmountOut;
                amtWethInPresale =
                    _amountWethIn(tokenAmountOutPresale, reserveWeth + virtualEth, reserveToken + virtualToken);
            }
        } else {
            tokenAmountOutAmm = tokenAmountOut;
        }

        if (tokenAmountOutAmm != 0) {
            if (isPresale) {
                reserveToken -= tokenAmountOutPresale;
                reserveWeth += amtWethInPresale;
            }
            amtWethInAmm = _amountWethIn(tokenAmountOutAmm, reserveWeth, reserveToken);
        }

        amountWethIn = amtWethInAmm + amtWethInPresale;
        // take in account of 99 bps fees and scale it to ceiling
        amountWethIn = (amountWethIn * 10000 / 9901) + 1;
    }

    function _amountWethIn(uint256 tokenAmountOut, uint256 reserveWeth, uint256 reserveToken)
        private
        pure
        returns (uint256 amountWethIn)
    {
        uint256 numerator = reserveWeth * tokenAmountOut;
        uint256 denominator = (reserveToken - tokenAmountOut);
        amountWethIn = (numerator / denominator);
    }
}
