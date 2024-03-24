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
    address public immutable weth;
    string private baseName;
    address public treasury;
    address public pendingTreasury;
    mapping(address => address) public pools;
    uint256 public minimumCollectableFees = 0.1 ether;

    event PairCreated(address indexed weth, address indexed token, address pair);
    event PairRemoved(address indexed token, address pair);

    constructor(address _weth) {
        weth = _weth;
        baseName = IERC20Metadata(_weth).name();
        treasury = msg.sender;
    }

    function createPair(address token, GoatTypes.InitParams memory params) external returns (address) {
        // @note is there a need to have minimum values for theser params so it can't be frontrun?
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

    function removePair(address token) external {
        address pair = pools[token];
        if (msg.sender != pair) {
            revert GoatErrors.Forbidden();
        }
        delete pools[token];

        emit PairRemoved(token, pair);
    }

    function getPool(address token) external view returns (address) {
        return pools[token];
    }

    function setTreasury(address _pendingTreasury) external {
        if (msg.sender != treasury) {
            revert GoatErrors.Forbidden();
        }
        pendingTreasury = _pendingTreasury;
    }

    function acceptTreasury() external {
        if (msg.sender != pendingTreasury) {
            revert GoatErrors.Forbidden();
        }
        pendingTreasury = address(0);
        treasury = msg.sender;
    }

    function setFeeToTreasury(uint256 _minimumCollectibleFees) external {
        if (msg.sender != treasury) {
            revert GoatErrors.Forbidden();
        }
        minimumCollectableFees = _minimumCollectibleFees;
    }
}
