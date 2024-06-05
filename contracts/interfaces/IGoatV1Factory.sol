// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {GoatTypes} from "./../library/GoatTypes.sol";

interface IGoatV1Factory {
    function weth() external view returns (address);
    function getPool(address token) external view returns (address);
    function getPair(address token0, address token1) external view returns (address);
    function treasury() external view returns (address);
    function pendingTreasury() external view returns (address);
    function minimumCollectableFees() external view returns (uint256);
    function pools(address) external view returns (address);
    function removePair(address token) external;
    function createPair(address token, GoatTypes.InitParams memory params) external returns (address pool);
}
