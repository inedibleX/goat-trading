// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "./ERC20.sol";
import {TokenErrors} from "./TokenErrors.sol";

interface IRouter {
    function getAmountsOut(uint256 amountIn, address[] memory path) external returns (uint256[] memory);

    function swapExactTokensForWeth(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external
        returns (uint256 amountWethOut);
    function swapExactTokensForWethSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external;
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
    uint256 internal constant _DIVISOR = 10_000;
    uint256 internal constant _TAX_MAX = 1_000;
    address internal immutable _WETH;

    // Team address that will receive tax profits.
    address public treasury;
    address public dex;

    // Pool address => % tax on the pool, 100 == 1%, 1000 (10%) maximum.
    mapping(address => uint256) public buyTax;
    mapping(address => uint256) public sellTax;

    // Used in some iterations such as TaxShare in a situation where a dex should be excluded from activity.
    mapping(address => bool) public taxed;

    /* ********************************************* CONSTRUCTOR ********************************************* */
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, address _weth)
        ERC20(_name, _symbol)
    {
        treasury = msg.sender;
        _WETH = _weth;
        _mint(msg.sender, _initialSupply);
    }

    /* ********************************************* INTERNAL ********************************************* */

    // If transfer is from a dex, apply buy tax
    // If transfer is to a dex, apply sell tax
    // Add tax to token contract balance and/or rewardAmount or lotteryAmount
    // If token contract balance is above a certain amount, sell tokens
    // OpenZeppelin ERC20 _update with only change being _updateRewards calls.
    function _update(address from, address to, uint256 value) internal virtual override {
        uint256 tax = _determineTax(from, to, value);
        // Final value to be received by address.
        uint256 receiveValue = value - tax;

        // We need to sell taxes before updating balances because user transfer
        // to pair contract will trigger sell taxes and update reserves by using
        //  the new balance reverting the transaction.
        if (tax > 0) {
            _awardTaxes(tax);
            _sellTaxes(tax);
        }

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

        emit Transfer(from, to, value);
    }

    /**
     * @notice Determine how much tax needs to be paid.
     * @param _from User/contract that funds are being sent from.
     * @param _to User/contract that funds are being sent to.
     * @param _value Value of the funds being sent.
     *
     */
    function _determineTax(address _from, address _to, uint256 _value) internal view returns (uint256 taxAmount) {
        uint256 fromTax = buyTax[_from];
        uint256 toTax = sellTax[_to];

        // If there's no tax, will just equal 0.
        taxAmount += _value * fromTax / _DIVISOR;
        taxAmount += _value * toTax / _DIVISOR;
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
    function _sellTaxes(uint256 tokens) internal virtual {
        if (dex == address(0) || dex.code.length == 0) {
            // transfer tax to treasury if dex is not set
            _transfer(address(this), treasury, tokens);
            return;
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _WETH;

        // Try/catch because this will revert on buy txns because of reentrancy
        try IRouter(dex).swapExactTokensForWethSupportingFeeOnTransferTokens(
            tokens, 0, address(this), treasury, block.timestamp
        ) {} catch (bytes memory) {
            // transfer tax tokens to treasury sell of tax tokens fail
            _transfer(address(this), treasury, tokens);
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
        if (msg.sender != treasury && msg.sender != owner()) revert TokenErrors.OnlyOwnerOrTreasury();
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
     * @notice Change the dex that taxes are to be sold on. Requires a Uni V2 interface.
     * @param _dexAddress New address to sell tokens on.
     *
     */
    function changeDex(address _dexAddress) external onlyOwnerOrTreasury {
        if (dex != address(0)) {
            IERC20(address(this)).approve(dex, 0);
        }
        dex = _dexAddress;
        IERC20(address(this)).approve(_dexAddress, type(uint256).max);
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
    function setTaxes(address _dex, uint256 _buyTax, uint256 _sellTax) external virtual onlyOwner {
        if (_buyTax > _TAX_MAX || _sellTax > _TAX_MAX) revert TokenErrors.TaxTooHigh();
        buyTax[_dex] = _buyTax;
        sellTax[_dex] = _sellTax;

        if (_buyTax > 0 || _sellTax > 0) taxed[_dex] = true;
        else taxed[_dex] = false;
    }

    /* ********************************************* VIEW FUNCTIONS ********************************************* */
    function getTaxes(address _dex) external view returns (uint256 buy, uint256 sell) {
        return (buyTax[_dex], sellTax[_dex]);
    }
}
