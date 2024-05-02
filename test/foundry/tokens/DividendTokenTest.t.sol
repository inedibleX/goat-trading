// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest, DividendToken} from "./BaseTokenTest.t.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatLibrary} from "../../../contracts/library/GoatLibrary.sol";
import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";
import {TokenErrors} from "./../../../contracts/tokens/library/TokenErrors.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract DividendTokenTest is BaseTokenTest {
    uint256 private totalSupply = 1e21;
    uint256 private bootstrapTokenAmount;
    string private constant tokenName = "Dividend Token";
    string private constant tokenSymbol = "DVT";

    function createTokenAndAddLiquidity(GoatTypes.InitParams memory initParams, RevertType revertType) public {
        bootstrapTokenAmount = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (revertType == RevertType.NonZeroInitialEth) {
            vm.expectRevert(TokenErrors.InitialEthNotAccepted.selector);
        }
        (address token, address pool) = tokenFactory3.createToken(
            tokenName, tokenSymbol, totalSupply, 100, 100, users.owner, TokenType.DIVIDEND, 5000, initParams
        );
        dividend = DividendToken(payable(token));
        pair = pool;
    }

    function testDividendInitialize() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        assertEq(dividend.owner(), users.owner);
        assertEq(dividend.balanceOf(users.owner), totalSupply - bootstrapTokenAmount);
        assertEq(dividend.balanceOf(pair), bootstrapTokenAmount);

        assertEq(dividend.totalSupply(), totalSupply);
        assertEq(dividend.name(), tokenName);
        assertEq(dividend.symbol(), tokenSymbol);
        assertEq(dividend.rewarder(), address(0));
        assertEq(dividend.blacklisted(pair), true);
    }

    function testDividendChangeRewarder() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.expectRevert(TokenErrors.OnlyBeneficiaryOrRewarder.selector);
        dividend.transferRewarder(users.alice);

        assertEq(dividend.rewarder(), address(0));
        vm.startPrank(users.owner);
        dividend.transferRewarder(users.bob);
        vm.stopPrank();

        assertEq(dividend.rewarder(), users.bob);
    }

    function testAddDividend() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.expectRevert(TokenErrors.OnlyTeam.selector);
        dividend.addDividend(1000);
        vm.startPrank(users.owner);
        dividend.transferRewarder(users.rewarder);
        vm.stopPrank();
        uint256 reward = 100 ether;
        uint256 dripInSeconds = 3600;

        vm.startPrank(users.rewarder);
        vm.deal(users.rewarder, 1000 ether);
        dividend.addDividend{value: reward}(dripInSeconds);
        vm.stopPrank();

        assertEq(dividend.rewardRate(), reward / dripInSeconds, "reward rate is not correct");
        assertEq(dividend.lastUpdateTime(), block.timestamp, "last update time should be block.timestamp");
        assertEq(dividend.rewardPerTokenStored(), 0, "Expected reward per token stored to be 0");
        assertEq(dividend.periodFinish(), block.timestamp + dripInSeconds, "period finish is not correct");

        vm.warp(block.timestamp + dripInSeconds / 2);

        vm.startPrank(users.rewarder);
        vm.deal(users.rewarder, 1000 ether);
        dividend.addDividend{value: reward}(dripInSeconds);
        vm.stopPrank();
        uint256 newRate = (reward / dripInSeconds) + ((reward / dripInSeconds) / 2);

        assertApproxEqAbs(dividend.rewardRate(), newRate, 1);
        assertEq(dividend.lastUpdateTime(), block.timestamp);
        assertGt(dividend.rewardPerTokenStored(), 1e10);
        assertEq(dividend.periodFinish(), block.timestamp + dripInSeconds);
    }

    function testBlackListAddress() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        dividend.blacklistAddress(users.alice, true);

        assertEq(dividend.blacklisted(users.alice), false);
        vm.startPrank(users.owner);
        dividend.blacklistAddress(users.alice, true);
        vm.stopPrank();

        assertEq(dividend.blacklisted(users.alice), true);
        vm.startPrank(users.owner);
        dividend.blacklistAddress(users.alice, false);
        vm.stopPrank();
        assertEq(dividend.blacklisted(users.alice), false);
    }

    function testWithdrawEthByOwnerOrTreasury() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.deal(users.bob, 1 ether);
        vm.startPrank(users.bob);
        payable(address(dividend)).transfer(1e18);
        vm.stopPrank();

        vm.expectRevert(TokenErrors.OnlyOwnerOrTreasury.selector);
        dividend.withdraw(1e18, payable(users.bob));
        uint256 bobEthBalBefore = users.bob.balance;
        vm.startPrank(users.owner);
        dividend.withdraw(1e18, payable(users.bob));
        vm.stopPrank();
        uint256 bobEthBalAfter = users.bob.balance;

        assertEq(bobEthBalAfter - bobEthBalBefore, 1e18);
    }

    function testUpdateOnTokenTransfer() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.expectRevert(TokenErrors.OnlyTeam.selector);
        dividend.addDividend(1000);
        vm.startPrank(users.owner);
        dividend.transferRewarder(users.rewarder);
        vm.stopPrank();
        uint256 reward = 100 ether;
        uint256 dripInSeconds = 3600;
        vm.startPrank(users.rewarder);
        vm.deal(users.rewarder, 1000 ether);
        dividend.addDividend{value: reward}(dripInSeconds);
        vm.stopPrank();
        uint256 rewardPerTokenStored = dividend.rewardPerTokenStored();
        assertEq(rewardPerTokenStored, 0);
        vm.warp(block.timestamp + (dripInSeconds / 2));
        uint256 ownerEthBalBefore = users.owner.balance;
        vm.startPrank(users.owner);
        dividend.getReward(users.owner);
        vm.stopPrank();
        rewardPerTokenStored = dividend.rewardPerTokenStored();
        uint256 stored = dividend.rewardRate() * (dripInSeconds / 2) * 1e18 / totalSupply;
        assertEq(rewardPerTokenStored, stored);

        uint256 newRewardPerTokenStored = dividend.rewardPerTokenStored();

        uint256 ownerEthBalAfter = users.owner.balance;
        uint256 rewardsToDistribute = newRewardPerTokenStored * dividend.totalSupply();
        uint256 ownerShare = (rewardsToDistribute / 4) / 1e18;

        assertEq(ownerEthBalAfter - ownerEthBalBefore, ownerShare);

        vm.warp(block.timestamp + dripInSeconds);

        vm.startPrank(users.owner);
        dividend.getReward(users.owner);
        vm.stopPrank();
        ownerEthBalAfter = users.owner.balance;

        newRewardPerTokenStored = dividend.rewardPerTokenStored();
        rewardsToDistribute = newRewardPerTokenStored * dividend.totalSupply();
        ownerShare = (rewardsToDistribute / 4) / 1e18;
        assertEq(ownerEthBalAfter - ownerEthBalBefore, ownerShare);
    }

    function testEarnedDividend() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        dividend.transferRewarder(users.rewarder);
        vm.stopPrank();

        uint256 reward = 100 ether;
        uint256 dripInSeconds = 3600;

        vm.startPrank(users.rewarder);
        vm.deal(users.rewarder, 1000 ether);
        dividend.addDividend{value: reward}(dripInSeconds);
        vm.stopPrank();

        vm.warp(block.timestamp + (dripInSeconds / 2));

        uint256 userEarned = dividend.earned(users.owner);
        // actually it should be 12.5 ether, but due to precision loss
        // in reward rate it is 12.49999999999999500
        assertEq(userEarned, 12499999999999999500);
    }

    function testUpdateRewardsOnTokenTransfer() public {
        GoatTypes.InitParams memory initParams;
        initParams.initialEth = 0;
        initParams.bootstrapEth = 10e18;
        initParams.virtualEth = 10e18;
        initParams.initialTokenMatch = 1000e18;

        createTokenAndAddLiquidity(initParams, RevertType.None);

        vm.startPrank(users.owner);
        dividend.transferRewarder(users.rewarder);
        vm.stopPrank();

        uint256 reward = 100 ether;
        uint256 dripInSeconds = 3600;

        vm.startPrank(users.rewarder);
        vm.deal(users.rewarder, 1000 ether);
        dividend.addDividend{value: reward}(dripInSeconds);
        vm.stopPrank();

        vm.warp(block.timestamp + (dripInSeconds / 2));
        uint256 rewardPerTokenStored = dividend.rewardPerTokenStored();
        uint256 rewardPerTokenPaidBob = dividend.userRewardPerTokenPaid(users.bob);
        uint256 rewardPerTokenPaidOwner = dividend.userRewardPerTokenPaid(users.owner);

        assertEq(rewardPerTokenStored, 0);
        assertEq(rewardPerTokenPaidBob, 0);
        assertEq(rewardPerTokenPaidOwner, 0);

        vm.startPrank(users.owner);
        dividend.transfer(users.bob, 250e18);
        vm.stopPrank();

        uint256 stored = dividend.rewardRate() * (dripInSeconds / 2) * 1e18 / dividend.totalSupply();

        rewardPerTokenStored = dividend.rewardPerTokenStored();
        rewardPerTokenPaidBob = dividend.userRewardPerTokenPaid(users.bob);
        rewardPerTokenPaidOwner = dividend.userRewardPerTokenPaid(users.owner);

        assertEq(rewardPerTokenStored, stored);
        assertEq(rewardPerTokenPaidBob, stored);
        assertEq(rewardPerTokenPaidOwner, stored);
    }
}
