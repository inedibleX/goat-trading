// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

contract GoatTypes {
    struct Pool {
        uint112 reserveEth;
        uint112 reserveToken;
        uint32 lastTrade;
        uint112 totalSupply;
        uint112 virtualEth;
        uint32 vestingUntil;
        uint112 bootstrapEth;
        uint112 feesPerTokenStored;
        bool exists;
        uint256 kLast;
    }

    struct LPInfo {
        uint224 balance;
        uint32 lockedUntil;
    }

    struct LaunchParams {
        uint112 virtualEth;
        uint112 bootstrapEth;
        uint112 initialEth;
        uint112 initialTokenMatch;
    }

    struct FractionalLiquidity {
        uint112 fractionalBalance;
        uint32 lastWithdraw;
        uint8 withdrawlLeft;
    }

    struct InitParams {
        uint112 virtualEth;
        uint112 bootstrapEth;
        uint112 initialEth;
        uint112 initialTokenMatch;
    }

    struct InitialLPInfo {
        address liquidityProvider;
        // it's safe to use uint104 as it can hold 20 trillion ether
        uint104 initialWethAdded;
        uint112 fractionalBalance;
        uint32 lastWithdraw;
        uint8 withdrawalLeft;
    }

    struct LocalVariables_AddLiquidity {
        bool isNewPair;
        address pair;
        uint256 actualTokenAmount;
        uint256 tokenAmount;
        uint256 wethAmount;
        uint256 liquidity;
        address token;
    }

    struct LocalVariables_MintLiquidity {
        uint112 virtualEth;
        uint112 initialTokenMatch;
        uint256 bootstrapEth;
        bool isFirstMint;
    }

    struct LocalVariables_Swap {
        bool isBuy;
        bool isPresale;
        uint256 initialReserveEth;
        uint256 initialReserveToken;
        uint256 finalReserveEth;
        uint256 finalReserveToken;
        uint256 amountWethIn;
        uint256 amountTokenIn;
        uint256 feesCollected;
        uint256 lpFeesCollected;
        uint256 tokenAmount;
        uint32 vestingUntil;
        uint256 bootstrapEth;
        uint256 virtualEthReserveBefore;
        uint256 virtualTokenReserveBefore;
        uint256 virtualEthReserveAfter;
        uint256 virtualTokenReserveAfter;
    }

    struct LocalVariables_PairStateInfo {
        uint112 reserveEth;
        uint112 reserveToken;
        uint112 virtualEth;
        uint112 initialTokenMatch;
        uint112 bootstrapEth;
        uint256 virtualToken;
    }

    struct LocalVariables_TokenAmountOutInfo {
        uint256 actualWethIn;
        uint256 numerator;
        uint256 denominator;
        uint256 amountTokenOutPresale;
        uint256 amountTokenOutAmm;
        uint256 wethForAmm;
        uint256 wethForPresale;
    }

    struct LocalVariables_TakeOverPool {
        uint256 minTokenNeeded;
        uint256 tokenAmountForPresaleOld;
        uint256 tokenAmountForAmmOld;
        uint256 tokenAmountForPresaleNew;
        uint256 tokenAmountForAmmNew;
        uint256 virtualEthOld;
        uint256 initialTokenMatchOld;
        uint256 bootstrapEthOld;
        uint256 reserveToken;
        uint256 reserveEth;
        uint256 pendingProtocolFees;
        uint256 pendingLiquidityFees;
    }
}
