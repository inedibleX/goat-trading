// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Utility contract so the frontend can easily check many total supplies at once.
 */
contract SupplyChecker {

    function checkSupplies(address[] memory _tokens)
      external
      view
    returns (uint256[] memory supplies)
    {
        supplies = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            supplies[i] = IERC20(_tokens[i]).totalSupply();
        }
    }

}
