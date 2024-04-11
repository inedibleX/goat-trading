// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Demurrage Token: A token that decays over time if it's being held in unproductive manners.
 * @author Robert M.C. Forster
 * @notice This token's inspired by Mark Friedenbach's Freicoin and consequently Silvio Gesell's Freigeld.
 *         The demurrage aspect in those currencies, however, is meant to accelerate exchange of the currency,
 *         whereas the demurrage aspect in this token is meant to enforce productivity of the asset.
 *
 *         The token creator can decide any address that is safe from demurrage charges, such as a
 *         liquidity pool, lending protocol, staking contract, or more. Theoretically this could allow
 *         0% interest lending and 0 reward market making.
 *
 *         More info behind the concept here https://robertmcforster.medium.com/the-case-for-demurrage-tokens-be64619a888d
 * @dev The difficult part of demurrage tokens is that if you're charging a flat yearly percent,
 *      the time between your actions "compounding" will affect how much you're paying. For example,
 *      1% subtracted from a balance 100 times is very different from 100% subtracted once.
 *
 *      It's not the biggest deal for people to pay changing amounts based on how long they take to
 *      interact, but it is the biggest deal when it comes to giving the beneficiary tokens since their
 *      benefit will have the same problems and they will end up gaining a different number of tokens
 *      than users had lost.
 *
 *      The cleanest solution to ensure consistent fees is to compound every second, but with Solidity
 *      the math for that is unwieldy. Our solution is to compound on every interaction and to track
 *      the cumulative tokens taken, also track the average unproductive tokens paying those fees,
 *      then a user will end up paying the average of all loss during their unproductive time period.
 *
 *      While this still isn't the cleanest method for consistent results, it works well enough and
 *      maintains a consistent total supply.
 *
 */
