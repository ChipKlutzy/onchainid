// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title TrustedIssuersRegistry — ERC-3643 trusted claim issuers
/// @notice Maps each trusted issuer (the `issuer` address recorded on
///         Identity claims) to the claim topics it is authorized to issue.
contract TrustedIssuersRegistry {
    address public owner;

    address[] private _issuers;
    mapping(address => bool) private _isTrusted;
    mapping(address => uint256[]) private _issuerTopics;

    event TrustedIssuerAdded(address indexed issuer);
    event TrustedIssuerRemoved(address indexed issuer);
    event IssuerTopicsUpdated(address indexed issuer);

    error NotOwner();
    error IssuerAlreadyTrusted();
    error IssuerNotTrusted();
    error ZeroIssuer();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Trust a new issuer for the given claim topics. Owner only.
    function addTrustedIssuer(address issuer, uint256[] memory topics) external onlyOwner {
        if (issuer == address(0)) revert ZeroIssuer();
        if (_isTrusted[issuer]) revert IssuerAlreadyTrusted();
        _isTrusted[issuer] = true;
        _issuerTopics[issuer] = topics;
        _issuers.push(issuer);
        emit TrustedIssuerAdded(issuer);
    }

    /// @notice Replace the authorized topics of a trusted issuer. Owner only.
    function updateIssuerTopics(address issuer, uint256[] memory topics) external onlyOwner {
        if (!_isTrusted[issuer]) revert IssuerNotTrusted();
        _issuerTopics[issuer] = topics;
        emit IssuerTopicsUpdated(issuer);
    }

    /// @notice Remove a trusted issuer. Owner only.
    function removeTrustedIssuer(address issuer) external onlyOwner {
        if (!_isTrusted[issuer]) revert IssuerNotTrusted();
        _isTrusted[issuer] = false;
        delete _issuerTopics[issuer];
        for (uint256 i = 0; i < _issuers.length; i++) {
            if (_issuers[i] == issuer) {
                _issuers[i] = _issuers[_issuers.length - 1];
                _issuers.pop();
                break;
            }
        }
        emit TrustedIssuerRemoved(issuer);
    }

    /// @notice True when `issuer` is currently trusted.
    function isTrustedIssuer(address issuer) external view returns (bool) {
        return _isTrusted[issuer];
    }

    /// @notice All currently trusted issuers.
    function getTrustedIssuers() external view returns (address[] memory) {
        return _issuers;
    }

    /// @notice Claim topics `issuer` is authorized to issue.
    function getIssuerClaimTopics(address issuer) external view returns (uint256[] memory) {
        return _issuerTopics[issuer];
    }

    /// @notice True when `issuer` is trusted for `topic`.
    function isIssuerAuthorizedForTopic(address issuer, uint256 topic) external view returns (bool) {
        if (!_isTrusted[issuer]) return false;
        uint256[] storage topics = _issuerTopics[issuer];
        for (uint256 i = 0; i < topics.length; i++) {
            if (topics[i] == topic) return true;
        }
        return false;
    }
}
