// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TaxToken, TokenErrors, IRouter} from "./TaxToken.sol";
import {IWETH} from "./../interfaces/IWETH.sol";

/**
 * @title Vault Token
 * @author Robert M.C. Forster
 * @notice This is a type of tax token that takes a percent of taxes and keeps them in the token contract
 *         to allow tokens to be proportionally redeemed for Ether. It ensures a minimum token price based on past taxes.
 *
 */
contract VaultToken is TaxToken {
    // Percent of taxes to go to vault. 100 == 1%.
    uint256 public vaultPercent;

    // Amount of Ether in this contract owed to the vault.
    uint256 public vaultEth;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _vaultPercent,
        address _weth
    ) TaxToken(_name, _symbol, _initialSupply, _weth) {
        vaultPercent = _vaultPercent;
    }

    receive() external payable {
        assert(msg.sender == _WETH); // only accept ETH via fallback from the WETH contract
    }

    /**
     * @notice Redeem tokens for their vault Ether value.
     * @param _amount The amount of tokens to burn for Ether.
     *
     */
    function redeem(uint256 _amount) external {
        uint256 ethOwed = _amount * vaultEth / totalSupply();
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(ethOwed);
    }

    /**
     * @notice In case the team wants to deposit Ether. Not much of a worry of someone frontrunning because most
     *      of the time I image the Ether deposited will be worth less than the token (assets vs. assets + speculation)
     *
     */
    function deposit() external payable {
        vaultEth += msg.value;
    }

    /**
     * @dev Within this sell taxes and add a percent of the return to the vault.
     *
     */
    function _sellTaxes() internal override returns (uint256 tokens, uint256 ethValue) {
        address token = address(this);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = _WETH;

        tokens = _balances[token];

        // return if dex is not set
        if (dex == address(0)) return (0, 0);

        try IRouter(dex).getAmountsOut(tokens, path) returns (uint256[] memory amounts) {
            ethValue = amounts[1];
            if (ethValue > _minSell) {
                // How do we make impact minor here...
                try IRouter(dex).swapExactTokensForWethSupportingFeeOnTransferTokens(
                    tokens, 0, token, token, block.timestamp
                ) {
                    ethValue = IWETH(_WETH).balanceOf(address(this));
                    IWETH(_WETH).withdraw(ethValue);

                    uint256 ethForVault = ethValue * vaultPercent / _DIVISOR;
                    vaultEth += ethForVault;
                    payable(treasury).transfer(ethValue - ethForVault);
                } catch (bytes memory) {}
            }
        } catch (bytes memory) {}
    }

    /**
     * @notice Find how much Ether an amount of tokens is worth.
     * @param _amount The amount of tokens to find the value of. 1e18 == 1 token.
     *
     */
    function tokenEthValue(uint256 _amount) external view returns (uint256 ethValue) {
        ethValue = _amount * vaultEth / totalSupply();
    }

    /**
     * @notice Change the percent of taxes that are being given to the vault. Not an
     *         extremely sensitive call so we're making it onlyOwnerOrTreasury.
     * @param _newVaultPercent New percent of taxes to give to the vault. 100 == 1%.
     *
     */
    function changeVaultPercent(uint256 _newVaultPercent) external onlyOwnerOrTreasury {
        if (_newVaultPercent > _DIVISOR) revert TokenErrors.NewVaultPercentTooHigh();
        vaultPercent = _newVaultPercent;
    }
}
