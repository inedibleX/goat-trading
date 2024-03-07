// SPDX-License-Identifier: MIT
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

        _update(balanceEth, balanceToken, false);

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

        uint256 balanceEth = IERC20(_weth).balanceOf(address(this));
        uint256 balanceToken = IERC20(_token).balanceOf(address(this));

        uint256 totalSupply_ = totalSupply();
        amountWeth = (liquidity * balanceEth) / totalSupply_;
        amountToken = (liquidity * balanceToken) / totalSupply_;
        if (amountWeth == 0 || amountToken == 0) {
            revert GoatErrors.InsufficientLiquidityBurned();
        }

        _updateFeeRewards(to);
        _burn(address(this), liquidity);

        // Transfer liquidity tokens to the user
        IERC20(_weth).safeTransfer(to, amountWeth);
        IERC20(_token).safeTransfer(to, amountToken);
        balanceEth = IERC20(_weth).balanceOf(address(this));
        balanceToken = IERC20(_token).balanceOf(address(this));

        _update(balanceEth, balanceToken, false);

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
        if (swapVars.isPresale && swapVars.finalReserveEth >= swapVars.bootstrapEth) {
            // at this point pool should be changed to an AMM
            _checkAndConvertPool(swapVars.finalReserveEth, swapVars.finalReserveToken);
        } else {
            // check for K
            swapVars.initialTokenMatch = _initialTokenMatch;
            swapVars.virtualEth = _virtualEth;

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
        // presale lp fees should go to reserve eth
        if (swapVars.isPresale) {
            swapVars.finalReserveEth += swapVars.lpFeesCollected;
        }
        _update(swapVars.finalReserveEth, swapVars.finalReserveToken, true);
        // TODO: Emit swap event with similar details to uniswap v2 after audit
        // @note what should be the swap amount values for emit here? Should it include fees?
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
            uint256 virtualToken = _getVirtualToken(virtualEth, _bootstrapEth, initialTokenMatch);
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
            _tokenAmountsForLiquidityBootstrap(_virtualEth, bootstrapEth, reserveEth, _initialTokenMatch);

        IERC20 token = IERC20(_token);
        uint256 poolTokenBalance = token.balanceOf(address(this));

        uint256 amountToTransferBack = poolTokenBalance - tokenAmtForAmm;
        // transfer excess token to the initial liquidity provider
        token.safeTransfer(initialLiquidityProvider, amountToTransferBack);

        if (reserveEth != 0) {
            _burnLiquidityAndConvertToAmm(reserveEth, tokenAmtForAmm);
            // update bootstrap eth because original bootstrap eth was not met and
            // eth we raised until this point should be considered as bootstrap eth
            _bootstrapEth = uint112(bootstrapEth);
            _update(reserveEth, tokenAmtForAmm, true);
        } else {
            IGoatV1Factory(factory).removePair(_token);
        }
    }

    /**
     * @notice Allows a team to take over a pool from malicious actors.
     * @dev Prevents malicious actors from griefing the pool by setting unfavorable
     *   initial conditions. It requires the new team to match the initial liquidity
     *   provider's WETH amount and exceed their token contribution by at least 10%.
     *   This function also resets the pool's initial liquidity parameters.
     * @param tokenAmount The amount of tokens being added to take over the pool.
     * @param initParams The new initial parameters for the pool.
     * Requirements:
     * - Pool must be in presale period.
     * - `initParams.initialEth` must exactly match the initial liquidity provider's WETH contribution.
     * - The `tokenAmount` must be at least 10% greater and equal to bootstrap token needed for new params.
     * Reverts:
     * - If the pool has already transitioned to an AMM.
     * - If `tokenAmount` is less than the minimum required to take over the pool.
     * - If `tokenAmount` does not match the new combined token amount requirements.
     * Post-Conditions:
     * - Transfers the amount of token and weth deposited by initial lp to it's address.
     * - Burns the initial liquidity provider's tokens and
     *   mints new liquidity tokens to the new team based on the new `initParams`.
     * - Resets the pool's initial liquidity parameters to the new `initParams`.
     * - Updates the pool's reserves to reflect the new token balance.
     */
    function takeOverPool(uint256 tokenAmount, GoatTypes.InitParams memory initParams) external {
        if (_vestingUntil != _MAX_UINT32) {
            revert GoatErrors.ActionNotAllowed();
        }

        GoatTypes.InitialLPInfo memory initialLpInfo = _initialLPInfo;

        if (initParams.initialEth != initialLpInfo.initialWethAdded) {
            revert GoatErrors.IncorrectWethAmount();
        }

        GoatTypes.LocalVariables_TakeOverPool memory localVars;
        address to = msg.sender;
        localVars.virtualEthOld = _virtualEth;
        localVars.bootstrapEthOld = _bootstrapEth;
        localVars.initialTokenMatchOld = _initialTokenMatch;
        // @note is there a need to check old init params and new init params?
        (localVars.tokenAmountForPresaleOld, localVars.tokenAmountForAmmOld) = _tokenAmountsForLiquidityBootstrap(
            localVars.virtualEthOld,
            localVars.bootstrapEthOld,
            initialLpInfo.initialWethAdded,
            localVars.initialTokenMatchOld
        );

        // team needs to add min 10% more tokens than the initial lp to take over
        localVars.minTokenNeeded =
            ((localVars.tokenAmountForPresaleOld + localVars.tokenAmountForAmmOld) * 11000) / 10000;
        if (tokenAmount < localVars.minTokenNeeded) {
            revert GoatErrors.InsufficientTakeoverTokenAmount();
        }

        // new token amount for presale if initParams are changed
        (localVars.tokenAmountForPresaleNew, localVars.tokenAmountForAmmNew) = _tokenAmountsForLiquidityBootstrap(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );

        if (tokenAmount != (localVars.tokenAmountForPresaleNew + localVars.tokenAmountForAmmNew)) {
            revert GoatErrors.IncorrectTokenAmount();
        }

        IERC20(_token).safeTransferFrom(to, address(this), tokenAmount);
        if (initParams.initialEth != 0) {
            // Transfer weth directly to the initial lp
            IERC20(_weth).safeTransferFrom(to, initialLpInfo.liquidityProvider, initialLpInfo.initialWethAdded);
        }

        uint256 lpBalance = balanceOf(initialLpInfo.liquidityProvider);
        _burn(initialLpInfo.liquidityProvider, lpBalance);

        delete _initialLPInfo;
        // new lp balance
        lpBalance = Math.sqrt(uint256(initParams.virtualEth) * initParams.initialTokenMatch) - MINIMUM_LIQUIDITY;
        _mint(to, lpBalance);
        _updateInitialLpInfo(lpBalance, initParams.initialEth, to, false, false);

        // transfer excess token to the initial liquidity provider
        IERC20(_token).safeTransfer(
            initialLpInfo.liquidityProvider, (localVars.tokenAmountForAmmOld + localVars.tokenAmountForPresaleOld)
        );
        // update init vars
        _virtualEth = uint112(initParams.virtualEth);
        _bootstrapEth = uint112(initParams.bootstrapEth);
        _initialTokenMatch = initParams.initialTokenMatch;

        //@note final balance check is this necessary?
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        // update reserves
        _update(_reserveEth, tokenBalance, false);
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

    function _update(uint256 balanceEth, uint256 balanceToken, bool fromSwap) internal {
        // Update token reserves and other necessary data
        if (fromSwap) {
            _reserveEth = uint112(balanceEth);
            _reserveToken = uint112(balanceToken);
        } else {
            _reserveEth = uint112(balanceEth - (_pendingLiquidityFees + _pendingProtocolFees));
            _reserveToken = uint112(balanceToken);
        }
    }

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
        address treasury = _factory.treasury();

        if (pendingProtocolFees > minCollectableFees) {
            IERC20(_weth).safeTransfer(treasury, pendingProtocolFees);
            pendingProtocolFees = 0;
        }
        _pendingProtocolFees = uint72(pendingProtocolFees);
    }

    function _handleMevCheck(bool isBuy) internal returns (uint32 lastTrade) {
        // @note  Known bug for chains that have block time less than 2 second
        uint8 swapType = isBuy ? 1 : 2;
        uint32 timestamp = uint32(block.timestamp);
        lastTrade = _lastTrade;
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

    function _burnLiquidityAndConvertToAmm(uint256 actualEthReserve, uint256 actualTokenReserve) internal {
        address initialLiquidityProvider = _initialLPInfo.liquidityProvider;

        uint256 initialLPBalance = balanceOf(initialLiquidityProvider);

        uint256 liquidity = Math.sqrt(actualTokenReserve * actualEthReserve) - MINIMUM_LIQUIDITY;

        uint256 liquidityToBurn = initialLPBalance - liquidity;

        _updateInitialLpInfo(liquidity, 0, initialLiquidityProvider, false, true);
        _burn(initialLiquidityProvider, liquidityToBurn);
        _vestingUntil = uint32(block.timestamp + VESTING_PERIOD);
    }

    function _checkAndConvertPool(uint256 initialReserveEth, uint256 initialReserveToken) internal {
        uint256 tokenAmtForAmm;
        uint256 kForAmm;
        if (initialReserveEth >= _bootstrapEth) {
            (, tokenAmtForAmm) = _tokenAmountsForLiquidityBootstrap(_virtualEth, _bootstrapEth, 0, _initialTokenMatch);
            kForAmm = _bootstrapEth * tokenAmtForAmm;
        }

        uint256 actualK = initialReserveEth * initialReserveToken;
        if (actualK < kForAmm) {
            revert GoatErrors.KInvariant();
        }
        _burnLiquidityAndConvertToAmm(initialReserveEth, initialReserveToken);
    }

    function _getVirtualToken(uint256 virtualEth, uint256 bootstrapEth, uint256 initialTokenMatch)
        internal
        pure
        returns (uint256 virtualToken)
    {
        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) =
            _tokenAmountsForLiquidityBootstrap(virtualEth, bootstrapEth, 0, initialTokenMatch);

        virtualToken = initialTokenMatch - (tokenAmtForPresale + tokenAmtForAmm);
    }

    function _tokenAmountsForLiquidityBootstrap(
        uint256 virtualEth,
        uint256 bootstrapEth,
        uint256 initialEth,
        uint256 initialTokenMatch
    ) internal pure returns (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) {
        uint256 k = virtualEth * initialTokenMatch;
        tokenAmtForPresale = initialTokenMatch - (k / (virtualEth + bootstrapEth));
        tokenAmtForAmm = ((k / (virtualEth + bootstrapEth)) / (virtualEth + bootstrapEth)) * bootstrapEth;

        if (initialEth != 0) {
            uint256 numerator = (initialEth * initialTokenMatch);
            uint256 denominator = virtualEth + initialEth;
            uint256 tokenAmountOut = numerator / denominator;
            if (tokenAmtForPresale > tokenAmountOut) {
                tokenAmtForPresale -= tokenAmountOut;
            } else {
                tokenAmtForPresale = 0;
            }
        }
    }

    /**
     * @dev handle initial liquidity provider checks and update locked if lp is transferred
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        GoatTypes.InitialLPInfo memory lpInfo = _initialLPInfo;
        if (to == lpInfo.liquidityProvider) revert GoatErrors.TransferToInitialLpRestricted();
        uint256 timestamp = block.timestamp;
        if (from == lpInfo.liquidityProvider) {
            // initial lp can't transfer funds to other addresses
            if (to != address(this)) revert GoatErrors.TransferFromInitialLpRestricted();

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
        _updateFeeRewards(to);
    }

    function _updateFeeRewards(address lp) internal {
        // save for multiple reads
        uint256 _feesPerTokenStored = feesPerTokenStored;
        lpFees[lp] = _earned(lp, _feesPerTokenStored);
        feesPerTokenPaid[lp] = _feesPerTokenStored;
    }

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
        virtualToken = _getVirtualToken(virtualEth, bootstrapEth, initialTokenMatch);
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
