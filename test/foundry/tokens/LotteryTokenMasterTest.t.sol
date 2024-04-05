// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./BaseTokenTest.t.sol";

contract LotteryTokenMasterTest is BaseTokenTest {
    function testCreateLotteryTokenSuccess() public {}
    function testCreateLotteryTokenRevertOnInvalidWinChance() public {}

    function testUpkeepSuccess() public {}

    function testAddEntryRevertOnUserWinChancesZero() public {}

    function testAddEntrySuccess() public {}
}
