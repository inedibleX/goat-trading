// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "./ERC20.sol";

/**
 * @title Plain Token
 * @author Robert M.C. Forster
 * @notice Just a plain token cause why not have one *shrugging emoticon*
**/
contract PlainToken is ERC20, Ownable {

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) 
        ERC20(_name, _symbol) 
    {
        _mint(msg.sender, _initialSupply);
    }

}