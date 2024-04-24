// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
/**
 * @title Goat Trading ERC20
 * @notice ERC20 token contract for the Goat Trading Pair contract.
 * @author Goat Trading -- Chiranjibi Poudyal, Robert M.C. Forster
 */

abstract contract GoatV1ERC20 {
    // Token metadata
    uint256 private constant _TWO_DAYS = 2 days;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    // Total supply of the token
    uint256 private _totalSupply;

    // _balances for each account
    mapping(address => uint256) private _balances;

    // Owner's _allowancess for another account
    mapping(address => mapping(address => uint256)) private _allowances;

    // liquidity lock
    mapping(address => uint32) internal _locked;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function _mint(address _to, uint256 _value) internal {
        uint32 lockUntil;
        if (_value > _totalSupply) {
            lockUntil = uint32(block.timestamp + _TWO_DAYS);
        } else {
            lockUntil = uint32(block.timestamp + ((_value * _TWO_DAYS) / _totalSupply));
        }

        if (lockUntil > _locked[_to]) {
            _locked[_to] = lockUntil;
        }

        _totalSupply += _value;
        _balances[_to] += _value;

        emit Transfer(address(0), _to, _value);
    }

    function _burn(address _from, uint256 _value) internal {
        _balances[_from] -= _value;
        _totalSupply -= _value;
        emit Transfer(_from, address(0), _value);
    }

    function _approve(address _owner, address _spender, uint256 _value) internal {
        _allowances[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        _beforeTokenTransfer(_from, _to, _value);
        _balances[_from] -= _value;
        _balances[_to] += _value;
        emit Transfer(_from, _to, _value);
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        if (_allowances[_from][msg.sender] != type(uint256).max) {
            _allowances[_from][msg.sender] -= _value;
        }
        _transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return _balances[_owner];
    }

    // Get the value of tokens that an owner allowance to a spender
    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return _allowances[_owner][_spender];
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _value) internal virtual;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
}
