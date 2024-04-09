// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {GoatV1Factory} from "../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../contracts/periphery/GoatRouterV1.sol";
import {TokenFactory} from "../contracts/tokens/TokenFactory.sol";
import {TokenFactory2} from "../contracts/tokens/TokenFactory2.sol";
import {TokenFactory3} from "../contracts/tokens/TokenFactory3.sol";
import {LotteryTokenMaster} from "../contracts/tokens/LotteryTokenMaster.sol";
import {SupplyChecker} from "../contracts/periphery/SupplyChecker.sol";

import {console2} from "forge-std/Test.sol";

contract DeployMainnet is Script {
    address private _WETH = 0x4200000000000000000000000000000000000006;
    address private factory = 0x2ED91c218Df7deDF7Ce2198eA668F7439d6dcCa2;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //GoatV1Factory factory = new GoatV1Factory(_WETH);
        //GoatV1Router router = new GoatV1Router(address(factory), _WETH);
        LotteryTokenMaster lotteryMaster = new LotteryTokenMaster(factory, _WETH);
        /**TokenFactory tokenFactory = new TokenFactory(address(factory), _WETH);
        TokenFactory2 tokenFactory2 = new TokenFactory2(address(factory), _WETH);
        TokenFactory3 tokenFactory3 = new TokenFactory3(address(factory), _WETH);
        SupplyChecker supplyChecker = new SupplyChecker();
        console2.log("Factory address: ", address(factory));
        console2.log("Router address: ", address(router));
        console2.log("TokenFactory address: ", address(tokenFactory));
        console2.log("TokenFactory2 address: ", address(tokenFactory2));
        console2.log("TokenFactory3 address: ", address(tokenFactory3));
        console2.log("SupplyChecker address: ", address(supplyChecker));**/
        console2.log("LotteryToken master:", address(lotteryMaster));
        vm.stopBroadcast();
    }
}
