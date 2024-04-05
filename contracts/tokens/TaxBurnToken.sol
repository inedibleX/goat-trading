// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./TaxToken.sol";

/**
 * @title TaxBurn Token
 * @author Robert M.C. Forster
 * @notice This is a type of tax token that burns a percent of taxed tokens every time taxes are taken.
 *
 */
contract TaxBurnToken is TaxToken {
    // Percent of taxes to burn. 100 == 1%.
    uint256 public burnPercent;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, uint256 _burnPercent)
        TaxToken(_name, _symbol, _initialSupply)
    {
        burnPercent = _burnPercent;
    }

    /* ********************************************* INTERNAL ********************************************* */

    /**
     * @notice In versions with more advanced tax features, this function will be overridden.
     * @param _amount Amount of tax tokens to be awarded.
     *
     */
    function _awardTaxes(uint256 _amount) internal override {
        // Eh, could be more efficient but I like the cleanliness.
        _balances[address(this)] += _amount;
        uint256 burnAmount = _amount * burnPercent / DIVISOR;
        _burn(address(this), burnAmount);
    }

    /* ********************************************* ONLY OWNER/TREASURY ********************************************* */

    /**
     * @notice Change the percent of taxes to burn.
     * @param _newBurnPercent The new percent of taxes to burn. 100 == 1%.
     *
     */
    function changeBurnPercent(uint256 _newBurnPercent) external onlyOwnerOrTreasury {
        require(_newBurnPercent <= DIVISOR, "New vault percent too high.");
        burnPercent = _newBurnPercent;
    }
}
