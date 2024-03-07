// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {GoatV1Factory} from "../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../contracts/periphery/GoatRouterV1.sol";

import {console2} from "forge-std/Test.sol";

contract DeployMainnet is Script {
    address private _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY1");
        vm.startBroadcast(deployerPrivateKey);
        GoatV1Factory factory = new GoatV1Factory(_WETH);
        GoatV1Router router = new GoatV1Router(address(factory), _WETH);
        console2.log("Factory address: ", address(factory));
        console2.log("Router address: ", address(router));
        vm.stopBroadcast();
    }
}
