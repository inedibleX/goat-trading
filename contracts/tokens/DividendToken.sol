// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {TaxToken} from "./TaxToken.sol";
import {TokenErrors} from "./library/TokenErrors.sol";
/**
 * @title Dividend Token
 * @author Robert M.C. Forster
 * @notice This is a type of token that can be used to distribute Ether to users proportional to their held tokens.
 *         Also includes the ability for the owner to take taxes if desired.
 *
 */

contract DividendToken is TaxToken, ReentrancyGuard {
    // The address that's allowed to give rewards.
    address public rewarder;

    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => bool) public revoked;

    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event Recovered(uint256 amount);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, address _weth)
        TaxToken(_name, _symbol, _initialSupply, _weth)
    {}

    // Not on tax token by default because Ether is only sent to treasury there.
    receive() external payable {}

    /* ********************************************* PUBLIC ********************************************* */

    /**
     * @notice Withdraw the Ether rewards for any address.
     * @param _account The account to withdraw rewards for.
     *
     */
    function getReward(address _account) public nonReentrant {
        _updateRewards(_account);
        uint256 reward = rewards[_account];
        if (reward > 0) {
            rewards[_account] = 0;
            payable(_account).transfer(reward);
            emit RewardPaid(_account, reward);
        }
    }

    /* ********************************************* VIEW ********************************************* */

    /**
     * @notice Find the amount of Ether that has been earned (and not withdrawn) by an address.
     * @param account The address to find the amount owed of.
     *
     */
    function earned(address account) public view returns (uint256) {
        return _balances[account] * (_rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    /* ********************************************* INTERNAL ********************************************* */

    // OpenZeppelin ERC20 _update with only change being _updateRewards calls.
    function _update(address from, address to, uint256 value) internal override {
        // Dividend: Add rewards to both user token balance.
        _updateRewards(from);
        _updateRewards(to);

        super._update(from, to, value);
    }

    /**
     * @notice Update the rewards of an address.
     * @dev Does not update address 0 or revoked addresses. Only global updates for those.
     * @param account The account to update the rewards of. address(0) if only global updates are needed.
     *
     */
    function _updateRewards(address account) internal {
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = _lastTimeRewardApplicable();
        if (account != address(0) && !revoked[account]) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /**
     * @notice Find the cumulative rewards for 1 full token. Used to set rewardPerTokenStored.
     *
     */
    function _rewardPerToken() internal view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((_lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    /**
     * @notice Find the last time a reward was given. Either right now, or when the last drip ended.
     *
     */
    function _lastTimeRewardApplicable() internal view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /* ********************************************* ONLY TEAM ********************************************* */

    /**
     * @notice Drip Ether to users over time.
     * @param _dripTimeInSeconds This will average with any currently running drip of the token. This averaging
     *        could end up with weird scenarios where you drastically slow or increase a drip, so this function
     *        is restricted to the team.
     *
     */
    function addDividend(uint256 _dripTimeInSeconds) external payable {
        if (msg.sender != rewarder) {
            revert TokenErrors.OnlyTeam();
        }

        uint256 reward = msg.value;
        rewardPerTokenStored = _rewardPerToken();
        // small precision loss in reward rate is accepted as it is not scaled.
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / _dripTimeInSeconds;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / _dripTimeInSeconds;
        }

        // Full Ether balance.
        uint256 balance = address(this).balance;
        if (balance / _dripTimeInSeconds < rewardRate) {
            revert TokenErrors.ProvidedRewardsTooHigh();
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + _dripTimeInSeconds;
        emit RewardAdded(reward);
    }

    /**
     * @notice Transfer rewarder permissions to a new address.
     * @param _newRewarder Address to give rewarder permissions to.
     *
     */
    function transferRewarder(address _newRewarder) external {
        if (msg.sender != owner() && msg.sender != rewarder) revert TokenErrors.OnlyBeneficiaryOrRewarder();
        rewarder = _newRewarder;
    }

    /**
     * @notice Withdraw Eth to owner. Should primarily be used to withdraw allocations that would otherwise go to revoked addresses.
     * @param _amount Amount of Ether (in Wei) to withdraw.
     * @param _to The address to withdraw Ether to.
     *
     */
    function withdraw(uint256 _amount, address payable _to) external onlyOwnerOrTreasury {
        _to.transfer(_amount);
        emit Recovered(_amount);
    }

    /**
     * @notice Revoke an address, such as a dex, from receiving rewards. A little bit weird cause
     *         these rewards will just be sitting in the contract after that, but they can be withdrawn
     *         by the owners.
     * @param _user Address to revoke.
     * @param _revoked True if you want to revoke the user, false to grant the user.
     *
     */
    function revokeRewardsEligibility(address _user, bool _revoked) external onlyOwnerOrTreasury {
        revoked[_user] = _revoked;
    }
}
