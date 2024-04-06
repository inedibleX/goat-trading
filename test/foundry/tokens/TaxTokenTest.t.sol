// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest, TaxToken} from "./BaseTokenTest.t.sol";

import {TokenType} from "../../../contracts/tokens/TokenFactory.sol";

import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract TaxTokenTest is BaseTokenTest {
    // Test all functionality of plain tax tokens
    function launch() public {
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;

        (address token, address pool) =
            tokenFactory.createToken("TaxToken", "TT1", 1e21, 100, 100, users.owner, TokenType.TAX, 1000, initParams);

        plainTax = TaxToken(token);
        pair = pool;
    }

    function testPlainTax() public {
        launch();
        // Tests that tokens transfer correctly with and without taxes.
        _testTaxTransfers();
        // Test that taxes are added to the treasury correctly.
        _testPlainTaxUpdates();
        // Tests that tokens are sold or not sold correctly in the pool.
        _testPlainTaxSelling();
        // Tests all privileged functions of the token.
        _testPlainTaxPrivileged();
    }

    // This tests only that balances are applied and removed correctly from addresses.
    // The actual updating for taxes to be given to a certain address is tested below
    function _testTaxTransfers() private {
        // 1. Transfer from one user to the next with no taxes
        // 2. Check that the above does not have taxes removed
        // 3. Transfer from one user to the next with buy taxes
        // 4. Check that update is done correctly on from/to
        // 5. Transfer from one user to the next with sell taxes
        // (one of the users above is taxed on buys, one on sells)
        // 6. Check that update is done correctly
    }

    function _testPlainTaxUpdates() private {
        // 1. Make sure that treasury got all of the deducted transfers
    }

    function _testPlainTaxSelling() private {
        // 1. Make sure selling works correctly before pool is in the right mode
        // 2. Update pool so selling should work
        // 3. Make sure selling works correctly once tokens can be sold
    }

    function _testPlainTaxPrivileged() private {
        // 1. Test that only owner can set taxes
        // 2. Test that owner or treasury can set treasury address
    }
}
