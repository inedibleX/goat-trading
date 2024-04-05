// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest} from "./BaseTokenTest.t.sol";

// Taxburn tokens:
// 1. Tokens are burned on tax
// 2. Privileged

contract TaxBurnTokenTest is BaseTokenTest {
    function testTaxBurn() public {
        // Make sure part of transfers are burned as well, counts as tax burn functionality.
        _testTaxBurnUpdates();
        _testTaxBurnPrivileged();
    }

    function _testTaxBurnUpdates() private {
        // 1. Make sure correct part of taxes were burned
    }

    function _testTaxBurnPrivileged() private {
        // 1. Test that only owner can change burn percent
    }
}
