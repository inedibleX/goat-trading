// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {GoatV1Factory} from "../../../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../../../contracts/periphery/GoatRouterV1.sol";
import {MockWETH} from "../../../contracts/mock/MockWETH.sol";
import {MockERC20} from "../../../contracts/mock/MockERC20.sol";

import {TaxToken} from "../../../contracts/tokens/TaxToken.sol";
import {TaxShareToken} from "../../../contracts/tokens/TaxShareToken.sol";
import {TaxBurnToken} from "../../../contracts/tokens/TaxBurnToken.sol";
import {DemurrageToken} from "../../../contracts/tokens/DemurrageToken.sol";
import {DividendToken} from "../../../contracts/tokens/DividendToken.sol";
import {VaultToken} from "../../../contracts/tokens/VaultToken.sol";
import {LotteryToken} from "../../../contracts/tokens/LotteryToken.sol";
import {TokenFactory} from "../../../contracts/tokens/TokenFactory.sol";
import {LotteryTokenMaster} from "../../../contracts/tokens/LotteryTokenMaster.sol";

struct Users {
    address whale;
    address alice;
    address bob;
    address treasury;
}

// General tax token tests that will be run on every token
// 1. All normal token things such as transfers working
// 2. Adjustment of all variables works correctly
// 3. Transfers with taxes work correctly, remove the right amount, give the right amount
// 4. Buys and sells are correct
// 5. Selling taxes works and at the right time
// 6. Ownership things are correct

// Taxshare tokens:
// 1. When taxes occur half go to this and half to rewards
// 2. Rewards are added to balances correctly
// 3. Works correctly with Ether rewards
// 4. Earned and balance work correctly
// 5. Privileged

// Taxburn tokens:
// 1. Tokens are burned on tax
// 2. Privileged

// Dividend tokens:
// 1. Constructed correctly
// 2. Correct updates are made on all transfers (make sure balances don't get messed up)
// 3. Adding dividends works
// 4. Earned for dividend is correct
// 5. get reward works and updates correctly
// 6. Privileged
// 7. blacklist

// Lottery tokens:
// 1. Master creates correctly
// 2. Privileged
// 3. Wins are calculated correctly
// 4. Entries are checked correctly on every token transfer
// 5. Upkeep overall
// 6. awardTaxes goes to the right place
// 7. pot is paid out correctly

// Vault token:
// 1. Taxes are added to the correct place
// 2. Token receives ether from sells
// 3. Ether rewards are calculated correctly and redeemed correctly

// Demurrage:
// 1. Tokens decay at the correct rate
// 2. Balance returns correctly
// 3. safeHavens don't decay
// 4. Updates occur correctly
// 5. Privileged

// windUp() slowly starts us special functionality, such as if a demurrage token is being switched to
// windDown() slowly winds down a token, such as if a lottery pot needs to be won
// Need to somehow make sure extra balances are saved. Probably need a function on every contract
// to call to other function on other contracts like getReward()
// maybe things like vault eth and lottery will wind down by buying tokens on the market and distributing?
// Probably want to decide on a final "clean" state that all tokens should get to
// Ya, don't have people calling old functions but rather have a constant taxshare system where we can clean slate
// with dividends, lottery, vaults

contract TokenBackupTest is Test {
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint32 private constant _MAX_UINT32 = type(uint32).max;
    TokenFactory tokenFactory;
    GoatV1Factory factory;
    GoatV1Router router;
    MockERC20 goat;
    MockWETH weth;
    Users users;

    TaxToken plainTax;
    DemurrageToken demurrage;
    DividendToken dividend;
    LotteryTokenMaster lotteryMaster;
    LotteryToken lottery;
    VaultToken vault;
    TaxShareToken taxshare;
    TaxBurnToken taxburn;

    function setUp() public {
        users = Users({
            whale: makeAddr("whale"),
            alice: makeAddr("alice"),
            bob: makeAddr("bob"),
            treasury: makeAddr("treasury")
        });
        vm.warp(300 days);

        weth = new MockWETH();

        // Launch factory
        // Testing factory probably works well enough just through tests of the token as long as pool is tested
        // Tests for each token type start with
        factory = new GoatV1Factory(address(weth));
        tokenFactory = new TokenFactory(address(factory), address(weth));
    }

    // function setUp() public {
    //     _launchTokens();

    //     vm.startPrank(users.whale);

    //     vm.stopPrank();
    //     vm.startPrank(users.treasury);
    //     vm.stopPrank();
    // }

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
