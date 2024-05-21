// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IToken is IERC20 {
    function setTaxes(address dex, uint256 buyTax, uint256 sellTax) external;
    function transferBeneficiary(address beneficiary) external;
    function transferOwnership(address owner) external;
    function transferTreasury(address treasury) external;
    function changeSafeHaven(address _safeHaven, bool _toAdd) external;
    function getTaxes(address token) external view returns (uint256 buyTax, uint256 sellTax);
    function revokeRewardsEligibility(address _user, bool _revoked) external;
    function changeDex(address _dexAddress) external;
}
