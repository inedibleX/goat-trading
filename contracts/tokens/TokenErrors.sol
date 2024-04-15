// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract TokenErrors {
    error BurnPercentTooHigh();
    error NewBurnPercentTooHigh();
    error OnlyBeneficiaryOrOwner();
    error OnlyBeneficiaryOrRewarder();
    error OnlyLotteryMaster();
    error OnlyTeam();
    error ProvidedRewardsTooHigh();
    error NewPotPercentTooHigh();
    error NewVaultPercentTooHigh();
    error TaxTooHigh();
    error OnlyOwnerOrTreasury();
}
