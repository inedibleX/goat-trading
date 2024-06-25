// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Vesting} from "./../../../contracts/periphery/Vesting.sol";
import {MockERC20} from "./../../../contracts/mock/MockERC20.sol";
import {VestingLibrary} from "./../../../contracts/library/VestingLibrary.sol";

contract VestingTest is Test {
    Vesting vesting;
    MockERC20 token;
    address owner = address(0x1);
    uint256 totalVestingAmount = 88888888 ether;
    uint256 vestingPeriod = 30 days;
    uint256 claimWindow = 365 days;
    VestingLibrary.UserData userData;

    address recipient1;
    address recipient2;
    uint256 recipient1Amount;
    uint256 recipient2Amount;

    function setUp() public {
        userData = VestingLibrary.getUserData();
        token = new MockERC20();
        token.mint(owner, totalVestingAmount);

        vm.startPrank(owner);
        vesting = new Vesting(token, userData.recipients, userData.grantedAmounts, vestingPeriod, claimWindow);
        token.transfer(address(vesting), totalVestingAmount);
        vm.stopPrank();
        recipient1 = userData.recipients[0];
        recipient2 = userData.recipients[1];
        recipient1Amount = userData.grantedAmounts[0];
        recipient2Amount = userData.grantedAmounts[1];
    }

    function testDeployment() public {
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.start(), block.timestamp);
        assertEq(vesting.end(), block.timestamp + vestingPeriod);
        assertEq(vesting.claimDeadline(), block.timestamp + vestingPeriod + claimWindow);
        assertEq(vesting.granted(recipient1), recipient1Amount);
        assertEq(vesting.granted(recipient2), recipient2Amount);
    }

    function testUserData() public {
        uint256 totalGranted;
        uint256 length = userData.grantedAmounts.length;
        for (uint256 i = 0; i < length; i++) {
            totalGranted += userData.grantedAmounts[i];
        }
        assertGe(totalVestingAmount, totalGranted);
    }

    function testClaimBeforeVestingPeriodEnds() public {
        vm.warp(block.timestamp + (vestingPeriod / 2));

        vm.startPrank(recipient1);
        vesting.claim();
        vm.stopPrank();

        uint256 expectedClaimable = (recipient1Amount * (vestingPeriod / 2)) / vestingPeriod;
        assertEq(token.balanceOf(recipient1), expectedClaimable);
    }

    function testClaimAfterVestingPeriodEnds() public {
        vm.warp(block.timestamp + vestingPeriod);

        vm.startPrank(recipient1);
        vesting.claim();
        vm.stopPrank();

        assertEq(token.balanceOf(recipient1), recipient1Amount);
    }

    function testAllClaimsAfterVestingEnds() public {
        uint256 length = userData.recipients.length;
        vm.warp(block.timestamp + vestingPeriod);

        for (uint256 i = 0; i < length; i++) {
            address recipient = userData.recipients[i];
            uint256 amount = userData.grantedAmounts[i];
            vm.startPrank(recipient);
            vesting.claim();
            vm.stopPrank();
            assertEq(token.balanceOf(recipient), amount);
        }
    }

    function testPullTokensAfterClaimWindow() public {
        vm.warp(block.timestamp + vestingPeriod + claimWindow + 1);

        vm.expectRevert();
        vesting.pullTokens(recipient1);

        vm.startPrank(owner);
        vesting.pullTokens(recipient1);
        vm.stopPrank();

        uint256 remainingTokens = token.balanceOf(owner);
        assertEq(remainingTokens, recipient1Amount);
    }

    function testClaimNothingToClaim() public {
        vm.warp(block.timestamp + (vestingPeriod / 2));

        vm.startPrank(recipient1);
        vesting.claim();
        vm.stopPrank();

        vm.expectRevert(Vesting.NothingToClaim.selector);
        vm.startPrank(recipient1);
        vesting.claim();
        vm.stopPrank();
    }

    function testPullBeforeClaimDeadline() public {
        vm.warp(block.timestamp + vestingPeriod);

        vm.expectRevert(Vesting.PullDeadlineNotReached.selector);
        vm.startPrank(owner);
        vesting.pullTokens(recipient1);
        vm.stopPrank();
    }
}
