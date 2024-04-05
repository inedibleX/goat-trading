// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRouter {
    function getAmountsOut(uint256 amountIn, address[] memory path, address tokenOut) external returns (uint256);
    function swapExactTokensForEth(
        uint256 amountIn,
        uint256 minAmountOut,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256);
}

/**
 * @title Plain Tax Token
 * @author Robert M.C. Forster
 * @notice This is a pretty plain tax token. When a transfer is made to or from a dex, a sell or buy tax is applied respectively.
 *         The tax is taken in tokens, then when it gets past a minimum amount a dex swap is automatically executed to trade the
 *         taxes for Ether. Ownership is split between "owner" and "treasury" so the power to change taxes can be relinquished
 *         without losing the power to change where taxes are sent or change what dex taxes are sold on.
 *
 */
contract TaxToken is ERC20, Ownable {
    uint256 constant DIVISOR = 10_000;
    uint256 constant TAX_MAX = 1_000;
    uint256 minSell;

    // Team address that will receive tax profits.
    address public treasury;
    address public dex;

    // This is for Base, must be changed for other chains.
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Pool address => % tax on the pool, 100 == 1%, 1000 (10%) maximum.
    mapping(address => uint256) public buyTax;
    mapping(address => uint256) public sellTax;

    // Used in some iterations such as TaxShare in a situation where a dex should be excluded from activity.
    mapping(address => bool) public taxed;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        // Somewhat arbitrary minimumSell beginning
        minSell = 0.1 ether;
        treasury = msg.sender;
        _mint(msg.sender, _initialSupply);
    }

    /* ********************************************* INTERNAL ********************************************* */

    // If transfer is from a dex, apply buy tax
    // If transfer is to a dex, apply sell tax
    // Add tax to token contract balance and/or rewardAmount or lotteryAmount
    // If token contract balance is above a certain amount, sell tokens
    // OpenZeppelin ERC20 _update with only change being _updateRewards calls.
    function _update(address from, address to, uint256 value) internal virtual override {
        uint256 tax = determineTax(from, to, value);
        // Final value to be received by address.
        uint256 receiveValue = value - tax;

        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= receiveValue;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                // Default value here changed to receiveValue to account for possible taxes.
                _balances[to] += receiveValue;
            }
        }

        // External interaction here must come after state changes.
        if (tax > 0) {
            _awardTaxes(tax);
            _sellTaxes();
        }

        emit Transfer(from, to, value);
    }

    /**
     * @notice Determine how much tax needs to be paid.
     * @param _from User/contract that funds are being sent from.
     * @param _to User/contract that funds are being sent to.
     * @param _value Value of the funds being sent.
     *
     */
    function determineTax(address _from, address _to, uint256 _value) internal view returns (uint256 taxAmount) {
        uint256 fromTax = buyTax[_from];
        uint256 toTax = sellTax[_to];

        // If there's no tax, will just equal 0.
        taxAmount += _value * fromTax / DIVISOR;
        taxAmount += _value * toTax / DIVISOR;
    }

    /**
     * @notice Give tax balances to a new address.
     * @dev In versions with more advanced tax features, this function will be overridden.
     * @param _amount Amount of tax tokens to be awarded.
     *
     */
    function _awardTaxes(uint256 _amount) internal virtual {
        _balances[address(this)] += _amount;
    }

    /**
     * @notice Sell taxes if the balance of treasury is over a pre-determined amount.
     *
     */
    function _sellTaxes() internal virtual returns (uint256 tokens, uint256 ethValue) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        tokens = _balances[address(this)];
        ethValue = IRouter(dex).getAmountsOut(tokens, path, WETH);
        if (ethValue > minSell) {
            // In a case such as a lot of taxes being gained during bootstrapping, we don't want to immediately dump all tokens.
            tokens = tokens * minSell / ethValue;
            // Try/catch because during bootstrapping selling won't be allowed.
            try IRouter(dex).swapExactTokensForEth(tokens, 0, path, treasury, block.timestamp) {}
                catch (bytes memory) {}
        }
    }

    /* ********************************************* ONLY OWNER/TREASURY ********************************************* */

    /**
     * @dev We need treasury to have permissions along with owner so that adjustments that need to always be there
     *      such as changing the dex that tokens are sold on can still be used if people want to renounce owner
     *      so that users don't have a worry that taxes will be changed from under there.
     *
     */
    modifier onlyOwnerOrTreasury() {
        require(msg.sender == treasury || msg.sender == owner(), "Only owner or treasury may call this function.");
        _;
    }

    /**
     * @notice Transfer treasury permissions to a new address.
     * @param _newTreasury Address to give treasury permissions to.
     *
     */
    function transferTreasury(address _newTreasury) external onlyOwnerOrTreasury {
        treasury = _newTreasury;
    }

    /**
     * @notice Change the minimum amount of Ether value required before selling taxes.
     * @param _newMinSell Minimum value required before a sell. In Ether wei so 1e18 is 1 Ether.
     *
     */
    function changeMinSell(uint256 _newMinSell) external onlyOwnerOrTreasury {
        minSell = _newMinSell;
    }

    /**
     * @notice Change the dex that taxes are to be sold on. Requires a Uni V2 interface.
     * @param _dexAddress New address to sell tokens on.
     *
     */
    function changeDex(address _dexAddress) external onlyOwnerOrTreasury {
        dex = _dexAddress;
    }

    /* ********************************************* ONLY OWNER ********************************************* */

    /**
     * @notice Set taxes of a specific dex/address based on buy and sell.
     * @dev This is onlyOwner rather than including treasury so that a team can renounce ownership
     *      of this critical function while maintaining ownership of non-critical treasury functions.
     * @param _dex Address of the dex that taxes are being added to when a transfer is made from/to it.
     * @param _buyTax The tax for buys (transactions coming from the address). 1% == 100.
     * @param _sellTax The tax for sells (transactions going to the address). 1% == 100.
     *
     */
    function setTaxes(address _dex, uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        require(_buyTax <= TAX_MAX && _sellTax <= TAX_MAX, "Tax attempting to be set too high.");
        buyTax[_dex] = _buyTax;
        sellTax[_dex] = _sellTax;

        if (_buyTax > 0 || _sellTax > 0) taxed[_dex] = true;
        else taxed[_dex] = false;
    }
}
