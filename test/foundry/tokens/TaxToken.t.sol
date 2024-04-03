// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../../contracts/exchange/GoatV1Pair.sol";
import "../../../contracts/exchange/GoatV1Factory.sol";
import "../../../contracts/mock/MockWETH.sol";
import "../../../contracts/mock/MockERC20.sol";
import "../../../contracts/library/GoatTypes.sol";
import "../../../contracts/library/GoatLibrary.sol";
import "../../../contracts/library/GoatErrors.sol";

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


contract GoatExchangeTest is Test {
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
    Lottery lottery;
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
        tokenFactory = new TokenFactory(router, factory);

    }

    function setUp() public {


        vm.startPrank(users.whale);

        vm.stopPrank();
        vm.startPrank(users.treasury);
        vm.stopPrank();
    }

    function _launchPlainTax(IERC20 token, address to, uint256 amount) public {
        // Create plain token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);
        // Check token data
        // Check pool
        // Check that tokens belong to sender
        // Check that ownership belongs to sender

        // Create tax token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);

        // Create TaxShare token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);

        // Create TaxBurn token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);

        // Create Demurrage token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);

        // Create token
        tokenFactory.createToken("Robert", "ROB", 10000000000, 500, 500, bob.address, 1, 0);
    }

    function _mintInitialLiquidity(GoatTypes.InitParams memory initParams, address to)
        private
        returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm)
    {
        (tokenAmtForPresale, tokenAmtForAmm) = GoatLibrary.getTokenAmountsForPresaleAndAmm(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );
        uint256 bootstrapTokenAmt = tokenAmtForPresale + tokenAmtForAmm;
        _fundMe(IERC20(address(goat)), to, bootstrapTokenAmt);
        vm.startPrank(to);
        address pairAddress = factory.createPair(address(goat), initParams);
        if (bootstrapTokenAmt != 0) {
            goat.transfer(pairAddress, bootstrapTokenAmt);
        }
        if (initParams.initialEth != 0) {
            vm.deal(to, initParams.initialEth);
            weth.deposit{value: initParams.initialEth}();
            weth.transfer(pairAddress, initParams.initialEth);
        }
        pair = GoatV1Pair(pairAddress);
        pair.mint(to);

        vm.stopPrank();
    }

}
