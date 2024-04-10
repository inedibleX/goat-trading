// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {GoatV1Factory} from "../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../contracts/periphery/GoatRouterV1.sol";
import {TokenFactory, TokenType} from "../contracts/tokens/TokenFactory.sol";
import {TokenFactory2} from "../contracts/tokens/TokenFactory2.sol";
import {TokenFactory3} from "../contracts/tokens/TokenFactory3.sol";
import {LotteryTokenMaster} from "../contracts/tokens/LotteryTokenMaster.sol";
import {SupplyChecker} from "../contracts/periphery/SupplyChecker.sol";
import {GoatTypes} from "../contracts/library/GoatTypes.sol";

import {console2} from "forge-std/Test.sol";

contract DeployMainnet is Script {
    address private _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // mainnet
    // address private _WETH = 0x4200000000000000000000000000000000000006; // base
    // address private factory = 0x2ED91c218Df7deDF7Ce2198eA668F7439d6dcCa2;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GoatV1Factory factory = new GoatV1Factory(_WETH);
        GoatV1Router router = new GoatV1Router(address(factory), _WETH);
        // LotteryTokenMaster lotteryMaster = new LotteryTokenMaster(factory, _WETH);
        TokenFactory tokenFactory = new TokenFactory(address(factory), _WETH);
        TokenFactory2 tokenFactory2 = new TokenFactory2(address(factory), _WETH);
        TokenFactory3 tokenFactory3 = new TokenFactory3(address(factory), _WETH);
        SupplyChecker supplyChecker = new SupplyChecker();
        console2.log("Factory address: ", address(factory));
        console2.log("Router address: ", address(router));
        console2.log("TokenFactory address: ", address(tokenFactory));
        console2.log("TokenFactory2 address: ", address(tokenFactory2));
        console2.log("TokenFactory3 address: ", address(tokenFactory3));
        console2.log("SupplyChecker address: ", address(supplyChecker));
        // console2.log("LotteryToken master:", address(lotteryMaster));
        vm.stopBroadcast();
    }
}
// BASE SEPOLIA REMOVE ENUM
//   Factory address:  0xCfC1BE3Be99eF9d997eD72890950387657b733B8
//   Router address:  0xFEf213A017535712FAF178b44401135087ff015A
//   TokenFactory address:  0x871d2C5678B0866BfAc567Ff8BDc71c8d4E57A03
//   SupplyChecker address:  0x12646a381B9DDca480315dEaC452FcB1676f2D70

// BASE SEPOLIA REMOVE ENUM
//   Factory address:  0x9e23F7059C95859524246a2b7F33145797D393ff
//   Router address:  0xb7ecE757F6dfC146D3458805Ad8281f738B4e662
//   TokenFactory address:  0xFdd7b8d99388A04Be4362f17D239902C1E679497
//   SupplyChecker address:  0x941d5454c94d183a193eF2456a2e43b52E7FEcDC

// BASE SEPOLIA
//   Factory address:  0x246c4EA319f9bbB5E7816e73e2B79dc98C64AE58
//   Router address:  0xdb9E9F3397f48cDd5772E5Cd876703Ddd5392010
//   TokenFactory address:  0x3a108348128C2d179Ac1d8a998DEc52e6334a285
//   TokenFactory2 address:  0x991DE6Bdc788BB0bA5594ed7fbF9f4F52711D3F4
//   TokenFactory3 address:  0x406843AF2704eaE3671671083d1cef1384aaa129
//   SupplyChecker address:  0xEb09f3780bd5926708cc55Db6184D1c64611d52D

//  MAINNET FORK
//   Factory address:  0xf9318A7b1B9B5a367e94045EcD87d2A66DC7C8df
//   Router address:  0x81E8416369338817025Eb63253D7C84f60E22010
//   TokenFactory address:  0xb3269f3a635C15b5270fb11CE71898F712262b98
//   TokenFactory2 address:  0x4a3D3C867BEEE178f9b698a5BAE6Ae29630464Fb
//   TokenFactory3 address:  0x075d103679f01BE1fAE51Ec05d556fDE6ab8C879
//   SupplyChecker address:  0xde86646d01Ff1EE77E26700f12C3B4d2F7F73B94

// BASE FORK
//   Factory address:  0x33603C1618b02916B82dcBe7C9A3EcF5ac138858
//   Router address:  0x946BBe1d592B00De5C01329F7CBD9E218d3775a5
//   TokenFactory address:  0x512a619f765434be6775D88E0d51a648139ff340
//   TokenFactory2 address:  0x1404DDD5BC09a6375c7F11516BB5601625f231a3
//   TokenFactory3 address:  0x2f24FF4b205B24E352b05139D49dca2e4CC5D171
//   SupplyChecker address:  0xB4A09f4B3711a9bed5Ff676b311609fC23c88ae7

contract DeployTaxToken is Script {
    // TokenFactory tokenFactory = TokenFactory(0x871d2C5678B0866BfAc567Ff8BDc71c8d4E57A03);
    // TokenFactory tokenFactory = TokenFactory(0x33603C1618b02916B82dcBe7C9A3EcF5ac138858); // enum base testnet

    // TokenFactory tokenFactory = TokenFactory(0x512a619f765434be6775D88E0d51a648139ff340); // enum base fork
    TokenFactory tokenFactory = TokenFactory(0xb3269f3a635C15b5270fb11CE71898F712262b98); // enum mainnet fork
    uint256 private totalSupply = 1e21;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        GoatTypes.InitParams memory initParams;
        initParams.bootstrapEth = 10e18;
        initParams.initialEth = 0;
        initParams.initialTokenMatch = 1000e18;
        initParams.virtualEth = 10e18;
        console2.log("Creating TaxToken");
        console2.log(uint8(TokenType.TAX));
        (address token, address pool) = tokenFactory.createToken(
            "TaxToken",
            "TT1",
            totalSupply,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.TAX,
            1000,
            initParams
        );

        console2.log("Token address: ", token);
        console2.log("Pool address: ", pool);
        vm.stopBroadcast();
    }
}
