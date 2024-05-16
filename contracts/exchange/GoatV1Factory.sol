// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GoatV1Pair} from "./GoatV1Pair.sol";
import {GoatTypes} from "../library/GoatTypes.sol";
import {GoatErrors} from "../library/GoatErrors.sol";

/**
 * @title Goat Trading Factory
 * @notice Factory contract for creating Goat Trading Pair contracts.
 * @dev This contract is used to create Goat Trading Pair contracts.
 * @author Goat Trading -- Chiranjibi Poudyal, Robert M.C. Forster
 */
contract GoatV1Factory {
    /// @notice The address of the wrapped native token (e.g., WETH).
    address public immutable weth;

    /// @notice The name of wrapped native token. (e.g. Wrapped Ether)
    string internal baseName;

    /// @notice The address of the treasury.
    address public treasury;

    /// @notice The address of the pending treasury.
    address public pendingTreasury;

    /// @notice Mapping of token addresses to their corresponding trading pair addresses.
    mapping(address => address) internal pools;

    /// @notice The minimum collectable fees in the native token (e.g., ETH).
    uint256 public minimumCollectableFees = 0.1 ether;

    /// @notice Emitted when a new trading pair is created.
    event PairCreated(address indexed weth, address indexed token, address pair);

    /// @notice Emitted when a trading pair is removed.
    event PairRemoved(address indexed token, address pair);

    /**
     * @notice Constructs the GoatV1Factory contract and migrates
     *     the trading pairs from the previous version.
     * @param _weth The address of the wrapped native token (e.g., WETH).
     * @param _tokens The addresses of the tokens to pair with the wrapped native token.
     * @param _pairs The addresses of the trading pair contracts.
     */
    constructor(address _weth, address[] memory _tokens, address[] memory _pairs) {
        weth = _weth;
        baseName = IERC20Metadata(_weth).name();
        treasury = msg.sender;
        uint256 length = _pairs.length;
        if (length != _tokens.length) {
            revert GoatErrors.LengthMismatch();
        }
        for (uint256 i = 0; i < length; i++) {
            pools[_tokens[i]] = _pairs[i];
            emit PairCreated(_weth, _tokens[i], _pairs[i]);
        }
    }

    /**
     * @notice Creates a new trading pair contract.
     * @param token The address of the token to pair with the wrapped native token.
     * @param params The initialization parameters for the trading pair.
     * @return The address of the newly created trading pair contract.
     */
    function createPair(address token, GoatTypes.InitParams memory params) external returns (address) {
        if (params.bootstrapEth == 0 || params.virtualEth == 0 || params.initialTokenMatch == 0) {
            revert GoatErrors.InvalidParams();
        }
        if (pools[token] != address(0)) {
            revert GoatErrors.PairExists();
        }
        if (token == weth) {
            revert GoatErrors.CannnotPairWithBaseAsset();
        }
        GoatV1Pair pair = new GoatV1Pair();
        pair.initialize(token, weth, baseName, params);
        pools[token] = address(pair);
        emit PairCreated(token, weth, address(pair));
        return address(pair);
    }

    /* ----------------------------- PRIVILEGED FUNCTIONS ----------------------------- */

    /**
     * @notice Removes a trading pair contract.
     * @param token The address of the token paired with the wrapped native token.
     */
    function removePair(address token) external {
        address pair = pools[token];
        if (msg.sender != pair) {
            revert GoatErrors.Forbidden();
        }
        delete pools[token];

        emit PairRemoved(token, pair);
    }

    /**
     * @notice Sets the pending treasury address.
     * @param _pendingTreasury The address of the pending treasury.
     */
    function setTreasury(address _pendingTreasury) external {
        if (msg.sender != treasury) {
            revert GoatErrors.Forbidden();
        }
        pendingTreasury = _pendingTreasury;
    }

    /**
     * @notice Accepts the pending treasury address and updates the current treasury.
     */
    function acceptTreasury() external {
        if (msg.sender != pendingTreasury) {
            revert GoatErrors.Forbidden();
        }
        pendingTreasury = address(0);
        treasury = msg.sender;
    }

    /**
     * @notice Sets the minimum collectable fees.
     * @param _minimumCollectibleFees The new minimum collectable fees value.
     */
    function setFeeToTreasury(uint256 _minimumCollectibleFees) external {
        if (msg.sender != treasury) {
            revert GoatErrors.Forbidden();
        }
        minimumCollectableFees = _minimumCollectibleFees;
    }

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */

    /**
     * @notice Retrieves the address of the trading pair contract for a given token.
     * @param token The address of the token paired with wrapped native token.
     * @return The address of the trading pair contract.
     */
    function getPool(address token) external view returns (address) {
        return pools[token];
    }

    /**
     * @notice Retrives the address of pair contract (compatible with uni v2)
     * @param token0 The address of the first token.
     * @param token1 The address of the second token.
     * @return pair The address of the trading pair contract.
     */
    function getPair(address token0, address token1) external view returns (address pair) {
        if (token0 == weth) {
            pair = pools[token1];
        } else if (token1 == weth) {
            pair = pools[token0];
        }
    }
}
