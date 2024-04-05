// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest} from "./BaseTokenTest.t.sol";

// Taxshare tokens:
// 1. When taxes occur half go to this and half to rewards
// 2. Rewards are added to balances correctly
// 3. Works correctly with Ether rewards
// 4. Earned and balance work correctly
// 5. Privileged

contract TaxShareTokenTest is BaseTokenTest {
    // Test all functionality of TaxShare tokens
    function testTaxShare() public {
        // Includes normal tax tests and that rewards are updated correctly
        _testTaxShareUpdates();
        // Tests functionality that has to do with sharing taxes.
        _testTaxShareFunctionality();
        _testTaxSharePrivileged();
    }

    function _testTaxShareUpdates() private {
        // 1. Make sure part of taxes went to treasury
        // 2. Make sure part of taxes went to sharing
    }

    function _testTaxShareFunctionality() private {
        // 1. Send a tx to take taxes
        // 2. Make sure balance of an unrelated address is updated correctly
        // 3. Make sure on transfers between addresses balance updates correctly
        // 4. Check all variables ^
    }

    function _testTaxSharePrivileged() private {
        // 1. Test that treasury or owner can change % to be shared
    }
}
