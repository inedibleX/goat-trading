// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeOnTransferToken is ERC20, Ownable {
    uint256 public feePercentage = 1; // 1%

    constructor() ERC20("FeeOnTransferToken", "FOTT") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        _transfer(_msgSender(), address(this), fee);
        _transfer(_msgSender(), recipient, amount - fee);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        _transfer(sender, address(this), fee);
        _transfer(sender, recipient, amount - fee);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()) - amount);
        return true;
    }
}
