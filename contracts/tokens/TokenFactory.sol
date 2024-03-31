// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "./TaxToken.sol";
import "./PlainToken.sol";
import "./TaxShareToken.sol";
import "./TaxBurnToken.sol";
import "./DemurrageToken.sol";
import "./DividendToken.sol";
import "./VaultToken.sol";

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external returns (uint256);
    function approve(address user, uint256 amount) external returns (bool);
    function setTaxes(address dex, uint256 buyTax, uint256 sellTax) external;
    function transferBeneficiary(address beneficiary) external;
    function transferOwnership(address owner) external;
    function transferTreasury(address treasury) external;
}

/**
 * @title Token Factory
 * @author Robert M.C. Forster
 * @notice This contract will create all initial advanced Goat tokens except lottery tokens. Lottery
 *         tokens need a master contract that is cleanest separated from the rest of token creation.
 * @dev We'll make a more upgradeable version of this soon to be able to add more tokens types. Right now
 *      we're going for simplicity.
**/
contract TokenFactory {

    IRouter router;

    struct InitParams {
        uint112 virtualEth;
        uint112 bootstrapEth;
        uint112 initialEth;
        uint112 initialTokenMatch;
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
    **/
    function createToken(string memory _name, string memory _symbol, uint256 _totalSupply, 
                         uint256 _buyTax, uint256 _sellTax, address _owner, uint256 _type, uint256 _percent
                         InitParams memory initParams)
      external
      payable
    returns (address tokenAddress, address pool)
    {
        // Create the initial token.
        IToken memory token;
        if (_type == 0) token = IToken(new PlainToken(_name, _symbol, _totalSupply));
        elif (_type == 1) token = IToken(new DemurrageToken(_name, _symbol, _totalSupply, _percent));
        elif (_type == 2) token = IToken(new TaxToken(_name, _symbol, _totalSupply));
        elif (_type == 3) token = IToken(new Taxshare(_name, _symbol, _totalSupply, _percent));
        elif (_type == 4) token = IToken(new Taxburn(_name, _symbol, _totalSupply, _percent));
        elif (_type == 5) token = IToken(new DividendToken(_name, _symbol, _totalSupply));
        elif (_type == 6) token = IToken(new VaultToken(_name, _symbol, _totalSupply, _percent));
        tokenAddress = address(token);

        // Create pool, figure out how many tokens are needed, approve that token amount, add liquidity.
        address pool = factory.createPair(token, initParams);
        (tokenAmtForPresale, tokenAmtForAmm) = GoatLibrary.getTokenAmountsForPresaleAndAmm(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );
        uint256 bootstrapTokenAmt = tokenAmtForPresale + tokenAmtForAmm;
        token.approve(pool, bootstrapTokenAmt);
        router.addLiquidity(token, 0, 0, 0, 0, _owner, block.timestamp, initParams);

        // Set taxes for dex, transfer all ownership to owner.
        if (_type == 1) {
            token.transferBeneficiary(_owner);
        } elif (_type >= 2) {
            token.setTaxes(pool, _buyTax, _sellTax);
            token.transferTreasury(_owner);
        } 

        // Plain tokens do not need ownership transfer.
        if (_type != 0) token.transferOwnership(_owner);

        // Send all tokens back to owner.
        uint256 remainingBalance = token.balanceOf(address(this));
        token.transfer(_owner, remainingBalance);
    }

    function addLiquidity(
        address token,
        uint256 tokenDesired,
        uint256 wethDesired,
        uint256 tokenMin,
        uint256 wethMin,
        address to,
        uint256 deadline,
        GoatTypes.InitParams memory initParams

    }

}