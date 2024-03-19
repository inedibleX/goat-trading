// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 100000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
