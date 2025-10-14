// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IdentityRegistry} from "./IdentityRegistry.sol";

/// @title ModularCompliance — ERC-3643 country allowlist + freeze module
/// @notice Bound to one IdentityRegistry (for per-wallet countries) and one
///         token (the only caller allowed to mutate freeze state on its
///         behalf is the owner). `canTransfer` returns false when either side
///         is frozen or lives in a non-allowlisted country. Mint (from == 0)
///         skips the sender-side checks.
contract ModularCompliance {
    address public owner;

    IdentityRegistry public identityRegistry;
    address public token;

    mapping(address => bool) private _frozen;
    mapping(uint16 => bool) private _countryAllowed;

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event TokenBound(address indexed token);
    event WalletFrozen(address indexed wallet);
    event WalletUnfrozen(address indexed wallet);
    event CountryAllowlistUpdated(uint16 indexed country, bool allowed);

    error NotOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address identityRegistry_) {
        if (identityRegistry_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        identityRegistry = IdentityRegistry(identityRegistry_);
    }

    /// @notice Bind the token this module governs. Owner only.
    function bindToken(address token_) external onlyOwner {
        if (token_ == address(0)) revert ZeroAddress();
        token = token_;
        emit TokenBound(token_);
    }

    /// @notice Freeze `wallet`: it can neither send nor receive. Owner only.
    function freeze(address wallet) external onlyOwner {
        _frozen[wallet] = true;
        emit WalletFrozen(wallet);
    }

    /// @notice Unfreeze `wallet`. Owner only.
    function unfreeze(address wallet) external onlyOwner {
        _frozen[wallet] = false;
        emit WalletUnfrozen(wallet);
    }

    /// @notice True when `wallet` is frozen.
    function isFrozen(address wallet) external view returns (bool) {
        return _frozen[wallet];
    }

    /// @notice Allowlist (or delist) a country code. Owner only.
    function setCountryAllowed(uint16 country, bool allowed) external onlyOwner {
        _countryAllowed[country] = allowed;
        emit CountryAllowlistUpdated(country, allowed);
    }

    /// @notice True when `country` is allowlisted.
    function isCountryAllowed(uint16 country) external view returns (bool) {
        return _countryAllowed[country];
    }

    /// @notice Transfer gate: no frozen side, both sides in allowlisted
    ///         countries. `from == address(0)` (mint) skips sender checks.
    function canTransfer(address from, address to) external view returns (bool) {
        if (_frozen[to]) return false;
        if (!_countryAllowed[identityRegistry.country(to)]) return false;
        if (from == address(0)) return true;
        if (_frozen[from]) return false;
        if (!_countryAllowed[identityRegistry.country(from)]) return false;
        return true;
    }
}
