// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC20.sol";

/**
 * @title Plain Token
 * @author Robert M.C. Forster
 * @notice Just a plain token cause why not have one *shrugging emoticon*
 *
 */
contract PlainToken is ERC20 {
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
    }
}
