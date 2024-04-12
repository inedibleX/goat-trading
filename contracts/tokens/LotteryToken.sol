// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./TaxToken.sol";

interface ILotteryMaster {
    function upkeep(uint256 loops) external;
    function addEntry(address user, uint256 entryAmount) external;
}

/**
 * @title Lottery Token
 * @author Robert M.C. Forster
 * @notice Actual token for the lottery scheme. Tax token that also adds taxes to a lottery pot.
 * @dev On every single token transfer it also calls back to the lottery master to check
 *      whether previous entries for any token have won their own lottery.
 *
 */
contract LotteryToken is TaxToken {
    // The maximum amount over entry amount that the user can win.
    // 10000 == 100x
    uint256 public maxWinMultiplier;

    // Chance for a win to occur. Can be from 1 - 1 million.
    uint256 public winChance;

    // Factory contract that holds all lottery token entries.
    address public lotteryMaster;

    // Amount of tokens currently in the pot able to payout lottery wins.
    uint256 public lotteryPot;

    // Percent of tokens to be put into the pot. 100 == 1%.
    uint256 public potPercent;

    event LotteryWin(address user, uint256 entryAmount, uint256 winnings, uint256 timestamp);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _maxWinMultiplier,
        uint256 _potPercent,
        address _weth
    ) TaxToken(_name, _symbol, _initialSupply, _weth) {
        maxWinMultiplier = _maxWinMultiplier;
        potPercent = _potPercent;
    }

    /* ********************************************* INTERNAL ********************************************* */

    // OpenZeppelin ERC20 _update with only change being upkeep and entry calls.
    function _update(address from, address to, uint256 value) internal override {
        uint256 tax = _determineTax(from, to, value);
        // Final value to be received by address.
        uint256 receiveValue = value - tax;

        // Every transfer calls to upkeep the lottery.
        ILotteryMaster(lotteryMaster).upkeep(0);

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

            // Add lottery entry for the user receiving tokens.
            if (taxed[from]) ILotteryMaster(lotteryMaster).addEntry(to, value);
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                // Weird situation with taxes but if you somehow tax burning it should be receiveValue here.
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
        } else {
            _sellTaxes();
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev In versions with more advanced tax features, this function will be overridden.
     * @param _amount Amount of tax tokens to be awarded.
     *
     */
    function _awardTaxes(uint256 _amount) internal override {
        uint256 potGain = _amount * potPercent / _DIVISOR;
        _balances[address(this)] += _amount - potGain;
    }

    /* ********************************************* PRIVILEGED ********************************************* */

    /**
     * @notice Lottery master calls in here to payout a win.
     * @param _user The user address who's won the lottery.
     * @param _entryAmount The amount of tokens they purchased with this entry which determines their maximum win.
     *
     */
    function payWinner(address _user, uint256 _entryAmount) external {
        require(msg.sender == lotteryMaster, "Only LotteryMaster may pay winner.");

        uint256 maxWin = _entryAmount * maxWinMultiplier;
        uint256 winnings = maxWin < lotteryPot ? maxWin : lotteryPot;

        lotteryPot -= winnings;
        _balances[_user] += winnings;

        emit LotteryWin(_user, _entryAmount, winnings, block.timestamp);
    }

    /**
     * @notice Change the percent of taxes that are put into the lottery pot.
     * @param _newPotPercent New percent of taxes that are put into the pot. 100 == 1%.
     *
     */
    function changePotPercent(uint256 _newPotPercent) external onlyOwnerOrTreasury {
        require(_newPotPercent <= _DIVISOR, "New vault percent too high.");
        potPercent = _newPotPercent;
    }
}
