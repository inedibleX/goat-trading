// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract TokenErrors {
    error BurnPercentTooHigh();
    error NewBurnPercentTooHigh();
    error NewPotPercentTooHigh();
    error NewVaultPercentTooHigh();
    error OnlyBeneficiaryOrOwner();
    error OnlyBeneficiaryOrRewarder();
    error OnlyLotteryMaster();
    error OnlyOwnerOrTreasury();
    error OnlyTeam();
    error ProvidedRewardsTooHigh();
    error TaxTooHigh();
}
