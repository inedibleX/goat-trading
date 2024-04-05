// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTokenTest} from "./BaseTokenTest.t.sol";

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

contract DividendTokenTest is BaseTokenTest {
    function _launchTokens() internal {
        // function createToken(
        //     string memory _name,
        //     string memory _symbol,
        //     uint256 _totalSupply,
        //     uint256 _buyTax,
        //     uint256 _sellTax,
        //     address _owner,
        //     uint256 _type,
        //     uint256 _percent,
        //     GoatTypes.InitParams memory initParams
        // ) external payable returns (address tokenAddress, address pool) {
    }

    // Test that each of the tokens that were setup were created successfully by the factory.
    function testTokenCreation() public {
        // Check name, symbol, total supply, who owns tokens, etc.
    }

    // Test that each of the pools that were setup were done so successfully by the factory
    function testPoolCreation() public {
        // Check that all values are correct here
    }

    /* *********************************************** Plain Tax *********************************************** */

    // Test all functionality of plain tax tokens
    function testPlainTax() public {
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

    /* *********************************************** Tax Share *********************************************** */

    // Test all functionality of TaxShare tokens
    function testTaxShare() public {
        _testTaxTransfers();
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

    /* *********************************************** Tax Burn *********************************************** */

    function testTaxBurn() public {
        _testTaxTransfers();
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

    /* *********************************************** Dividend *********************************************** */

    function testDividend() public {
        _testTaxTransfers();
        // Taxes on dividend are normal. We have this because we customized update so want to make sure we didn't mess up normal functionality.
        _testPlainTaxUpdates();
        // Test functionality specific to dividends.
        _testDividendFunctionality();
        // Includes rewarded
        _testDividendPrivileged();
    }

    function _testDividendFunctionality() private {
        // 1. Make sure dividends can be added
        // 2. Make sure variables update correctly when that happens
        // 3. Make sure dividends update correctly when a transfer occurs
        // 4. Make sure dividends can be withdrawn correctly
    }

    function _testDividendPrivileged() private {
        // 1. test rewarder functionality
    }

    /* *********************************************** Demurrage *********************************************** */

    // Transfers are the only specific functionality of demurrage so we don't need other tests.
    function testDemurrage() public {
        // Make sure token amounts are updated correctly when transferred (whether that's altered or unaltered).
        _testDemurrageTransfers();
        _testDemurragePrivileged();
    }

    function _testDemurrageTransfers() private {
        // 1. Test transfer from one to another normally and make sure updates are made correctly
        // 2. Test transfer above with safe havens and make sure the same
        // 2. Make sure transfer that is more than the balance completely fails
        // 3. Make sure transfer that is more than the balance only after decay succeeds but only gives balance amount
    }

    function _testDemurragePrivileged() private {
        // 1. Test owner and beneficiary can change what they should change
        // 2. Make sure all variables are change correctly when things are adjusted (such as decay implemented if something is becoming safe haven)
    }

    /* *********************************************** Vault *********************************************** */

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

    /* *********************************************** Lottery *********************************************** */

    function testLottery() public {
        // Normal tax tests.
        _testTaxTransfers();
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
