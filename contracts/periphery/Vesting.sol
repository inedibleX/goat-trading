// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token Vesting Contract
/// @notice This contract handles the vesting of tokens for multiple recipients.
/// @dev The contract ensures that tokens are vested over a specified period
///      and allows recipients to claim their tokens gradually.
///      The total vesting amount is directly sent to this contract.
contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    error LengthMismatch();
    error NothingToClaim();
    error PullDeadlineNotReached();

    /// @notice Event emitted when a user claims their vested tokens.
    /// @param user The address of the user claiming tokens.
    /// @param amount The amount of tokens claimed.
    /// @param timestamp The timestamp when the tokens were claimed.
    event Claimed(address indexed user, uint256 amount, uint256 timestamp);

    /// @notice Event emitted when the owner pulls vested token after a deadline.
    /// @param user The address of the user whose vested amounts are pulled.
    /// @param amount The amount of tokens pulled.
    /// @param timestamp The timestamp when the tokens were pulled.
    event Pulled(address indexed user, uint256 amount, uint256 timestamp);

    /// @notice The token being vested.
    IERC20 public immutable token;
    /// @notice The start time of the vesting period.
    uint48 public immutable start;
    /// @notice The end time of the vesting period.
    uint48 public immutable end;
    /// @notice The timestamp from when unclaimed tokens can be pulled.
    uint160 public immutable claimDeadline;

    /// @notice Mapping of user addresses to the amount of tokens granted to them.
    mapping(address => uint256) public granted;
    /// @notice Mapping of user addresses to the amount of tokens claimed by them.
    mapping(address => uint256) public claimed;

    /**
     * @notice Constructor to initialize the vesting contract.
     * @param vestingToken The token to be vested.
     * @param recipients The list of addresses to receive the vested tokens.
     * @param grantedAmounts The list of amounts to be vested for each recipient.
     * @param vestingPeriod The vesting period in seconds.
     * @param claimWindow The time period for claim after which owner can pull vested tokens.
     */
    constructor(
        IERC20 vestingToken,
        address[] memory recipients,
        uint256[] memory grantedAmounts,
        uint256 vestingPeriod,
        uint256 claimWindow
    ) {
        if (recipients.length != grantedAmounts.length) revert LengthMismatch();
        token = vestingToken;

        for (uint256 i = 0; i < recipients.length; i++) {
            granted[recipients[i]] = grantedAmounts[i];
        }

        uint256 timestamp = block.timestamp;
        start = uint48(timestamp);
        end = uint48(timestamp + vestingPeriod);
        claimDeadline = uint160(timestamp + vestingPeriod + claimWindow);
    }

    /**
     * @notice Allows a user to claim their vested tokens.
     */
    function claim() external {
        address user = _msgSender();
        uint256 claimableAmount = claimable(user);

        if (claimableAmount == 0) revert NothingToClaim();

        claimed[user] += claimableAmount;
        token.safeTransfer(user, claimableAmount);
        emit Claimed(user, claimableAmount, block.timestamp);
    }

    /**
     * @notice Calculates the amount of tokens a user can claim.
     * @param user The address of the user.
     * @return actualClaimableAmount The amount of tokens that can be claimed by the user.
     */
    function claimable(address user) public view returns (uint256 actualClaimableAmount) {
        uint256 currentTime = block.timestamp;
        uint256 timePassed = currentTime > end ? end - start : currentTime - start;
        uint256 claimableAmount = (granted[user] * timePassed) / (end - start);
        actualClaimableAmount = claimableAmount - claimed[user];
    }

    /**
     * @notice Allows the owner to pull unclaimed tokens after the pull start time has passed.
     * @param user The address of the user whose unclaimed tokens are being pulled.
     */
    function pullTokens(address user) external onlyOwner {
        if (block.timestamp < claimDeadline) revert PullDeadlineNotReached();
        uint256 pullAmount = claimable(user);
        if (pullAmount == 0) revert NothingToClaim();
        // update granted to be whatever user has claimed upto now
        // that way they cannot claim anything in the future
        granted[user] = claimed[user];
        token.safeTransfer(owner(), pullAmount);
        emit Pulled(user, pullAmount, block.timestamp);
    }
}
