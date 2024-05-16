// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGoatV1Router} from "./../interfaces/IGoatV1Router.sol";
import {IGoatV1Factory} from "./../interfaces/IGoatV1Factory.sol";
import {IGoatV1Pair} from "./../interfaces/IGoatV1Pair.sol";

/**
 * @notice Utility contract so the frontend can easily check many total supplies at once.
 */
contract GoatHelper {
    address internal immutable _ROUTER;
    address internal immutable _FACTORY;
    address internal immutable _WETH;
    uint256 internal constant _DIVISOR = 10_000;
    uint256 internal constant _ONE = 1e18;

    constructor(address router) {
        _ROUTER = router;
        _FACTORY = IGoatV1Router(router).factory();
        _WETH = IGoatV1Router(router).WETH();
    }

    function checkSupplies(address[] memory tokens) external view returns (uint256[] memory supplies) {
        supplies = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            supplies[i] = IERC20(tokens[i]).totalSupply();
        }
    }

    function getLpBalances(address[] memory pairs, address account) external view returns (uint256[] memory balances) {
        balances = new uint256[](pairs.length);
        for (uint256 i = 0; i < pairs.length; i++) {
            balances[i] = IGoatV1Pair(pairs[i]).balanceOf(account);
        }
    }

    function getVestingUntil(address[] memory pairs) external view returns (uint256[] memory vestingUntils) {
        vestingUntils = new uint256[](pairs.length);
        uint256 length = pairs.length;
        for (uint256 i = 0; i < length; i++) {
            vestingUntils[i] = IGoatV1Pair(pairs[i]).vestingUntil();
        }
    }

    function getActualPoolReserves(address[] memory pairs) external view returns (uint256[][] memory reserves) {
        reserves = new uint256[][](pairs.length);
        for (uint256 i = 0; i < pairs.length; i++) {
            (uint112 reserveEth, uint112 reserveToken) = IGoatV1Pair(pairs[i]).getStateInfoAmm();
            uint256[] memory pairReserves = new uint256[](2);
            pairReserves[0] = uint256(reserveEth);
            pairReserves[1] = uint256(reserveToken);
            reserves[i] = pairReserves;
        }
    }

    function getLockedLiquidityPercentages(address[] memory pairs)
        external
        view
        returns (uint32[] memory percentages)
    {
        percentages = new uint32[](pairs.length);
        address initialLp;
        uint256 initialLpBalance;
        uint256 totalSupply;

        for (uint256 i = 0; i < pairs.length; i++) {
            initialLp = IGoatV1Pair(pairs[i]).getInitialLPInfo().liquidityProvider;
            initialLpBalance = IGoatV1Pair(pairs[i]).balanceOf(initialLp);
            totalSupply = IGoatV1Pair(pairs[i]).totalSupply();
            percentages[i] = uint32((((initialLpBalance * _DIVISOR) / totalSupply)));
        }
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts) {
        address token;
        bool isSell;

        amounts = IGoatV1Router(_ROUTER).getAmountsOut(amountIn, path);

        // Check what will be dumped
        if (path[0] == _WETH) {
            token = path[1];
        } else {
            token = path[0];
            isSell = true;
        }

        IGoatV1Pair pair = IGoatV1Pair(IGoatV1Factory(_FACTORY).getPool(token));

        // making static call because some tokens may not have taxes
        // and will revert if we call directly
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("getTaxes(address)", address(pair)));

        if (success && data.length >= 64) {
            (uint256 buyTax, uint256 sellTax) = abi.decode(data, (uint256, uint256));
            if (isSell) {
                // Taxes from current txn
                uint256 taxToSell = (amounts[0] * sellTax) / _DIVISOR;

                // get actual amount out after taxes
                amounts = IGoatV1Router(_ROUTER).getAmountsOut(amountIn - taxToSell, path);

                //
                // so keeping it as original amount In because amount[0] returned
                // to should be original amountIn
                amounts[0] = amountIn;

                if (pair.vestingUntil() < block.timestamp) {
                    // This means we are in an amm phase of the pool

                    // Taxes from previous txns stuck inside the tax tokens
                    uint256 tokenBalance = IERC20(token).balanceOf(token);
                    if (tokenBalance > (taxToSell * 2)) {
                        // tax token will sell only 3X the current tax amount
                        // even if there is more tax stuck inside
                        taxToSell += (taxToSell * 2);
                    } else {
                        taxToSell += tokenBalance;
                    }

                    // as we know path is same for sell
                    uint256[] memory taxAmounts = IGoatV1Router(_ROUTER).getAmountsOut(taxToSell, path);

                    // get reserves or pair contract
                    (uint112 reserveEth, uint112 reserveToken,) = pair.getReserves();

                    uint256 priceImpact;
                    //  calculate price impact because of tax sold before sell txn
                    {
                        uint256 ratio_in = (taxAmounts[0] * _ONE) / reserveToken;
                        uint256 ratio_out = (taxAmounts[1] * _ONE) / (reserveEth - taxAmounts[1]);
                        uint256 ratioDiff = ((ratio_in * _DIVISOR) / ratio_out);

                        if (ratioDiff > _DIVISOR) {
                            priceImpact = ratioDiff - _DIVISOR;
                        } else {
                            priceImpact = _DIVISOR - ratioDiff;
                        }
                    }
                    // amount out should be lesser than amounts[1] because of price impact
                    amounts[1] = amounts[1] - ((amounts[1] * priceImpact) / _DIVISOR);
                }
            } else {
                // if it's a buy txn
                // amount out should be lesser than amounts[1] because of tax
                amounts[1] -= (amounts[1] * buyTax) / _DIVISOR;
            }
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) external view returns (uint256[] memory amounts) {
        address token;
        bool isSell;

        // Check what will be dumped
        if (path[0] == _WETH) {
            token = path[1];
        } else {
            token = path[0];
            isSell = true;
        }

        IGoatV1Pair pair = IGoatV1Pair(IGoatV1Factory(_FACTORY).getPool(token));

        // making static call because some tokens may not have taxes
        // and will revert if we call directly
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("getTaxes(address)", address(pair)));

        if (success && data.length >= 64) {
            (uint256 buyTax, uint256 sellTax) = abi.decode(data, (uint256, uint256));
            if (isSell) {
                amounts = IGoatV1Router(_ROUTER).getAmountsIn(amountOut, path);
                if (pair.vestingUntil() > block.timestamp) {
                    // This means we are in an amm phase of the pool
                    // and sell txns will dump taxes before selling so pirce impact
                    // should be considered
                    uint256 taxToSell = (amounts[0] * sellTax) / _DIVISOR;

                    // Taxes from previous txns stuck inside the tax tokens
                    uint256 tokenBalance = IERC20(token).balanceOf(token);
                    if (tokenBalance > (taxToSell * 2)) {
                        // tax token will sell only 3X the current tax amount
                        // even if there is more tax stuck inside
                        taxToSell += (taxToSell * 2);
                    } else {
                        taxToSell += tokenBalance;
                    }

                    // as we know path is same for sell
                    uint256[] memory taxAmounts = IGoatV1Router(_ROUTER).getAmountsOut(taxToSell, path);

                    // get reserves or pair contract
                    (uint112 reserveEth, uint112 reserveToken,) = pair.getReserves();

                    uint256 priceImpact;
                    //  calculate price impact because of tax sold before sell txn
                    {
                        uint256 ratio_in = (taxAmounts[0] * _ONE) / reserveToken;
                        uint256 ratio_out = (taxAmounts[1] * _ONE) / (reserveEth - taxAmounts[1]);
                        uint256 ratioDiff = ((ratio_in * _DIVISOR) / ratio_out);

                        if (ratioDiff > _DIVISOR) {
                            priceImpact = ratioDiff - _DIVISOR;
                        } else {
                            priceImpact = _DIVISOR - ratioDiff;
                        }
                    }
                    amounts[0] = (amounts[0] * (_DIVISOR + priceImpact) / _DIVISOR) + 1;
                } else {
                    // as taxes cannot be dumped we only add tax to amountIn
                    amounts[0] = (amounts[0] * (_DIVISOR + sellTax) / _DIVISOR) + 1;
                }
            } else {
                amountOut = amountOut * (_DIVISOR + buyTax) / _DIVISOR;
                amounts = IGoatV1Router(_ROUTER).getAmountsIn(amountOut, path);
            }
        }
    }
}
