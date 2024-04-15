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
import {TokenFactory2} from "../../../contracts/tokens/TokenFactory2.sol";
import {TokenFactory3} from "../../../contracts/tokens/TokenFactory3.sol";
import {LotteryTokenMaster} from "../../../contracts/tokens/LotteryTokenMaster.sol";

struct Users {
    address whale;
    address alice;
    address bob;
    address treasury;
    address owner;
    address dex;
}

contract BaseTokenTest is Test {
    enum RevertType {
        None,
        NonZeroInitialEth,
        InitialBurnPercent
    }

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint32 private constant _MAX_UINT32 = type(uint32).max;
    address pair;

    TokenFactory tokenFactory;
    TokenFactory2 tokenFactory2;
    TokenFactory3 tokenFactory3;
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
            treasury: makeAddr("treasury"),
            owner: makeAddr("owner"),
            dex: makeAddr("dex")
        });
        vm.warp(300 days);

        vm.startPrank(users.whale);
        vm.deal(users.whale, 1000 ether);
        weth = new MockWETH();
        weth.deposit{value: 1000 ether}();
        vm.stopPrank();

        // Launch factory
        // Testing factory probably works well enough just through tests of the token as long as pool is tested
        // Tests for each token type start with
        factory = new GoatV1Factory(address(weth));
        tokenFactory = new TokenFactory(address(factory), address(weth));
        tokenFactory2 = new TokenFactory2(address(factory), address(weth));
        tokenFactory3 = new TokenFactory3(address(factory), address(weth));
        router = new GoatV1Router(address(factory), address(weth));
    }
}
