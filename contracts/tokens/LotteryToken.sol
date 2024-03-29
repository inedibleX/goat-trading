// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "./TaxToken.sol";

interface ILotteryToken {
    function payWinner(address user, uint256 entryAmount) external;
}

interface ILotteryMaster {
    function upkeep(uint256 loops) external;
    function addEntry(address user, uint256 entryAmount) external;
}

/**
 * @title Lottery Token Master
 * @author Robert M.C. Forster
 * @notice This contract spawns lottery tokens and acts as the master for all lottery tokens.
 * @dev Here we use a commit/reveal scheme for randomization in which westore entries from users, 
 *      then on every transfer of any token we check whether previous entries from any other token
 *      have won according to the win chance. We then call to the token telling it there's a winner.
 *      The more lottery tokens there are, the less likely it'll ever go 255 blocks without a transfer.
**/
contract LotteryTokenMaster {

    uint256 constant WEI = 1e18;

    // Chance of an entry winning the prize.
    // 1 == 0.0001%, 10,000 == 1%, 1,000,000 == 100%
    mapping(address => uint256) winChances;

    Entry[] entries;
    uint256 entryIndex;
    uint256 defaultUpkeepLoops;

    struct Entry {
        address user;
        // Full tokens being traded (traded amount / 1e18).
        uint96 tokenAmt;
        // Token that the user traded.
        address token;
        // Block where the "drawing" will take place.
        uint96 drawBlock;
    }

/* ********************************************* PUBLIC ********************************************* */

    /**
     * @notice Factory function to create a lottery token.
     * @dev We don't want random contract being able to take advantage of our "keeping"
     *      so only valid lottery tokens should be able to interact.
    **/
    function createLotteryToken(string calldata _name, string calldata _symbol, uint256 _totalSupply, uint256 _winChance, uint256 _potPercent, uint256 _maxWinMultiplier)
      external 
    returns (address token)
    {
        // We save tokenAmt in full tokens so let's add protection against small total supplies.
        require(1_000_000 * WEI <= _totalSupply );

        // Minimum chance 1 out of 1 million, maximum 1 out of 1
        require(0 < _winChance && _winChance < 1_000_000, "Invalid win chance.");
        token = address(new LotteryToken(_name, _symbol, _totalSupply, _potPercent, _maxWinMultiplier));
        winChances[token] = _winChance;
    }

    /**
     * @notice Perform upkeep where we loop through entries to check for winners.
     * @dev This will be called on every lottery token transfer, but can also be called by keepers.
     * @param _loops Number of entries to check. If 0, it will do a default small amount.
    **/
    function upkeep(uint256 _loops)
      external 
    {
        // Tokens will call with 0 so we can adjust default as needed.
        // Keepers can call with many more if necessary.
        if (_loops == 0) _loops = defaultUpkeepLoops;

        for (uint256 i = entryIndex; i < _loops && i < entries.length; i++) {
            Entry memory entry = entries[i];

            // Must have reached draw block. If not, end of checks.
            if (entry.drawBlock > block.number) return;

            // Check to make sure draw block isn't too old and if hash is a winner.
            bool winner = _checkWin(entry.token, entry.user, uint256(entry.drawBlock));

            // Tell the token to send up to 100x the token trade to the user.
            if (winner) _wonLottery(entry.token, entry.user, uint256(entry.tokenAmt));

            // Increment.
            entryIndex++;
        }
    }

    /**
     * @dev Token calls this when a trade is made to add an entry to their lottery.
     * @param _user User who made the trade.
     * @param _tokenAmt The amount of tokens to trade, which will then determine maximum win.
    **/
    function addEntry(address _user, uint256 _tokenAmt)
      external 
    {
        // Don't want entries added that aren't from valid lottery coins.
        require(winChances[msg.sender] > 0, "Entry is not from a valid lottery token.");

        // Push drawing to the next Ethereum epoch
        uint96 drawBlock = uint96(block.number + 32);
        uint96 fullTokens = uint96(_tokenAmt / WEI);

        Entry memory entry = Entry(_user, fullTokens, msg.sender, drawBlock);
        entries.push(entry);
    }

/* ********************************************* INTERNAL ********************************************* */

    /**
     * @notice Reveal part of the commit/reveal where we check whether a user has won according to blockhash.
     * @param _token The address of the lottery token that we're checking.
     * @param _user The address of the user whose entry we're checking.
     * @param _drawBlock Block number of the block where drawing is allowed.
    **/
    function _checkWin(address _token, address _user, uint256 _drawBlock)
      internal
      view
    returns (bool isWinner)
    {
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
    **/
    function _wonLottery(address _token, address _user, uint256 _tokenAmt)
      internal 
    {
        // Need to first convert full token amount to token wei.
        uint256 fullTokens = _tokenAmt * WEI;
        ILotteryToken(_token).payWinner(_user, fullTokens);
    }

}

/**
 * @title Lottery Token
 * @author Robert M.C. Forster
 * @notice Actual token for the lottery scheme. Tax token that also adds taxes to a lottery pot.
 * @dev On every single token transfer it also calls back to the lottery master to check
 *      whether previous entries for any token have won their own lottery.
**/
contract LotteryToken is TaxToken {

    // The maximum amount over entry amount that the user can win.
    // 10000 == 100x
    uint256 public maxWinMultiplier;

    // Chance for a win to occur. Can be from 1 - 1 million.
    uint256 public winChance;

    // Factory contract that holds all lottery token entries.
    address public lotteryMaster;

    // Amount of tokens currently in the pot able to payout lottery wins.
    uint256 public lotteryPot;

    // Percent of tokens to be put into the pot. 100 == 1%.
    uint256 public potPercent;

    event LotteryWin(address user, uint256 entryAmount, uint256 winnings, uint256 timestamp);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, uint256 _maxWinMultiplier, uint256 _potPercent) 
       TaxToken(_name, _symbol, _initialSupply)
    {
        maxWinMultiplier = _maxWinMultiplier;
        potPercent = _potPercent;
    }

/* ********************************************* INTERNAL ********************************************* */

    // OpenZeppelin ERC20 _update with only change being upkeep and entry calls.
    function _update(address from, address to, uint256 value) internal override {

        uint256 tax = determineTax(from, to, value);
        // Final value to be received by address.
        uint256 receiveValue = value - tax;

        // Every transfer calls to upkeep the lottery.
        ILotteryMaster(lotteryMaster).upkeep(0);

        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }

            // Add lottery entry for the user receiving tokens.
            if (taxed[from]) ILotteryMaster(lotteryMaster).addEntry(to, value);
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                // Weird situation with taxes but if you somehow tax burning it should be receiveValue here.
                _totalSupply -= receiveValue;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                // Default value here changed to receiveValue to account for possible taxes.
                _balances[to] += receiveValue;
            }
        }

        // External interaction here must come after state changes.
        if (tax > 0) {
            _awardTaxes(tax);
            _sellTaxes();
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev In versions with more advanced tax features, this function will be overridden.
     * @param _amount Amount of tax tokens to be awarded.
    **/
    function _awardTaxes(uint256 _amount)
      internal
      override
    {
        uint256 potGain = _amount * potPercent / DIVISOR;
        _balances[address(this)] += _amount - potGain;
    }

/* ********************************************* PRIVILEGED ********************************************* */

    /**
     * @notice Lottery master calls in here to payout a win.
     * @param _user The user address who's won the lottery.
     * @param _entryAmount The amount of tokens they purchased with this entry which determines their maximum win.
    **/
    function payWinner(address _user, uint256 _entryAmount)
      external
    {
        require(msg.sender == lotteryMaster, "Only LotteryMaster may pay winner.");

        uint256 maxWin = _entryAmount * maxWinMultiplier;
        uint256 winnings = maxWin < lotteryPot ? maxWin : lotteryPot;

        lotteryPot -= winnings;
        _balances[_user] += winnings;

        emit LotteryWin(_user, _entryAmount, winnings, block.timestamp);
    }

    /**
     * @notice Change the percent of taxes that are put into the lottery pot.
     * @param _newPotPercent New percent of taxes that are put into the pot. 100 == 1%.
    **/
    function changePotPercent(uint256 _newPotPercent)
      external
      onlyOwnerOrTreasury
    {
        require(_newPotPercent <= DIVISOR, "New vault percent too high.");
        potPercent = _newPotPercent;
    }

}