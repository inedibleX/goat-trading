// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest} from "./BaseTokenTest.t.sol";

// Lottery tokens:
// 1. Master creates correctly
// 2. Privileged
// 3. Wins are calculated correctly
// 4. Entries are checked correctly on every token transfer
// 5. Upkeep overall
// 6. awardTaxes goes to the right place
// 7. pot is paid out correctly

contract LotteryTokenTest is BaseTokenTest {
    function testLottery() public {
        // Transfer should add money to pot and upkeep lottery contract
        _testLotteryUpdates();
        // Make sure entries are saved correctly on the lottery.
        _testLotteryEntries();
        // Make sure lottery win works correctly
        _testLotteryWin();
        _testLotteryPrivileged();
    }

    function _testLotteryUpdates() private {
        // 1. Check that on a tax update money is transferred to the pot
        // 2. Check that on any transfer the lottery master upkeep is called
    }

    function _testLotteryEntries() private {
        // 1. Check that on a purchase entries are added
    }

    function _testLotteryWin() private {
        // 1. Check that when a win happens, tokens are awarded to the user
        // 2. Check that on a win user is awarded the correct amount of tokens according to win multiplier
    }

    function _testLotteryPrivileged() private {
        // 1. Test changing pot percent
        // 2. Make sure only master can pay winner
    }
}
