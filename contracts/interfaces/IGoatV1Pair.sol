// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {GoatTypes} from "./../library/GoatTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGoatV1Pair is IERC20 {
    function lpFees(address, uint256) external view returns (uint256);
    function feesPerTokenPaid(address, uint256) external view returns (uint256);

    function initialize(address token, address weth, string memory baseName, GoatTypes.InitParams memory params)
        external;

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amountWeth, uint256 amountToken);

    function swap(uint256 amountTokenOut, uint256 amountWethOut, address to) external;

    function sync() external;

    function getReserves() external view returns (uint112 reserveEth, uint112 reserveToken);

    function withdrawExcessToken() external;

    function takeOverPool(GoatTypes.InitParams memory initParams) external;

    function withdrawFees(address to) external;

    function earned(address lp) external view returns (uint256);

    function vestingUntil() external view returns (uint32 vestingUntil_);

    function getStateInfoForPresale()
        external
        view
        returns (
            uint112 reserveEth,
            uint112 reserveToken,
            uint112 virtualEth,
            uint112 initialTokenMatch,
            uint112 bootstrapEth,
            uint256 virtualToken
        );

    function getStateInfoAmm() external view returns (uint112, uint112);

    function getInitialLPInfo() external view returns (GoatTypes.InitialLPInfo memory);

    function getPresaleBalance(address user) external view returns (uint256);

    function lockedUntil(address user) external view returns (uint32);

    function getFeesPerTokenStored() external view returns (uint256);

    function getPendingLiquidityFees() external view returns (uint112);

    function getPendingProtocolFees() external view returns (uint72);
}
