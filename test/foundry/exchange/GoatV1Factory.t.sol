// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {BaseTest, GoatV1Factory} from "../BaseTest.t.sol";
import {GoatTypes} from "../../../contracts/library/GoatTypes.sol";
import {GoatV1Pair} from "../../../contracts/exchange/GoatV1Pair.sol";
import {GoatErrors} from "../../../contracts/library/GoatErrors.sol";

contract GoatV1FactoryTest is BaseTest {
    function testConstructorFactory() public {
        assertEq(factory.weth(), address(weth));
        assertEq(factory.treasury(), address(this));
    }

    function testCreatePairWithValidParams() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10e18, 10e18, 0, 1000e18);
        GoatV1Pair pair = GoatV1Pair(factory.createPair(address(token), initParams));
        assert(address(pair) != address(0));
        assertEq(pair.factory(), address(factory));

        address pool = factory.getPool(address(token));
        assertEq(pool, address(pair));
    }

    function testCreatePairRevertIfPairForTokenAlreadyExists() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10e18, 10e18, 0, 1000e18);
        GoatV1Pair pair = GoatV1Pair(factory.createPair(address(token), initParams));
        assert(address(pair) != address(0));

        vm.expectRevert(GoatErrors.PairExists.selector);
        factory.createPair(address(token), initParams);
    }

    function testCreatePairRevertIfTokenPassedIsBaseAsset() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10e18, 10e18, 0, 1000e18);
        vm.expectRevert(GoatErrors.CannnotPairWithBaseAsset.selector);
        factory.createPair(address(weth), initParams);
    }

    function testRevertRemovePairUnauthorized() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10e18, 10e18, 0, 1000e18);
        GoatV1Pair pair = GoatV1Pair(factory.createPair(address(token), initParams));
        assert(address(pair) != address(0));

        vm.expectRevert(GoatErrors.Forbidden.selector);
        factory.removePair(address(token));
    }

    function testRemovePairAndCreateNewSuccess() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(10e18, 10e18, 0, 1000e18);
        GoatV1Pair pair = GoatV1Pair(factory.createPair(address(token), initParams));
        assert(address(pair) != address(0));

        vm.startPrank(address(pair));
        factory.removePair(address(token));
        assertEq(factory.getPool(address(token)), address(0));
        vm.stopPrank();

        // Create a pair again
        pair = GoatV1Pair(factory.createPair(address(token), initParams));
        assert(address(pair) != address(0));
    }

    function testCreatePairWithInvalidParams() public {
        GoatTypes.InitParams memory initParams = GoatTypes.InitParams(0, 0, 0, 0);
        vm.expectRevert(GoatErrors.InvalidParams.selector);
        GoatV1Pair(factory.createPair(address(token), initParams));
    }

    function testSetTreasuryAndAccept() public {
        factory.setTreasury(lp_1);
        assertEq(factory.pendingTreasury(), lp_1);
        vm.prank(lp_1);
        factory.acceptTreasury();
        assertEq(factory.treasury(), lp_1);
    }

    function testSetTreasuryRevertIfNotCalledByTreasury() public {
        vm.prank(lp_1);
        vm.expectRevert(GoatErrors.Forbidden.selector);
        factory.setTreasury(lp_1);
    }

    function testAcceptTreasuryRevertIfNotCalledByPendingTreasury() public {
        factory.setTreasury(lp_1);
        vm.expectRevert(GoatErrors.Forbidden.selector);
        factory.acceptTreasury();
    }

    function testSetFeeToTreasury() public {
        factory.setFeeToTreasury(100e18);
        assertEq(factory.minimumCollectableFees(), 100e18);
    }

    function testSetFeeToTreasuryRevertIfNotCalledByTreasury() public {
        vm.prank(lp_1);
        vm.expectRevert(GoatErrors.Forbidden.selector);
        factory.setFeeToTreasury(100e18);
    }

    // UPDATED FACTORY TEST FOR MIGRATION OF PAIRS
    function testFactoryMigrationUpdate() public {
        address[] memory tokens = new address[](3);
        address[] memory pairs = new address[](3);

        tokens[0] = makeAddr("tokens0");
        tokens[1] = makeAddr("tokens1");
        tokens[2] = makeAddr("tokens2");

        pairs[0] = makeAddr("pairs0");
        pairs[1] = makeAddr("pairs1");
        pairs[2] = makeAddr("pairs2");

        GoatV1Factory newFactory = new GoatV1Factory(address(weth), tokens, pairs);

        assertEq(newFactory.weth(), address(weth));
        assertEq(newFactory.getPool(tokens[0]), pairs[0]);
        assertEq(newFactory.getPool(tokens[1]), pairs[1]);
        assertEq(newFactory.getPool(tokens[2]), pairs[2]);

        // test getPair
        assertEq(newFactory.getPair(tokens[0], address(weth)), pairs[0]);
        assertEq(newFactory.getPair(address(weth), tokens[0]), pairs[0]);

        assertEq(newFactory.getPair(tokens[1], address(weth)), pairs[1]);
        assertEq(newFactory.getPair(address(weth), tokens[1]), pairs[1]);

        assertEq(newFactory.getPair(tokens[2], address(weth)), pairs[2]);
        assertEq(newFactory.getPair(address(weth), tokens[2]), pairs[2]);
    }
}
