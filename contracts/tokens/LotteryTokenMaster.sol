// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {LotteryToken} from "./LotteryToken.sol";
import {GoatLibrary} from "../library/GoatLibrary.sol";
import {GoatV1Factory} from "./../exchange/GoatV1Factory.sol";
import {GoatTypes} from "./../library/GoatTypes.sol";
import {TokenErrors} from "./library/TokenErrors.sol";

import {IGoatV1Pair} from "./../interfaces/IGoatV1Pair.sol";

interface ILotteryToken {
    function payWinner(address user, uint256 entryAmount) external;
}

/**
 * @title Lottery Token Master
 * @author Robert M.C. Forster
 * @notice This contract spawns lottery tokens and acts as the master for all lottery tokens.
 * @dev Here we use a commit/reveal scheme for randomization in which westore entries from users,
 *      then on every transfer of any token we check whether previous entries from any other token
 *      have won according to the win chance. We then call to the token telling it there's a winner.
 *      The more lottery tokens there are, the less likely it'll ever go 255 blocks without a transfer.
 *
 */
contract LotteryTokenMaster {
    uint256 internal constant _WEI = 1e18;

    address internal immutable _weth;

    // Chance of an entry winning the prize.
    // 1 == 0.0001%, 10,000 == 1%, 1,000,000 == 100%
    mapping(address => uint256) public winChances;

    Entry[] public entries;
    uint256 public entryIndex;
    uint256 public defaultUpkeepLoops;
    GoatV1Factory internal _factory;

    struct Entry {
        address user;
        // Full tokens being traded (traded amount / 1e18).
        uint96 tokenAmt;
        // Token that the user traded.
        address token;
        // Block where the "drawing" will take place.
        uint96 drawBlock;
    }

    constructor(address factory_, address weth_, uint256 defaultUpkeepLoops_) {
        _factory = GoatV1Factory(factory_);
        _weth = weth_;
        defaultUpkeepLoops = defaultUpkeepLoops_;
    }

    /* ********************************************* TOKEN CREATION ********************************************* */

    /**
     * @notice Factory function to create a lottery token.
     * @dev We don't want random contract being able to take advantage of our "keeping"
     *      so only valid lottery tokens should be able to interact.
     *
     */
    function createLotteryToken(
        string calldata _name,
        string calldata _symbol,
        uint256 _totalSupply,
        uint256 _winChance,
        uint256 _potPercent,
        uint256 _maxWinMultiplier,
        uint256 _buyTax,
        uint256 _sellTax,
        GoatTypes.InitParams calldata initParams
    ) external returns (address tokenAddress, address pool) {
        address owner = msg.sender;
        // Minimum chance 1 out of 1 million, maximum 1 out of 1
        if (_winChance > 1_000_000) {
            revert TokenErrors.InvalidWinChance();
        }
        LotteryToken token = new LotteryToken(_name, _symbol, _totalSupply, _potPercent, _maxWinMultiplier, _weth);
        tokenAddress = address(token);
        winChances[tokenAddress] = _winChance;

        // Create pool and add taxes to lottery
        pool = _factory.createPair(tokenAddress, initParams);
        (uint256 tokenAmtForPresale, uint256 tokenAmtForAmm) = GoatLibrary.getTokenAmountsForPresaleAndAmm(
            initParams.virtualEth, initParams.bootstrapEth, initParams.initialEth, initParams.initialTokenMatch
        );
        uint256 bootstrapTokenAmt = tokenAmtForPresale + tokenAmtForAmm;
        if (bootstrapTokenAmt < _totalSupply / 10) revert TokenErrors.TokenAmountForPoolTooLow();

        token.transfer(pool, bootstrapTokenAmt);
        IGoatV1Pair(pool).mint(owner);

        token.setTaxes(pool, _buyTax, _sellTax);
        token.transferTreasury(owner);
        token.transferOwnership(owner);

        // Send all tokens back to owner.
        uint256 remainingBalance = token.balanceOf(address(this));
        token.transfer(owner, remainingBalance);
    }

    /**
     * @notice Perform upkeep where we loop through entries to check for winners.
     * @dev This will be called on every lottery token transfer, but can also be called by keepers.
     * @param _loops Number of entries to check. If 0, it will do a default small amount.
     *
     */
    function upkeep(uint256 _loops) external {
        // Tokens will call with 0 so we can adjust default as needed.
        // Keepers can call with many more if necessary.
        if (_loops == 0) _loops = defaultUpkeepLoops;
        uint256 startIndex = entryIndex;
        uint256 entriesLength = entries.length;

        for (uint256 i = startIndex; i < _loops && i < entriesLength; i++) {
            Entry memory entry = entries[i];

            // Must have reached draw block. If not, end of checks.
            if (entry.drawBlock > block.number) return;

            // Check to make sure draw block isn't too old and if hash is a winner.
            bool winner = _checkWin(entry.token, entry.user, uint256(entry.drawBlock));

            // Tell the token to send up to 100x the token trade to the user.
            if (winner) _wonLottery(entry.token, entry.user, uint256(entry.tokenAmt));
        }
        if ((startIndex + _loops) < entriesLength) {
            entryIndex += _loops;
        } else {
            entryIndex = entriesLength;
        }
    }

    /**
     * @dev Token calls this when a trade is made to add an entry to their lottery.
     * @param _user User who made the trade.
     * @param _tokenAmt The amount of tokens to trade, which will then determine maximum win.
     *
     */
    function addEntry(address _user, uint256 _tokenAmt) external {
        // Don't want entries added that aren't from valid lottery coins.
        if (winChances[msg.sender] == 0) revert TokenErrors.EntryNotFromValidLotteryToken();
        // Push drawing to the next Ethereum epoch
        uint96 drawBlock = uint96(block.number + 32);
        uint96 fullTokens = uint96(_tokenAmt / _WEI);

        Entry memory entry = Entry(_user, fullTokens, msg.sender, drawBlock);
        entries.push(entry);
    }

    /* ********************************************* INTERNAL ********************************************* */

    /**
     * @notice Reveal part of the commit/reveal where we check whether a user has won according to blockhash.
     * @param _token The address of the lottery token that we're checking.
     * @param _user The address of the user whose entry we're checking.
     * @param _drawBlock Block number of the block where drawing is allowed.
     *
     */
    function _checkWin(address _token, address _user, uint256 _drawBlock) internal view returns (bool isWinner) {
        // We don't want pruning to give an unfair advantage, so we instead make all old transactions losers.
        // theoretically this could lead to unfair losses but with enough tokens it should never be a problem.
        // If there aren't many tokens, we should setup an upkeep bot until there are.
        if (_drawBlock < block.number - 255) return false;

        // "Randomization" - Use user address and blockhash so we don't have multiple winners on blocks.
        uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(_drawBlock), _user)));

        // Seed wins if the number modulo 1_000_000 is less than win chance.
        if (seed % 1_000_000 < winChances[_token]) isWinner = true;
    }

    /**
     * @notice If the trade is a winner, call the token contract with the maximum reward the token will get.
     * @param _token The token contract to call.
     * @param _user The user that has won the lottery.
     * @param _tokenAmt The amount of tokens that the user initially traded with.
     *
     */
    function _wonLottery(address _token, address _user, uint256 _tokenAmt) internal {
        // Need to first convert full token amount to token wei.
        uint256 fullTokens = _tokenAmt * _WEI;
        ILotteryToken(_token).payWinner(_user, fullTokens);
    }
}
