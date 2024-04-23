// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./TaxToken.sol";
import {TokenErrors} from "./TokenErrors.sol";

/**
 * @title TaxShare Token
 * @author Robert M.C. Forster
 * @notice This is a type of tax token that shares a percent of taxes with users. Whenever taxes are
 *         taken from a transaction, a portion of the tokens are split between all holders proportionally.
 * @dev Balances in this contract automatically increase every time taxes are taken--sort of interest-bearing.
 *
 */
contract TaxShareToken is TaxToken {
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;

    // Amount of taxes to be shared with users. 100 == 1%.
    uint256 public sharePercent;

    // Number of tokens that are not receiving rewards. This amount subtracted from total supply
    // when determining rewards per token so people get full rewards owed.
    uint256 public excludedSupply;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _sharePercent,
        address _weth
    ) TaxToken(_name, _symbol, _initialSupply, _weth) {
        sharePercent = _sharePercent;
    }

    // Not on tax token by default because Ether is only sent to treasury there.

    receive() external payable {}

    /* ********************************************* VIEW ********************************************* */

    /**
     * @notice Get the balance of a user including unclaimed rewards.
     * @param user Address of the account to check the balance of.
     *
     */
    function balanceOf(address user) public view override returns (uint256 balance) {
        balance = _balances[user];
        // taxed addresses, burned addresses and tax fees will not accrue rewards.
        if (user != address(0) && user != address(this) && !taxed[user]) {
            balance += _earned(user);
        }
    }

    /* ********************************************* INTERNAL ********************************************* */

    /**
     * @notice Find the amount earned by a user since the last update of their balance.
     * @dev Using this rather than coding it into each function individually will likely be less gas efficient,
     *      but it avoids any mistakes re-coding it.
     * @param _user Address of the user to find rewards for.
     *
     */
    function _earned(address _user) internal view returns (uint256 unclaimedRewards) {
        // 1e18 is removed from balance because rewardPerToken is in full tokens.
        unclaimedRewards = (rewardPerTokenStored - userRewardPerTokenPaid[_user]) * (_balances[_user] / 1e18);
    }

    // TaxToken _update with only change being _updateRewards calls.
    function _update(address from, address to, uint256 value) internal override {
        uint256 tax = _determineTax(from, to, value);
        // Final value to be received by address.
        uint256 receiveValue = value - tax;

        // TaxShare: Add rewards to both user token balance.
        _updateRewards(from, to);
        // Update excluded supply.
        _updateExcluded(from, to, value);

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
                _balances[to] += receiveValue;
            }
        }

        // External interaction here must come after state changes.
        if (tax > 0) {
            _awardTaxes(tax);
            _sellTaxes(tax);
        }

        emit Transfer(from, to, value);
    }

    /**
     * @notice Update user balance with unclaimed rewards. Store new point where user has been paid.
     * @dev It's imperative that this is called before any balance change or calcs will be off.
     * @param _from First address of which to update rewards.
     * @param _to Second address of which to update rewards.
     *
     */
    function _updateRewards(address _from, address _to) internal {
        if (_from != address(0) && _from != address(this) && !taxed[_from]) {
            _balances[_from] += _earned(_from);
            userRewardPerTokenPaid[_from] = rewardPerTokenStored;
        }
        if (_to != address(0) && _to != address(this) && !taxed[_to]) {
            _balances[_to] += _earned(_to);
            userRewardPerTokenPaid[_to] = rewardPerTokenStored;
        }
    }

    /**
     * @notice Update the amount of tokens excluded from reward calculations.
     *         Includes excluding 0, this, and taxed.
     * @param _from The address sending tokens.
     * @param _to The address receiving tokens.
     * @param _value The amount of tokens being sent.
     *
     */
    function _updateExcluded(address _from, address _to, uint256 _value) internal {
        if (_to == address(this) || taxed[_to]) excludedSupply += _value;
        if (_from == address(this) || taxed[_from]) excludedSupply -= _value;
    }

    /**
     * @notice In addition to awarding taxes to this address, add them to the rewards for users.
     * @param _amount Amount of tax tokens to be awarded.
     *
     */
    function _awardTaxes(uint256 _amount) internal override {
        uint256 reward = _amount * sharePercent / _DIVISOR;
        // 1e18 is removed because rewardPerToken is in full tokens
        rewardPerTokenStored += reward / ((_totalSupply - excludedSupply) / 1e18);
        _balances[address(this)] += _amount - reward;
    }

    /* ********************************************* ONLY OWNER/TREASURY ********************************************* */
    /**
     * @notice Change the percent of taxes to be shared with users.
     * @param _newSharePercent New percent of taxes to be shared. 100 == 1%.
     *
     */
    function changeSharePercent(uint256 _newSharePercent) external onlyOwnerOrTreasury {
        if (_newSharePercent > _DIVISOR) revert TokenErrors.NewVaultPercentTooHigh();
        sharePercent = _newSharePercent;
    }
}