contract DemurrageToken is ERC20, Ownable {
    /**
     * @dev The difficult part of demurrage tokens is that if you're charging a flat yearly percent,
     *      the time between your actions "compounding" will affect how much you're paying. For example,
     *      1% subtracted from a balance 100 times is very different from 100% subtracted once.
     *
     *      It's not the biggest deal for people to pay changing amounts based on how long they take to
     *      interact, but it is the biggest deal when it comes to giving the beneficiary tokens since their
     *      benefit will have the same problems and they will end up gaining a different number of tokens
     *      than users had lost.
     *
     *      The cleanest solution to ensure consistent fees is to compound every second, but with Solidity
     *      the math for that is unwieldy. Our solution is to compound on every interaction and to track
     *      the cumulative tokens taken, also track the average unproductive tokens paying those fees,
     *      then a user will end up paying the average of all loss during their unproductive time period.
     *
     *      While this still isn't the cleanest method for consistent results, it works well enough and
     *      maintains a consistent total supply.
     *
     */
    uint256 private constant _DIVISOR = 10_000;
    /**
     * @notice Address that will gain the decayed tokens.
     *
     */
    address public beneficiary;
    /**
     * @notice Total amount of tokens that are currently decaying, totalSupply() - safeHavenBalances.
     *
     */
    uint256 public decayingTokens;
    uint256 private _lastGlobalUpdate;
    /**
     * @notice The amount of decay to occur per second.
     * @dev Technically if you want a yearly charge of 5%, this needs to be greater than 5% / 1 year in seconds.
     *      Since it's compounded every second the amount decaying is constantly lowering. A 100% yearly charge
     *      compounded every second will be about $37 at the end of the year. Moreover, compounding doesn't
     *      actually occur every second but rather in an undetermined period based on how often interactions occur.
     *      If no one makes a transfer for a full year, 100% will be charged.
     *
     */
    uint256 public decayPercentPerSecond;
    uint256 private _cumulativeTokensPaid;
    uint256 private _cumulativeDecaying;

    // All addresses that are not exposed to decay.
    mapping(address => bool) public safeHavens;
    mapping(address => uint256) private _lastUserUpdate;
    mapping(address => uint256) private _lastUserTokensPaid;
    mapping(address => uint256) private _lastUserDecaying;

    error OnlyBeneficiaryOrOwner();

    /**
     * @dev Read above for an explanation of _decayPercentPerSecond.
     * @param _name Name for the token.
     * @param _symbol Symbol for the token.
     * @param _initialSupply Initial supply for the token that will be sent to msg.sender.
     * @param _decayPercentPerSecond Rate of token decay. Explained further above.
     *
     */
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, uint256 _decayPercentPerSecond)
        ERC20(_name, _symbol)
    {
        _mint(msg.sender, _initialSupply);
        // TODO: is thre a need to check _decayPercentPor second?

        decayPercentPerSecond = _decayPercentPerSecond;
        safeHavens[beneficiary] = true;
    }

    /* ********************************************* PUBLIC ********************************************* */

    /**
     * @notice balanceOf override. If an address is a safe haven, stored balance is returned. If it's not, we calculate
     *      balance based off how much has decayed since their last update.
     * @param user Address to find the balance of.
     *
     */
    function balanceOf(address user) public view override returns (uint256 balance) {
        if (safeHavens[user]) return _balances[user];

        uint256 tokensOwed = _calculateDecayedTokens(user);
        uint256 prevBalance = _balances[user];
        balance = tokensOwed < prevBalance ? prevBalance - tokensOwed : 0;
    }

    /**
     * @notice externalUpdate is just here in case someone wants to update without a transfer.
     * @param _user User whose balance to update. Not a problem if it's arbitrary.
     *
     */
    function externalUpdate(address _user) external {
        _updateGlobalBalance();
        _updateUserBalance(_user);
    }

    /* ********************************************* INTERNAL ********************************************* */

    /**
     * @notice Update the global cumulatives for the new block.
     *
     */
    function _updateGlobalBalance() internal {
        // Time since last update.
        uint256 timeElapsed = block.timestamp - _lastGlobalUpdate;

        uint256 globalPercentOwed = decayPercentPerSecond * timeElapsed;
        uint256 globalTokensOwed = decayingTokens * globalPercentOwed / _DIVISOR;
        // If we owe more than there are, cap it.
        globalTokensOwed = globalTokensOwed > decayingTokens ? decayingTokens : globalTokensOwed;

        _cumulativeTokensPaid += globalTokensOwed;
        _cumulativeDecaying += decayingTokens * (block.timestamp - _lastGlobalUpdate);
        _lastGlobalUpdate = block.timestamp;

        // Add balance to beneficiary.
        /**
         * @dev We could avoid paying gas for this and simply calculate beneficiary balance where needed,
         * but that adds a lot of code elsewhere that I don't want to worry about.
         * For the first version of these tokens we're prioritizing safety over efficiency.
         *
         */
        _balances[beneficiary] += globalTokensOwed;
    }

    /**
     * @notice Update the user balance based on new cumulatives. Must come after a global update.
     * @param _user The address that we're updating balance of.
     *
     */
    function _updateUserBalance(address _user) internal returns (uint256 newBalance) {
        newBalance = balanceOf(_user);
        _balances[_user] = newBalance;
        _lastUserDecaying[_user] = _cumulativeDecaying;
        _lastUserTokensPaid[_user] = _cumulativeTokensPaid;
        _lastUserUpdate[_user] = block.timestamp;
    }

    /**
     * @notice Calculate the decayed tokens of a user to update their balance/
     * @param _user The address that we're calculating recent decay for.
     *
     */
    function _calculateDecayedTokens(address _user) internal view returns (uint256 tokensOwed) {
        uint256 timeElapsed = block.timestamp - _lastUserUpdate[_user];
        if (timeElapsed != 0) {
            uint256 avgUnproductive = _cumulativeDecaying - _lastUserDecaying[_user] / timeElapsed;
            uint256 avgTokensPaid = _cumulativeTokensPaid - _lastUserTokensPaid[_user] / timeElapsed;

            // These 2 averages give us the average percent paid and can charge our balance based on that.
            if (avgUnproductive != 0) {
                tokensOwed = _balances[_user] * avgTokensPaid / avgUnproductive;
            }
        }
    }

    // OpenZeppelin ERC20 _update with only change being _updateRewards calls.
    /**
     * @notice ERC20 update override for all transfers.
     * @dev Demurrage special additions here include:
     *      1. Updating global variables initially.
     *      2. Updating individual balances (except if the balance is a safe haven or the beneficiary).
     *      3. Accounting for decay between tx send and execution by lowering value to user balance (after checking user had that balance stored).
     *      4. Adding/subtracting from unproductive token global variable to keep it up to date.
     * @param from The address sending tokens.
     * @param to The address receiving tokens.
     * @param value The value attempting to be set. Will revert if it's over stored _balance of user, but not if it's over updated balance.
     *
     */
    function _update(address from, address to, uint256 value) internal override {
        // Demurrage: Update global balance variables.
        _updateGlobalBalance();

        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }

            /**
             * @dev Hear me out.
             *
             * If we update before value is initially checked, sending max tokens will usually fail.
             * The solution would be to make value the full balance if we're sending over balance, and that's all fine and dandy.
             * The obvious problem here is developers need to be extremely cautious to check token amount transferred rather
             * than only checking for a successful transferFrom or someone with no tokens could "transfer" billions.
             *
             * While we can't entirely solve this problem, by updating after an initial balance check, and only then allowing
             * value over the user's balance to be lowered to the user's balance, we can at least confirm the user had those tokens.
             * It still isn't ideal, but is better and a scenario that already needs to be accounted for with fee-on-transfer tokens.
             *
             */
            bool fromSafeHaven = safeHavens[from] || from == beneficiary;
            if (!fromSafeHaven) fromBalance = _updateUserBalance(from);
            if (value > fromBalance) value = fromBalance;

            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }

            if (fromSafeHaven) decayingTokens += value;
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            // Demurrage Token: Update balance after demurrage.
            bool toSafeHaven = safeHavens[to] || to == beneficiary;
            if (!toSafeHaven) _balances[to] = _updateUserBalance(to);

            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }

            if (toSafeHaven) {
                if (decayingTokens < value) {
                    decayingTokens = 0;
                } else {
                    decayingTokens -= value;
                }
            }
        }

        emit Transfer(from, to, value);
    }

    /* ********************************************* PRIVILEGED ********************************************* */

    /**
     * @notice Add or remove safe havens (addresses that will not have their tokens decayed).
     *      These addresses are where you want tokens to be: LPs, lending protocols, etc.
     * @dev Beneficiary will be automatically added and all others need to be added manually.
     * @param _safeHaven The address to adjust whether or not their tokens decat.
     * @param _toAdd Whether to add (true) or remove (false) the address from being a safe haven.
     *
     */
    function changeSafeHaven(address _safeHaven, bool _toAdd) external onlyOwner {
        // First update in case it held tokens before this.
        _updateGlobalBalance();
        _updateUserBalance(_safeHaven);
        safeHavens[_safeHaven] = _toAdd;
    }

    /**
     * @notice Beneficiary or owner may change the address that receives decaying tokens.
     * @param _newBeneficiary The new address to receive decaying tokens.
     *
     */
    function transferBeneficiary(address _newBeneficiary) external {
        if (msg.sender != beneficiary && msg.sender != owner()) {
            revert OnlyBeneficiaryOrOwner();
        }

        _updateGlobalBalance();
        _updateUserBalance(beneficiary);
        _updateUserBalance(_newBeneficiary);

        safeHavens[beneficiary] = false;
        safeHavens[_newBeneficiary] = true;

        beneficiary = _newBeneficiary;
    }
}
