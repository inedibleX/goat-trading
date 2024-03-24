// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// library imports
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// local imports
import {GoatErrors} from "../library/GoatErrors.sol";
import {GoatTypes} from "../library/GoatTypes.sol";
import {GoatV1ERC20} from "./GoatV1ERC20.sol";

// interfaces
import {IGoatV1Factory} from "../interfaces/IGoatV1Factory.sol";

/**
 * @title Goat Trading V1 Pair
 * @notice Main contract for Goat Trading V1 and should be called from contract with safety checks.
 * @dev This contract is a pair of two tokens that are traded against each other.
 *  The pair is deployed by the factory contract.
 * Mint, Burn, Swap, and Takeover are handled in this contract.
 * @author Goat Trading -- Chiranjibi Poudyal, Robert M.C. Forster
 */
contract GoatV1Pair is GoatV1ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint32 private constant _MIN_LOCK_PERIOD = 2 days;
    uint32 public constant VESTING_PERIOD = 7 days;
    uint32 private constant _MAX_UINT32 = type(uint32).max;
    uint32 private constant _THIRTY_DAYS = 30 days;

    address public immutable factory;
    uint32 private immutable _genesis;
    // Figure out a way to use excess 12 bytes in here to store something
    address private _token;
    address private _weth;

    uint112 private _virtualEth;
    uint112 private _initialTokenMatch;
    uint32 private _vestingUntil;

    // this is the real amount of eth in the pool
    uint112 private _reserveEth;
    // token reserve in the pool
    uint112 private _reserveToken;
    // variable used to check for mev
    uint32 private _lastTrade;

    // Amounts of eth needed to turn pool into an amm
    uint112 private _bootstrapEth;
    // total lp fees that are not withdrawn
    uint112 private _pendingLiquidityFees;

    // Fees per token scaled by 1e18
    uint184 public feesPerTokenStored;
    // Can store >4500 ether which is more than enough
    uint72 private _pendingProtocolFees;

    mapping(address => uint256) private _presaleBalances;
    mapping(address => uint256) public lpFees;
    mapping(address => uint256) public feesPerTokenPaid;

    GoatTypes.InitialLPInfo private _initialLPInfo;

    event Mint(address, uint256, uint256);
    event Burn(address, uint256, uint256, address);
    event Swap(address, uint256, uint256, uint256, uint256, address);

    constructor() {
        factory = msg.sender;
        _genesis = uint32(block.timestamp);
    }

    /* ----------------------------- EXTERNAL FUNCTIONS ----------------------------- */
    function initialize(address token, address weth, string memory baseName, GoatTypes.InitParams memory params)
        external
    {
        if (msg.sender != factory) revert GoatErrors.GoatV1Forbidden();
        _token = token;
        _weth = weth;
        // setting non zero value so that swap will not incur new storage write on update
        _vestingUntil = _MAX_UINT32;
        // Is there a token without a name that may result in revert in this case?
        string memory tokenName = IERC20Metadata(_token).name();
        name = string(abi.encodePacked("GoatTradingV1: ", baseName, "/", tokenName));
        symbol = string(abi.encodePacked("GoatV1-", baseName, "-", tokenName));
        _initialTokenMatch = params.initialTokenMatch;
        _virtualEth = params.virtualEth;
        _bootstrapEth = params.bootstrapEth;
    }

    /**
     * @notice Should be called from a contract with safety checks
     * @notice Mints liquidity tokens in exchange for ETH and tokens deposited into the pool.
     * @dev This function allows users to add liquidity to the pool,
     *      receiving liquidity tokens in return. It includes checks for
     *      the presale period and calculates liquidity based on virtual amounts at presale
     *      and deposited ETH and tokens when it's an amm.
     * @param to The address to receive the minted liquidity tokens.
     * @return liquidity The amount of liquidity tokens minted.
     * Requirements:
     * - Cannot add liquidity during the presale period if the total supply is greater than 0.
     * - The amount of ETH deposited must not exceed the bootstrap ETH amount on first mint.
     * - Ensures the deposited token amount matches the required amount for liquidity bootstrapping.
     * Emits:
     * - A `Mint` event with details for the mint transaction.
     * Security:
     * - Uses `nonReentrant` modifier to prevent reentrancy attacks.
     */
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        uint256 totalSupply_ = totalSupply();
        uint256 amountWeth;
        uint256 amountToken;
        uint256 balanceEth = IERC20(_weth).balanceOf(address(this));
        uint256 balanceToken = IERC20(_token).balanceOf(address(this));

        GoatTypes.LocalVariables_MintLiquidity memory mintVars;

        mintVars.virtualEth = _virtualEth;
        mintVars.initialTokenMatch = _initialTokenMatch;
        mintVars.bootstrapEth = _bootstrapEth;

        if (_vestingUntil == _MAX_UINT32) {
            // Do not allow to add liquidity in presale period
            if (totalSupply_ > 0) revert GoatErrors.PresalePeriod();
            // don't allow to send more eth than bootstrap eth
            if (balanceEth > mintVars.bootstrapEth) {
                revert GoatErrors.SupplyMoreThanBootstrapEth();
            }

            if (balanceEth < mintVars.bootstrapEth) {
                (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) = _tokenAmountsForLiquidityBootstrap(
                    mintVars.virtualEth, mintVars.bootstrapEth, balanceEth, mintVars.initialTokenMatch
                );
                if (balanceToken != (tokenAmtForPresale + tokenAmtForAmm)) {
                    revert GoatErrors.InsufficientTokenAmount();
                }
                liquidity =
                    Math.sqrt(uint256(mintVars.virtualEth) * uint256(mintVars.initialTokenMatch)) - MINIMUM_LIQUIDITY;
            } else {
                // This means that user is willing to make this pool an amm pool in first liquidity mint
                liquidity = Math.sqrt(balanceEth * balanceToken) - MINIMUM_LIQUIDITY;
                uint32 timestamp = uint32(block.timestamp);
                _vestingUntil = timestamp + VESTING_PERIOD;
            }
            mintVars.isFirstMint = true;
        } else {
            // at this point in time we will get the actual reserves
            (uint256 reserveEth, uint256 reserveToken) = getReserves();
            amountWeth = balanceEth - reserveEth - _pendingLiquidityFees - _pendingProtocolFees;
            amountToken = balanceToken - reserveToken;
            liquidity = Math.min((amountWeth * totalSupply_) / reserveEth, (amountToken * totalSupply_) / reserveToken);
        }

        // @note can this be an attack area to grief initial lp by using to as initial lp?
        if (mintVars.isFirstMint || to == _initialLPInfo.liquidityProvider) {
            _updateInitialLpInfo(liquidity, balanceEth, to, false, false);
        }
        if (!mintVars.isFirstMint) _updateFeeRewards(to);

        if (totalSupply_ == 0) {
            _mint(address(0), MINIMUM_LIQUIDITY);
        }

        _mint(to, liquidity);

        _update(balanceEth, balanceToken, true);

        emit Mint(msg.sender, amountWeth, amountToken);
    }

    /**
     * @notice Should be called from a contract with safety checks
     * @notice Burns liquidity tokens to remove liquidity from the pool and withdraw ETH and tokens.
     * @dev This function allows liquidity providers to burn their liquidity
     *         tokens in exchange for the underlying assets (ETH and tokens).
     *         It updates the initial liquidity provider information,
     *         applies fee rewards, and performs necessary state updates.
     * @param to The address to which the withdrawn ETH and tokens will be sent.
     * @return amountWeth The amount of WETH withdrawn from the pool.
     * @return amountToken The amount of tokens withdrawn from the pool.
     * Reverts:
     * - If the function is called by the initial liquidity provider during the presale period.
     * Emits:
     * - A `Burn` event with necessary details of the burn.
     */
    function burn(address to) external returns (uint256 amountWeth, uint256 amountToken) {
        uint256 liquidity = balanceOf(address(this));

        // initial lp can bypass this check by using different
        // to address so _lastPoolTokenSender is used
        if (_vestingUntil == _MAX_UINT32) revert GoatErrors.PresalePeriod();

        uint256 totalSupply_ = totalSupply();
        amountWeth = (liquidity * _reserveEth) / totalSupply_;
        amountToken = (liquidity * _reserveToken) / totalSupply_;
        if (amountWeth == 0 || amountToken == 0) {
            revert GoatErrors.InsufficientLiquidityBurned();
        }

        _updateFeeRewards(to);
        _burn(address(this), liquidity);

        // Transfer liquidity tokens to the user
        IERC20(_weth).safeTransfer(to, amountWeth);
        IERC20(_token).safeTransfer(to, amountToken);
        uint256 balanceEth = IERC20(_weth).balanceOf(address(this));
        uint256 balanceToken = IERC20(_token).balanceOf(address(this));

        _update(balanceEth, balanceToken, true);

        emit Burn(msg.sender, amountWeth, amountToken, to);
    }

    /**
     * @notice Should be called from a contract with safety checks
     * @notice Executes a swap from ETH to tokens or tokens to ETH.
     * @dev This function handles the swapping logic, including MEV
     *  checks, fee application, and updating reserves.
     * @param amountTokenOut The amount of tokens to be sent out.
     * @param amountWethOut The amount of WETH to be sent out.
     * @param to The address to receive the output of the swap.
     * Requirements:
     * - Either `amountTokenOut` or `amountWethOut` must be greater than 0, but not both.
     * - The output amount must not exceed the available reserves in the pool.
     * - If the swap occurs in vesting period (presale included),
     *   it updates the presale balance for the buyer.
     * - Applies fees and updates reserves accordingly.
     * - Ensures the K invariant holds after the swap,
     *   adjusting for virtual reserves during the presale period.
     * - Transfers the specified `amountTokenOut` or `amountWethOut` to the address `to`.
     * - In case of a presale swap, adds LP fees to the reserve ETH.
     * Emits:
     * - A `Swap` event with details about the amounts swapped.
     * Security:
     * - Uses `nonReentrant` modifier to prevent reentrancy attacks.
     */
    function swap(uint256 amountTokenOut, uint256 amountWethOut, address to) external nonReentrant {
        if (amountTokenOut == 0 && amountWethOut == 0) {
            revert GoatErrors.InsufficientOutputAmount();
        }
        if (amountTokenOut != 0 && amountWethOut != 0) {
            revert GoatErrors.MultipleOutputAmounts();
        }
        GoatTypes.LocalVariables_Swap memory swapVars;
        swapVars.isBuy = amountWethOut > 0 ? false : true;
        // check for mev
        _handleMevCheck(swapVars.isBuy);

        (swapVars.initialReserveEth, swapVars.initialReserveToken) = _getActualReserves();

        if (amountTokenOut > swapVars.initialReserveToken || amountWethOut > swapVars.initialReserveEth) {
            revert GoatErrors.InsufficientAmountOut();
        }

        if (swapVars.isBuy) {
            swapVars.amountWethIn = IERC20(_weth).balanceOf(address(this)) - swapVars.initialReserveEth
                - _pendingLiquidityFees - _pendingProtocolFees;
            // optimistically send tokens out
            IERC20(_token).safeTransfer(to, amountTokenOut);
        } else {
            swapVars.amountTokenIn = IERC20(_token).balanceOf(address(this)) - swapVars.initialReserveToken;
            // optimistically send weth out
            IERC20(_weth).safeTransfer(to, amountWethOut);
        }
        swapVars.vestingUntil = _vestingUntil;
        swapVars.isPresale = swapVars.vestingUntil == _MAX_UINT32;

        (swapVars.feesCollected, swapVars.lpFeesCollected) =
            _handleFees(swapVars.amountWethIn, amountWethOut, swapVars.isPresale);

        swapVars.tokenAmount = swapVars.isBuy ? amountTokenOut : swapVars.amountTokenIn;

        // We store details of participants so that we only allow users who have
        // swap back tokens who have bought in the vesting period.
        if (swapVars.vestingUntil > block.timestamp) {
            _updatePresale(to, swapVars.tokenAmount, swapVars.isBuy);
        }

        if (swapVars.isBuy) {
            swapVars.amountWethIn -= swapVars.feesCollected;
        } else {
            unchecked {
                amountWethOut += swapVars.feesCollected;
            }
        }
        swapVars.finalReserveEth = swapVars.isBuy
            ? swapVars.initialReserveEth + swapVars.amountWethIn
            : swapVars.initialReserveEth - amountWethOut;
        swapVars.finalReserveToken = swapVars.isBuy
            ? swapVars.initialReserveToken - amountTokenOut
            : swapVars.initialReserveToken + swapVars.amountTokenIn;

        swapVars.bootstrapEth = _bootstrapEth;
        // presale lp fees should go to reserve eth
        if (swapVars.isPresale && ((swapVars.finalReserveEth + swapVars.lpFeesCollected) > swapVars.bootstrapEth)) {
            // at this point pool should be changed to an AMM
            _checkAndConvertPool(swapVars.finalReserveEth + swapVars.lpFeesCollected, swapVars.finalReserveToken);
        } else {
            // check for K

            (swapVars.virtualEthReserveBefore, swapVars.virtualTokenReserveBefore) =
                _getReserves(swapVars.vestingUntil, swapVars.initialReserveEth, swapVars.initialReserveToken);
            (swapVars.virtualEthReserveAfter, swapVars.virtualTokenReserveAfter) =
                _getReserves(swapVars.vestingUntil, swapVars.finalReserveEth, swapVars.finalReserveToken);
            if (
                swapVars.virtualEthReserveBefore * swapVars.virtualTokenReserveBefore
                    > swapVars.virtualEthReserveAfter * swapVars.virtualTokenReserveAfter
            ) {
                revert GoatErrors.KInvariant();
            }
        }

        if (swapVars.isPresale) {
            swapVars.finalReserveEth += swapVars.lpFeesCollected;
        }
        _update(swapVars.finalReserveEth, swapVars.finalReserveToken, false);

        emit Swap(
            msg.sender,
            swapVars.amountWethIn + swapVars.feesCollected,
            swapVars.amountTokenIn,
            amountWethOut,
            amountTokenOut,
            to
        );
    }

    /**
     * @notice Synchronizes the reserves of the pool with the current balances.
     * @dev This function updates the reserves to reflect the current reserve of WETH and token
     */
    function sync() external nonReentrant {
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        uint256 wethBalance = IERC20(_weth).balanceOf(address(this));
        _update(wethBalance, tokenBalance, true);
    }

    function _getActualReserves() internal view returns (uint112 reserveEth, uint112 reserveToken) {
        reserveEth = _reserveEth;
        reserveToken = _reserveToken;
    }

    function _getReserves(uint32 vestingUntil_, uint256 ethReserve, uint256 tokenReserve)
        internal
        view
        returns (uint112 reserveEth, uint112 reserveToken)
    {
        // just pass eth reserve and token reserve here only use virtual eth and initial token match
        // if pool has not turned into an AMM
        if (vestingUntil_ != _MAX_UINT32) {
            // Actual reserves
            reserveEth = uint112(ethReserve);
            reserveToken = uint112(tokenReserve);
        } else {
            uint256 initialTokenMatch = _initialTokenMatch;
            uint256 virtualEth = _virtualEth;
            uint256 virtualToken = _getVirtualTokenAmt(virtualEth, _bootstrapEth, initialTokenMatch);
            // Virtual reserves
            reserveEth = uint112(virtualEth + ethReserve);
            reserveToken = uint112(virtualToken + tokenReserve);
        }
    }

    /// @notice returns real reserves if pool has turned into an AMM else returns virtual reserves
    function getReserves() public view returns (uint112 reserveEth, uint112 reserveToken) {
        (reserveEth, reserveToken) = _getReserves(_vestingUntil, _reserveEth, _reserveToken);
    }

    /**
     * @notice Withdraws excess tokens from the pool and converts it into an AMM.
     * @dev Allows the initial liquidity provider to withdraw tokens if
     *  bootstrap goals are not met even after 1 month of launching the pool and
     *  forces the pool to transition to an AMM with the real reserve of with and
     *  matching tokens required at that point.
     * Requirements:
     * - Can only be called by the initial liquidity provider.
     * - Can only be called 30 days after the contract's genesis.
     * - Pool should transition to an AMM after successful exectuion of this function.
     * Post-Conditions:
     * - Excess tokens are returned to the initial liquidity provider.
     * - The pool transitions to an AMM with the real reserves of ETH and tokens.
     * - Deletes the pair from the factory if eth raised is zero.
     */
    function withdrawExcessToken() external {
        uint256 timestamp = block.timestamp;
        // initial liquidty provider can call this function after 30 days from genesis
        if (_genesis + _THIRTY_DAYS > timestamp) revert GoatErrors.PresaleDeadlineActive();
        if (_vestingUntil != _MAX_UINT32) {
            revert GoatErrors.ActionNotAllowed();
        }

        address initialLiquidityProvider = _initialLPInfo.liquidityProvider;
        if (msg.sender != initialLiquidityProvider) {
            revert GoatErrors.Unauthorized();
        }

        // as bootstrap eth is not met we consider reserve eth as bootstrap eth
        // and turn presale into an amm with less liquidity.
        uint256 reserveEth = _reserveEth;

        uint256 bootstrapEth = reserveEth;

        // if we know token amount for AMM we can remove excess tokens that are staying in this contract
        (, uint256 tokenAmtForAmm) =
            _tokenAmountsForLiquidityBootstrap(_virtualEth, bootstrapEth, 0, _initialTokenMatch);

        IERC20 token = IERC20(_token);
        uint256 poolTokenBalance = token.balanceOf(address(this));

        uint256 amountToTransferBack = poolTokenBalance - tokenAmtForAmm;
        // transfer excess token to the initial liquidity provider
        token.safeTransfer(initialLiquidityProvider, amountToTransferBack);

        if (reserveEth != 0) {
            _updateLiquidityAndConvertToAmm(reserveEth, tokenAmtForAmm);
            // update bootstrap eth because original bootstrap eth was not met and
            // eth we raised until this point should be considered as bootstrap eth
            _bootstrapEth = uint112(bootstrapEth);
            _update(reserveEth, tokenAmtForAmm, false);
        } else {
            IGoatV1Factory(factory).removePair(_token);
        }
    }

    /**
     * @notice Allows a team to take over a pool from malicious actors.
     * @dev Prevents malicious actors from griefing the pool by setting unfavorable
     *   initial conditions. It requires the new team to match the pool reserves of
     *   WETH amount and exceed their token contribution by at least 10%.
     *   This function also resets the pool's initial liquidity parameters.
     * @param initParams The new initial parameters for the pool.
     * Requirements:
     * - Pool must be in presale period.
     * - The `tokenAmount` must be at least 10% greater and equal to bootstrap token needed for new params.
     * - Tokens must be transferred to the pool before calling this function.
     * Reverts:
     * - If the pool has already transitioned to an AMM.
     * - If `tokenAmountIn` is less than the minimum required to take over the pool.
     * - If `wethAmountIn` is less than the reserve ETH.
     * Post-Conditions:
     * - Transfers the amount of token and weth after penalty to initial lp.
     * - Burns the initial liquidity provider's tokens and
     *   mints new liquidity tokens to the new team based on the new `initParams`.
     * - Resets the pool's initial liquidity parameters to the new `initParams`.
     * - Updates the pool's reserves to reflect the new token balance.
     */
    function takeOverPool(GoatTypes.InitParams memory initParams) external {
        if (_vestingUntil != _MAX_UINT32) {
            revert GoatErrors.ActionNotAllowed();
        }

        GoatTypes.InitialLPInfo memory initialLpInfo = _initialLPInfo;

        GoatTypes.LocalVariables_TakeOverPool memory localVars;
        address to = msg.sender;
        localVars.virtualEthOld = _virtualEth;
        localVars.bootstrapEthOld = _bootstrapEth;
        localVars.initialTokenMatchOld = _initialTokenMatch;

        (localVars.tokenAmountForPresaleOld, localVars.tokenAmountForAmmOld) = _tokenAmountsForLiquidityBootstrap(
            localVars.virtualEthOld,
            localVars.bootstrapEthOld,
            initialLpInfo.initialWethAdded,
            localVars.initialTokenMatchOld
        );

        // new token amount for bootstrap if no swaps would have occured
        (localVars.tokenAmountForPresaleNew, localVars.tokenAmountForAmmNew) = _tokenAmountsForLiquidityBootstrap(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        // team needs to add min 10% more tokens than the initial lp to take over
        localVars.minTokenNeeded =
            ((localVars.tokenAmountForPresaleOld + localVars.tokenAmountForAmmOld) * 11000) / 10000;

        if ((localVars.tokenAmountForAmmNew + localVars.tokenAmountForPresaleNew) < localVars.minTokenNeeded) {
            revert GoatErrors.InsufficientTakeoverTokenAmount();
        }

        localVars.reserveEth = _reserveEth;

        // Actual token amounts needed if the reserves have updated after initial lp mint
        (localVars.tokenAmountForPresaleNew, localVars.tokenAmountForAmmNew) = _tokenAmountsForLiquidityBootstrap(
            initParams.virtualEth, initParams.bootstrapEth, localVars.reserveEth, initParams.initialTokenMatch
        );
        localVars.reserveToken = _reserveToken;

        // amount of tokens transferred by the new team
        uint256 tokenAmountIn = IERC20(_token).balanceOf(address(this)) - localVars.reserveToken;

        if (
            tokenAmountIn
                < (
                    localVars.tokenAmountForPresaleOld + localVars.tokenAmountForAmmOld - localVars.reserveToken
                        + localVars.tokenAmountForPresaleNew + localVars.tokenAmountForAmmNew
                )
        ) {
            revert GoatErrors.IncorrectTokenAmount();
        }

        localVars.pendingLiquidityFees = _pendingLiquidityFees;
        localVars.pendingProtocolFees = _pendingProtocolFees;

        // amount of weth transferred by the new team
        uint256 wethAmountIn = IERC20(_weth).balanceOf(address(this)) - localVars.reserveEth
            - localVars.pendingLiquidityFees - localVars.pendingProtocolFees;

        if (wethAmountIn < localVars.reserveEth) {
            revert GoatErrors.IncorrectWethAmount();
        }

        _handleTakeoverTransfers(
            IERC20(_weth), IERC20(_token), initialLpInfo.liquidityProvider, localVars.reserveEth, localVars.reserveToken
        );

        uint256 lpBalance = balanceOf(initialLpInfo.liquidityProvider);
        _burn(initialLpInfo.liquidityProvider, lpBalance);

        // new lp balance
        lpBalance = Math.sqrt(uint256(initParams.virtualEth) * initParams.initialTokenMatch) - MINIMUM_LIQUIDITY;
        _mint(to, lpBalance);

        _updateStateAfterTakeover(
            initParams.virtualEth,
            initParams.bootstrapEth,
            initParams.initialTokenMatch,
            wethAmountIn,
            tokenAmountIn,
            lpBalance,
            to,
            initParams.initialEth
        );
    }

    /**
     * @notice Updates contract state following a successful pool takeover.
     * @dev Resets pool parameters with new values provided by the
     *  new liquidity provider and updates the pool's reserves and initial lp info.
     * @param virtualEth The new virtual Ether amount for the pool.
     * @param bootstrapEth The new bootstrap Ether amount for the pool.
     * @param initialTokenMatch The new initial token match amount for the pool.
     * @param finalReserveWeth The final WETH reserve amount after the takeover.
     * @param finalReserveToken The final token reserve amount after the takeover.
     * @param liquidity The liquidity amount minted to the new liquidity provider.
     * @param newLp The address of the new liquidity provider.
     * @param initialWeth The initial WETH amount added by the new liquidity provider.
     * Post-Conditions:
     * - Sets the pool's virtual ETH, bootstrap ETH, and initial token match to the new values.
     * - Updates the initial liquidity provider information with the new liquidity provider's details.
     * - Updates the pool's WETH and token reserves to reflect the final state after the takeover.
     */
    function _updateStateAfterTakeover(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialTokenMatch,
        uint256 finalReserveWeth,
        uint256 finalReserveToken,
        uint256 liquidity,
        address newLp,
        uint256 initialWeth
    ) internal {
        _virtualEth = uint112(virtualEth);
        _bootstrapEth = uint112(bootstrapEth);
        _initialTokenMatch = uint112(initialTokenMatch);

        // delete initial lp info
        delete _initialLPInfo;

        // update lp info as if it was first mint
        _updateInitialLpInfo(liquidity, initialWeth, newLp, false, false);

        _update(finalReserveWeth, finalReserveToken, false);
    }

    /**
     * @notice Handles asset transfers during a pool takeover.
     * @dev Transfers WETH and tokens back to the initial liquidity provider (lp) with a penalty
     *      for potential frontrunners. This mechanism aims to discourage malicious frontrunning by
     *      applying 5% penalty to the WETH amount being transferred.
     * @param weth The WETH token contract.
     * @param token The token contract associated with the pool.
     * @param lp The address of the initial liquidity provider to receive the transferred assets.
     * @param wethAmount Total amount of weth to be transferred. (lp share + penalty)
     * @param tokenAmount The amount of tokens to be transferred to the lp.
     */
    function _handleTakeoverTransfers(IERC20 weth, IERC20 token, address lp, uint256 wethAmount, uint256 tokenAmount)
        internal
    {
        if (wethAmount != 0) {
            // Malicious frontrunners can create cheaper pools buy tokens cheap
            // and make it costly for the teams to take over. So, we need to have penalty
            // for the frontrunner.
            uint256 penalty = (wethAmount * 5) / 100;
            // actual amount to transfer
            wethAmount -= penalty;
            weth.safeTransfer(lp, wethAmount);
            weth.safeTransfer(IGoatV1Factory(factory).treasury(), penalty);
        }
        token.safeTransfer(lp, tokenAmount);
    }

    /**
     * @notice Withdraws the fees accrued to the address `to`.
     * @dev Transfers the accumulated fees in weth of the liquidty proivder
     * @param to The address to which the fees will be withdrawn.
     * Post-conditions:
     * - The `feesPerTokenPaid` should reflect the latest `feesPerTokenStored` value for the address `to`.
     * - The `lpFees` owed to the address `to` are reset to 0.
     * - The `_pendingLiquidityFees` state variable is decreased by the amount of fees withdrawn.
     */
    function withdrawFees(address to) external {
        uint256 totalFees = _earned(to, feesPerTokenStored);

        if (totalFees != 0) {
            feesPerTokenPaid[to] = feesPerTokenStored;
            lpFees[to] = 0;
            _pendingLiquidityFees -= uint112(totalFees);
            IERC20(_weth).safeTransfer(to, totalFees);
        }
        // is there a need to check if weth balance is in sync with reserve and fees?
    }

    /* ----------------------------- INTERNAL FUNCTIONS ----------------------------- */

    /**
     * @notice Updates the reserve amounts.
     */
    function _update(uint256 balanceEth, uint256 balanceToken, bool deductFees) internal {
        // Update token reserves and other necessary data
        if (deductFees) {
            _reserveEth = uint112(balanceEth - (_pendingLiquidityFees + _pendingProtocolFees));
        } else {
            _reserveEth = uint112(balanceEth);
        }
        _reserveToken = uint112(balanceToken);
    }

    /**
     * @notice Updates the initial liquidity provider information.
     * @dev This function updates the `_initialLPInfo` storage variable based on the provided parameters.
     * @param liquidity The amount of liquidity to update.
     * @param wethAmt The amount of WETH added by the initial liquidity provider.
     * @param lp The address of the liquidity provider.
     * @param isBurn A flag indicating whether the update is a burn operation.
     * @param internalBurn A flag indicating whether the update is because or pool transition (from presale to amm)
     */
    function _updateInitialLpInfo(uint256 liquidity, uint256 wethAmt, address lp, bool isBurn, bool internalBurn)
        internal
    {
        GoatTypes.InitialLPInfo memory info = _initialLPInfo;

        if (internalBurn) {
            // update from from swap when pool converts to an amm
            info.fractionalBalance = uint112(liquidity) / 4;
        } else if (isBurn) {
            if (lp == info.liquidityProvider) {
                info.lastWithdraw = uint32(block.timestamp);
                info.withdrawalLeft -= 1;
            }
        } else {
            info.fractionalBalance = uint112(((info.fractionalBalance * info.withdrawalLeft) + liquidity) / 4);
            info.withdrawalLeft = 4;
            info.liquidityProvider = lp;
            if (wethAmt != 0) {
                info.initialWethAdded = uint104(wethAmt);
            }
        }

        // Update initial liquidity provider info
        _initialLPInfo = info;
    }

    /**
     * @dev Calculates and handles the distribution of fees for each swap transaction.
     * Fees are updated based on the amount of WETH entering or exiting the pool,
     *  - 99 bps fees are collected of which 60% goes to the treasury
     *  - Allocates 40% to LPs (added to reserves during presale, otherwise distributed per SNX logic).
     *  - If protocol fees exceed a predefined threshold, they are transferred to the treasury.
     * @param amountWethIn amount of weth entering the pool (0 if it's a sell)
     * @param amountWethOut amount of weth exiting the pool (0 if it's a buy)
     * @param isPresale boolean indicating if the swap is in the presale period.
     * @return feesCollected 99bps on the amount of weth entering or exiting the pool.
     * @return feesLp amount of lp fees share
     * Post-conditions:
     * - Updates the `_pendingProtocolFees` by 60% of the fees collected or resets it to 0.
     * - Updates the `_feesPerTokenStored` if pool is not in presale.
     */
    function _handleFees(uint256 amountWethIn, uint256 amountWethOut, bool isPresale)
        internal
        returns (uint256 feesCollected, uint256 feesLp)
    {
        // here either amountWethIn or amountWethOut will be zero

        // fees collected will be 99 bps of the weth amount
        if (amountWethIn != 0) {
            feesCollected = (amountWethIn * 99) / 10000;
        } else {
            feesCollected = (amountWethOut * 10000) / 9901 - amountWethOut;
        }
        // lp fess is fixed 40% of the fees collected of total 99 bps
        feesLp = (feesCollected * 40) / 100;

        uint256 pendingProtocolFees = _pendingProtocolFees;

        // lp fees only updated if it's not a presale
        if (!isPresale) {
            _pendingLiquidityFees += uint112(feesLp);
            // update fees per token stored
            feesPerTokenStored += uint184((feesLp * 1e18) / totalSupply());
        }

        pendingProtocolFees += feesCollected - feesLp;

        IGoatV1Factory _factory = IGoatV1Factory(factory);
        uint256 minCollectableFees = _factory.minimumCollectableFees();

        if (pendingProtocolFees > minCollectableFees) {
            IERC20(_weth).safeTransfer(_factory.treasury(), pendingProtocolFees);
            pendingProtocolFees = 0;
        }
        _pendingProtocolFees = uint72(pendingProtocolFees);
    }

    /**
     * @dev Handles (MEV) checks to mitigate front-running and sandwich attacks.
     *      Only allows trade to occur in one direction after first trade.
     *      sell -> buy -> buy -> buy ... is allowed
     *      buy -> sell -> sell -> sell ... is allowed
     *      buy -> buy -> sell -> sell ... is not allowed
     *      sell -> sell -> buy -> buy ... is not allowed
     * @param isBuy A boolean indicating nature of the trade (true for buy, false for sell).
     * Post-conditions:
     * - Updates the `_lastTrade` state variable to:-
     *   - current timestamp if it is first trade in the block.
     *   - current timestamp + 1 if trade after first is buy.
     *   - current timestamp + 2 if trade after first is seel.
     */
    function _handleMevCheck(bool isBuy) internal {
        // @note  Known bug for chains that have block time less than 2 second
        uint8 swapType = isBuy ? 1 : 2;
        uint32 timestamp = uint32(block.timestamp);
        uint32 lastTrade = _lastTrade;
        if (lastTrade < timestamp) {
            lastTrade = timestamp;
        } else if (lastTrade == timestamp) {
            lastTrade = timestamp + swapType;
        } else if (lastTrade == timestamp + 1) {
            if (swapType == 2) {
                revert GoatErrors.MevDetected1();
            }
        } else if (lastTrade == timestamp + 2) {
            if (swapType == 1) {
                revert GoatErrors.MevDetected2();
            }
        } else {
            // make it bullet proof
            revert GoatErrors.MevDetected();
        }
        // update last trade
        _lastTrade = lastTrade;
    }

    /**
     * @dev updates presale balances of the swappers
     * @param user address of the user
     * @param amount amount of tokens bought or sold
     * @param isBuy boolean indicating type of swap (true for buy, false for sell)
     */
    function _updatePresale(address user, uint256 amount, bool isBuy) internal {
        //
        if (isBuy) {
            unchecked {
                _presaleBalances[user] += amount;
            }
        } else {
            _presaleBalances[user] -= amount;
        }
    }

    /**
     * @dev Burns virtual liquidity and converts the pool to an AMM.
     * @param actualEthReserve The actual reserve of ETH in the pool.
     * @param actualTokenReserve The actual reserve of tokens in the pool.
     */
    function _updateLiquidityAndConvertToAmm(uint256 actualEthReserve, uint256 actualTokenReserve) internal {
        address initialLiquidityProvider = _initialLPInfo.liquidityProvider;

        uint256 initialLpBalance = balanceOf(initialLiquidityProvider);

        uint256 liquidity = Math.sqrt(actualTokenReserve * actualEthReserve) - MINIMUM_LIQUIDITY;

        if (liquidity < initialLpBalance) {
            uint256 liquidityToBurn = initialLpBalance - liquidity;
            _burn(initialLiquidityProvider, liquidityToBurn);
        } else {
            uint256 liquidityToMint = liquidity - initialLpBalance;
            _mint(initialLiquidityProvider, liquidityToMint);
        }

        _updateInitialLpInfo(liquidity, 0, initialLiquidityProvider, false, true);

        _vestingUntil = uint32(block.timestamp + VESTING_PERIOD);
    }

    /**
     * @dev Checks for k invariant of the pool at AMM phase and converts the pool to an AMM.
     * @param reserveEth The actual reserve of ETH in the pool.
     * @param reserveToken The actual reserve of tokens in the pool.
     */
    function _checkAndConvertPool(uint256 reserveEth, uint256 reserveToken) internal {
        uint256 tokenAmtForAmm;
        uint256 kForAmm;

        (, tokenAmtForAmm) = _tokenAmountsForLiquidityBootstrap(_virtualEth, _bootstrapEth, 0, _initialTokenMatch);
        kForAmm = _bootstrapEth * tokenAmtForAmm;

        uint256 actualK = reserveEth * reserveToken;
        if (actualK < kForAmm) {
            revert GoatErrors.KInvariant();
        }
        _updateLiquidityAndConvertToAmm(reserveEth, reserveToken);
    }

    /**
     * @dev Calculates the virtual token amount using initial parameters of the pool
     * @param virtualEth The virtual reserve of ETH in the pool.
     * @param bootstrapEth The amount of ETH needed to convert pool into an AMM.
     * @param initialTokenMatch The initial token match of the pool (real+virtual) amount.
     */
    function _getVirtualTokenAmt(uint256 virtualEth, uint256 bootstrapEth, uint256 initialTokenMatch)
        internal
        pure
        returns (uint256 virtualToken)
    {
        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) =
            _tokenAmountsForLiquidityBootstrap(virtualEth, bootstrapEth, 0, initialTokenMatch);

        virtualToken = initialTokenMatch - (tokenAmtForPresale + tokenAmtForAmm);
    }

    /**
     * @dev Calculates the token amounts for liquidity bootstrap. Tokens needed for presale and AMM.
     * @param virtualEth The virtual reserve of ETH in the pool.
     * @param bootstrapEth The amount of ETH needed to convert pool into an AMM.
     * @param initialEth The initial reserve of ETH in the pool.
     * @param initialTokenMatch The initial token match of the pool (real+virtual) amount.
     */
    function _tokenAmountsForLiquidityBootstrap(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) internal pure returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) {
        uint256 k = virtualEth * initialTokenMatch;
        tokenAmtForPresale = initialTokenMatch - (k / (virtualEth + bootstrapEth));
        uint256 totalEth = virtualEth + bootstrapEth;
        tokenAmtForAmm = (k * bootstrapEth) / (totalEth * totalEth);

        if (initialEth != 0) {
            uint256 numerator = (initialEth * initialTokenMatch);
            uint256 denominator = virtualEth + initialEth;
            uint256 tokenAmountOut = numerator / denominator;
            tokenAmtForPresale -= tokenAmountOut;
        }
    }

    /**
     * @notice Handles lock and initial liquidity provider checks.
     * @dev Called before any token transfers and performs the following checks and updates:
     *      1. Prevents transfers to the initial liquidity provider's address.
     *      2. For transfers from the initial liquidity provider:
     *          - Prevents transfers to addresses other than the pair contract.
     *          - Enforces a 1-week withdrawal cooldown period.
     *          - Validates withdrawal amounts based on the remaining withdrawal count and fractional balance.
     *      3. Prevents transfers if the sender's funds are locked.
     *      4. Updates fee rewards for both the sender and receiver addresses.
     * @param from The address sending the lp tokens.
     * @param to The address receiving the lp tokens.
     * @param amount The amount of lp tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        GoatTypes.InitialLPInfo memory lpInfo = _initialLPInfo;
        if (to == lpInfo.liquidityProvider) revert GoatErrors.TransferToInitialLpRestricted();
        uint256 timestamp = block.timestamp;
        if (from == lpInfo.liquidityProvider) {
            // initial lp can't transfer funds to other addresses
            if (to != address(this)) revert GoatErrors.TransferFromInitialLpRestricted();
            if (_vestingUntil == _MAX_UINT32) revert GoatErrors.PresalePeriod();

            // check for coldown period
            if ((timestamp - 1 weeks) < lpInfo.lastWithdraw) {
                revert GoatErrors.WithdrawalCooldownActive();
            }

            // we only check for fractional balance if withdrawalLeft is not 1
            // because last withdraw should be allowed to remove the dust amount
            // as well that's not in the fractional balance that's caused due
            // to division by 4
            if (lpInfo.withdrawalLeft == 1) {
                uint256 remainingLpBalance = balanceOf(lpInfo.liquidityProvider);
                if (amount != remainingLpBalance) {
                    revert GoatErrors.ShouldWithdrawAllBalance();
                }
            } else {
                if (amount > lpInfo.fractionalBalance) {
                    revert GoatErrors.BurnLimitExceeded();
                }
            }
            _updateInitialLpInfo(amount, 0, _initialLPInfo.liquidityProvider, true, false);
        }

        if (_locked[from] > timestamp) {
            revert GoatErrors.LiquidityLocked();
        }

        // Update fee rewards for both sender and receiver
        _updateFeeRewards(from);
        if (to != address(this)) {
            _updateFeeRewards(to);
        }
    }

    /**
     * @notice Updates the fee rewards for a given liquidity provider.
     * @dev This function calculates and updates the fee rewards earned by the liquidity provider.
     * @param lp The address of the liquidity provider.
     */
    function _updateFeeRewards(address lp) internal {
        // save for multiple reads
        uint256 _feesPerTokenStored = feesPerTokenStored;
        lpFees[lp] = _earned(lp, _feesPerTokenStored);
        feesPerTokenPaid[lp] = _feesPerTokenStored;
    }

    /**
     * @notice Calculates the earned fee rewards for a given liquidity provider.
     * @dev This function calculates the fee rewards accrued by a liquidity provider based on their
     *      token balance and the difference between the current `feesPerTokenStored` and the
     *      `feesPerTokenPaid` for the liquidity provider. It returns the sum of the previously
     *      stored fees and the newly accrued fees.
     * @param lp The address of the liquidity provider.
     * @param _feesPerTokenStored The current value of `feesPerTokenStored`.
     * @return The total earned fee rewards for the given liquidity provider.
     */
    function _earned(address lp, uint256 _feesPerTokenStored) internal view returns (uint256) {
        uint256 feesPerToken = _feesPerTokenStored - feesPerTokenPaid[lp];
        uint256 feesAccrued = (balanceOf(lp) * feesPerToken) / 1e18;
        return lpFees[lp] + feesAccrued;
    }

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function earned(address lp) external view returns (uint256) {
        return _earned(lp, feesPerTokenStored);
    }

    function vestingUntil() external view returns (uint32 vestingUntil_) {
        vestingUntil_ = _vestingUntil;
    }

    function getStateInfoForPresale()
        external
        view
        returns (
            uint112 reserveEth,
            uint112 reserveToken,
            uint112 virtualEth,
            uint112 initialTokenMatch,
            uint112 bootstrapEth,
            uint256 virtualToken
        )
    {
        reserveEth = _reserveEth;
        reserveToken = _reserveToken;
        virtualEth = _virtualEth;
        initialTokenMatch = _initialTokenMatch;
        bootstrapEth = _bootstrapEth;
        virtualToken = _getVirtualTokenAmt(virtualEth, bootstrapEth, initialTokenMatch);
    }

    function getStateInfoAmm() external view returns (uint112, uint112) {
        return (_reserveEth, _reserveToken);
    }

    function getInitialLPInfo() external view returns (GoatTypes.InitialLPInfo memory) {
        return _initialLPInfo;
    }

    function getPresaleBalance(address user) external view returns (uint256) {
        return _presaleBalances[user];
    }

    function lockedUntil(address user) external view returns (uint32) {
        return _locked[user];
    }

    function getFeesPerTokenStored() external view returns (uint256) {
        return feesPerTokenStored;
    }

    function getPendingLiquidityFees() external view returns (uint112) {
        return _pendingLiquidityFees;
    }

    function getPendingProtocolFees() external view returns (uint72) {
        return _pendingProtocolFees;
    }
}
