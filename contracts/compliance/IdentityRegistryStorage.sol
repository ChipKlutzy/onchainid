// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IdentityRegistryStorage — ERC-3643 wallet => identity + country store
/// @notice Holds the wallet => Identity-contract binding and the ISO-3166
///         numeric country code per wallet. Writes are restricted to
///         authorized agents (the IdentityRegistry) and the owner.
contract IdentityRegistryStorage {
    address public owner;

    mapping(address => bool) private _agents;
    mapping(address => address) private _identityOf;
    mapping(address => uint16) private _countryOf;

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event IdentityRegistered(address indexed wallet, address indexed identity);
    event IdentityRemoved(address indexed wallet, address indexed identity);
    event CountryUpdated(address indexed wallet, uint16 indexed country);

    error NotAuthorized();
    error ZeroWallet();
    error ZeroIdentity();

    modifier onlyAgentOrOwner() {
        if (msg.sender != owner && !_agents[msg.sender]) revert NotAuthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Authorize an agent (e.g. the IdentityRegistry). Owner only.
    function addAgent(address agent) external onlyOwner {
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    /// @notice Deauthorize an agent. Owner only.
    function removeAgent(address agent) external onlyOwner {
        delete _agents[agent];
        emit AgentRemoved(agent);
    }

    /// @notice True when `agent` may write to this storage.
    function isAgent(address agent) external view returns (bool) {
        return _agents[agent];
    }

    /// @notice Bind `wallet` to `identity` with `country` code.
    function registerIdentity(address wallet, address identity, uint16 country) external onlyAgentOrOwner {
        if (wallet == address(0)) revert ZeroWallet();
        if (identity == address(0)) revert ZeroIdentity();
        _identityOf[wallet] = identity;
        _countryOf[wallet] = country;
        emit IdentityRegistered(wallet, identity);
        emit CountryUpdated(wallet, country);
    }

    /// @notice Remove the identity binding for `wallet` (keeps country).
    function removeIdentity(address wallet) external onlyAgentOrOwner {
        address identity = _identityOf[wallet];
        delete _identityOf[wallet];
        emit IdentityRemoved(wallet, identity);
    }

    /// @notice Update the country code for `wallet`.
    function setCountry(address wallet, uint16 country) external onlyAgentOrOwner {
        if (wallet == address(0)) revert ZeroWallet();
        _countryOf[wallet] = country;
        emit CountryUpdated(wallet, country);
    }

    /// @notice Identity contract bound to `wallet` (zero when unregistered).
    function storedIdentity(address wallet) external view returns (address) {
        return _identityOf[wallet];
    }

    /// @notice Country code recorded for `wallet`.
    function storedCountry(address wallet) external view returns (uint16) {
        return _countryOf[wallet];
    }
}
