// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TokenType} from "../library/TokenTypes.sol";
import {GoatTypes} from "../../library/GoatTypes.sol";

interface ITokenFactory {
    function createToken(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _buyTax,
        uint256 _sellTax,
        address _owner,
        TokenType _type,
        uint256 _percent,
        GoatTypes.InitParams memory initParams
    ) external returns (address tokenAddress, address pool);
}
