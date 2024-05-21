// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {DividendToken} from "./DividendToken.sol";
import {VaultToken} from "./VaultToken.sol";

import {GoatTypes} from "../library/GoatTypes.sol";
import {GoatLibrary} from "../library/GoatLibrary.sol";
import {TokenErrors} from "./library/TokenErrors.sol";
import {TokenType} from "./library/TokenTypes.sol";

import {IToken} from "./../interfaces/IToken.sol";
import {IGoatV1Pair} from "./../interfaces/IGoatV1Pair.sol";
import {IGoatV1Factory} from "./../interfaces/IGoatV1Factory.sol";

/**
 * @title Token Factory
 * @author Robert M.C. Forster
 * @notice This contract will create all initial advanced Goat tokens except lottery tokens. Lottery
 *         tokens need a master contract that is cleanest separated from the rest of token creation.
 * @dev We'll make a more upgradeable version of this soon to be able to add more tokens types. Right now
 *      we're going for simplicity.
 */
contract TokenFactory3 {
    IGoatV1Factory private _factory;
    address private immutable _weth;
    address private immutable _router;

    constructor(address factory_, address weth_, address router_) {
        _factory = IGoatV1Factory(factory_);
        _weth = weth_;
        _router = router_;
    }

    /* ********************************************* TOKEN CREATION ********************************************* */

    /**
     * @dev Type is the type of token:
     * 0: plain token
     * 1: demurrage
     * 2: plain tax
     * 3: taxshare
     * 4: taxburn
     * 5: dividend
     * 6: vault
     * @param _percent Refers to the extra variable many contracts have. Mostly equates to the percent
     *                 of taxes that go toward the tokens advanced features. Demurrage is decay % per sec.
     *
     */
    function createToken(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _buyTax,
        uint256 _sellTax,
        address _owner,
        TokenType _type,
        uint256 _percent,
        GoatTypes.InitParams memory initParams
    ) external returns (address tokenAddress, address pool) {
        // Create the initial token.

        if (initParams.initialEth != 0) {
            revert TokenErrors.InitialEthNotAccepted();
        }
        if (_type == TokenType.DIVIDEND) {
            tokenAddress = address(new DividendToken(_name, _symbol, _totalSupply, _weth));
        } else if (_type == TokenType.VAULT) {
            tokenAddress = address(new VaultToken(_name, _symbol, _totalSupply, _percent, _weth));
        } else {
            revert TokenErrors.InvalidTokenType();
        }

        IToken token = IToken(tokenAddress);
        // Create pool, figure out how many tokens are needed, approve that token amount, add liquidity.
        pool = _factory.createPair(tokenAddress, initParams);
        uint256 bootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (bootstrapTokenAmt < _totalSupply / 10) revert TokenErrors.TokenAmountForPoolTooLow();

        token.transfer(pool, bootstrapTokenAmt);
        IGoatV1Pair(pool).mint(_owner);

        token.setTaxes(pool, _buyTax, _sellTax);
        if (_type == TokenType.DIVIDEND) {
            token.revokeRewardsEligibility(pool, true);
        }

        token.changeDex(_router);
        token.transferTreasury(_owner);

        // Plain tokens do not need ownership transfer.
        token.transferOwnership(_owner);

        // Send all tokens back to owner.
        uint256 remainingBalance = token.balanceOf(address(this));
        token.transfer(_owner, remainingBalance);
    }
}
