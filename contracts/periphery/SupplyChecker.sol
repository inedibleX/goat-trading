// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPair {
    function getStateInfoAmm() external view returns (uint112 reserveEth, uint112 reserveToken);
}
/**
 * @notice Utility contract so the frontend can easily check many total supplies at once.
 */

contract SupplyChecker {
    function checkSupplies(address[] memory tokens) external view returns (uint256[] memory supplies) {
        supplies = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            supplies[i] = IERC20(tokens[i]).totalSupply();
        }
    }

    function getActualPoolReserves(address[] memory pairs) external view returns (uint256[][] memory reserves) {
        reserves = new uint256[][](pairs.length);
        for (uint256 i = 0; i < pairs.length; i++) {
            (uint112 reserveEth, uint112 reserveToken) = IPair(pairs[i]).getStateInfoAmm();
            uint256[] memory pairReserves = new uint256[](2);
            pairReserves[0] = uint256(reserveEth);
            pairReserves[1] = uint256(reserveToken);
            reserves[i] = pairReserves;
        }
    }
}
