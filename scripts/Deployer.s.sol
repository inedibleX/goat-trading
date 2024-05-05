// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {GoatV1Factory} from "../contracts/exchange/GoatV1Factory.sol";
import {GoatV1Router} from "../contracts/periphery/GoatV1Router.sol";
import {TokenFactory, TokenType} from "../contracts/tokens/TokenFactory.sol";
import {TokenFactory2} from "../contracts/tokens/TokenFactory2.sol";
import {TokenFactory3} from "../contracts/tokens/TokenFactory3.sol";
import {GoatHelper} from "../contracts/periphery/GoatHelper.sol";
import {GoatTypes} from "../contracts/library/GoatTypes.sol";

// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {ITokenFactory} from "./../contracts/tokens/interfaces/ITokenFactory.sol";
// import {IGoatV1Pair} from "./../contracts/interfaces/IGoatV1Pair.sol";

import {console2} from "forge-std/Test.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _WETH = 0x4200000000000000000000000000000000000006;

        GoatV1Factory factory = new GoatV1Factory(_WETH);
        GoatV1Router router = new GoatV1Router(address(factory), _WETH);
        TokenFactory tokenFactory = new TokenFactory(address(factory), _WETH);
        TokenFactory2 tokenFactory2 = new TokenFactory2(address(factory), _WETH);
        TokenFactory3 tokenFactory3 = new TokenFactory3(address(factory), _WETH);
        GoatHelper goatHelper = new GoatHelper(address(router));
        console2.log("Factory address: ", address(factory));
        console2.log("Router address: ", address(router));
        console2.log("TokenFactory address: ", address(tokenFactory));
        console2.log("TokenFactory2 address: ", address(tokenFactory2));
        console2.log("TokenFactory3 address: ", address(tokenFactory3));
        console2.log("GoatHelper address: ", address(goatHelper));

        // create tokens
        (address taxToken, address pairTaxToken) = tokenFactory.createToken(
            "TaxToken",
            "TT1",
            1e21,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.TAX,
            1000,
            GoatTypes.InitParams(10e18, 10e18, 0, 1000e18)
        );

        // create taxshare token
        (address taxshareToken, address pairTaxShareToken) = tokenFactory2.createToken(
            "TaxShareToken",
            "TST1",
            1e21,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.TAXSHARE,
            1000,
            GoatTypes.InitParams(10e18, 10e18, 0, 1000e18)
        );
        // create taxburn token
        (address taxburnToken, address pairTaxBurnToken) = tokenFactory2.createToken(
            "TaxBurnToken",
            "TBT1",
            1e21,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.TAXBURN,
            1000,
            GoatTypes.InitParams(10e18, 10e18, 0, 1000e18)
        );

        // create vault token
        (address vaultToken, address pairVaultToken) = tokenFactory3.createToken(
            "VaultToken",
            "VT1",
            1e21,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.VAULT,
            1000,
            GoatTypes.InitParams(10e18, 10e18, 0, 1000e18)
        );

        // create dividend token
        (address dividendToken, address pairDividendToken) = tokenFactory3.createToken(
            "DividendToken",
            "DT1",
            1e21,
            100,
            100,
            0xF5265544F4072692409Bd41267679dd548489d42,
            TokenType.DIVIDEND,
            1000,
            GoatTypes.InitParams(10e18, 10e18, 0, 1000e18)
        );

        console2.log("TaxToken address: ", taxToken);
        console2.log("TaxShareToken address: ", taxshareToken);
        console2.log("TaxBurnToken address: ", taxburnToken);
        console2.log("VaultToken address: ", vaultToken);
        console2.log("DividendToken address: ", dividendToken);

        console2.log("PairTaxToken address: ", pairTaxToken);
        console2.log("PairTaxShareToken address: ", pairTaxShareToken);
        console2.log("PairTaxBurnToken address: ", pairTaxBurnToken);
        console2.log("PairVaultToken address: ", pairVaultToken);
        console2.log("PairDividendToken address: ", pairDividendToken);

        vm.stopBroadcast();
    }
}
