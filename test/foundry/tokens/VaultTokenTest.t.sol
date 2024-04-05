// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {BaseTokenTest} from "./BaseTokenTest.t.sol";

// Vault token:
// 1. Taxes are added to the correct place
// 2. Token receives ether from sells
// 3. Ether rewards are calculated correctly and redeemed correctly

contract VaultTokenTest is BaseTokenTest {
    // Vault doesn't include any changes to update so we don't need to test.
    function testVault() public {
        // Special functionality on vaults when selling, some Ether goes into the vault.
        _testVaultSelling();
        // Test redeeming functionality.
        _testVaultFunctionality();
        _testVaultPrivileged();
    }

    function _testVaultSelling() private {
        // 1. Make sure on a sell half of Ether goes to treasury and half of Ether is put into the vault
    }

    function _testVaultFunctionality() private {
        // 1. Make sure deposit works
        // 2. Make sure redeem works
        // 3. Make sure view functions work
    }

    function _testVaultPrivileged() private {
        // 1. Make sure owner or treasury can change vault percent
    }
}
