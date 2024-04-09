// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TaxShareToken} from "./TaxShareToken.sol";
import {TaxBurnToken} from "./TaxBurnToken.sol";

import {GoatTypes} from "../library/GoatTypes.sol";
import {GoatLibrary} from "../library/GoatLibrary.sol";

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external returns (uint256);
    function approve(address user, uint256 amount) external returns (bool);
    function setTaxes(address dex, uint256 buyTax, uint256 sellTax) external;
    function transferBeneficiary(address beneficiary) external;
    function transferOwnership(address owner) external;
    function transferTreasury(address treasury) external;
}

interface IGoatFactory {
    function createPair(address _token, GoatTypes.InitParams memory initParams) external returns (address);
}

interface IGoatPair {
    function mint(address to) external returns (uint256 liquidity);
}

enum TokenType {
    PLAIN,
    DEMURRAGE,
    TAX,
    TAXSHARE,
    TAXBURN,
    DIVIDEND,
    VAULT
}

/**
 * @title Token Factory
 * @author Robert M.C. Forster
 * @notice This contract will create all initial advanced Goat tokens except lottery tokens. Lottery
 *         tokens need a master contract that is cleanest separated from the rest of token creation.
 * @dev We'll make a more upgradeable version of this soon to be able to add more tokens types. Right now
 *      we're going for simplicity.
 */
contract TokenFactory2 {
    IGoatFactory private _factory;
    address private immutable _weth;

    error TokenAmountForPoolTooLow();
    error InitialEthNotAccepted();

    constructor(address factory_, address weth_) {
        _factory = IGoatFactory(factory_);
        _weth = weth_;
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
    ) external payable returns (address tokenAddress, address pool) {
        // Create the initial token.

        if (initParams.initialEth != 0) {
            revert InitialEthNotAccepted();
        }
        IToken token;
        if (_type == TokenType.TAXSHARE) {
            token = IToken(address(new TaxShareToken(_name, _symbol, _totalSupply, _percent, _weth)));
        } else if (_type == TokenType.TAXBURN) {
            token = IToken(address(new TaxBurnToken(_name, _symbol, _totalSupply, _percent, _weth)));
        }

        tokenAddress = address(token);

        // Create pool, figure out how many tokens are needed, approve that token amount, add liquidity.
        pool = _factory.createPair(tokenAddress, initParams);
        uint256 bootstrapTokenAmt = GoatLibrary.getActualBootstrapTokenAmount(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (bootstrapTokenAmt < _totalSupply / 10) revert TokenAmountForPoolTooLow();

        token.transfer(pool, bootstrapTokenAmt);
        IGoatPair(pool).mint(_owner);

        token.setTaxes(pool, _buyTax, _sellTax);
        token.transferTreasury(_owner);

        // Plain tokens do not need ownership transfer.
        token.transferOwnership(_owner);

        // Send all tokens back to owner.
        uint256 remainingBalance = token.balanceOf(address(this));
        token.transfer(_owner, remainingBalance);
    }
}
