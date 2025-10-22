// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ClaimTopicsRegistry — ERC-3643 required claim topics
/// @notice The token owner lists which claim topics (e.g. 1 = KYC) every
///         investor identity must hold for IdentityRegistry.isVerified.
contract ClaimTopicsRegistry {
    address public owner;

    uint256[] private _claimTopics;
    mapping(uint256 => bool) private _isRequired;

    event ClaimTopicAdded(uint256 indexed topic);
    event ClaimTopicRemoved(uint256 indexed topic);

    error NotOwner();
    error TopicAlreadyRequired();
    error TopicNotRequired();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Add a required claim topic. Owner only.
    function addClaimTopic(uint256 topic) external onlyOwner {
        if (_isRequired[topic]) revert TopicAlreadyRequired();
        _isRequired[topic] = true;
        _claimTopics.push(topic);
        emit ClaimTopicAdded(topic);
    }

    /// @notice Remove a required claim topic. Owner only.
    function removeClaimTopic(uint256 topic) external onlyOwner {
        if (!_isRequired[topic]) revert TopicNotRequired();
        _isRequired[topic] = false;
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            if (_claimTopics[i] == topic) {
                _claimTopics[i] = _claimTopics[_claimTopics.length - 1];
                _claimTopics.pop();
                break;
            }
        }
        emit ClaimTopicRemoved(topic);
    }

    /// @notice All currently required claim topics.
    function getClaimTopics() external view returns (uint256[] memory) {
        return _claimTopics;
    }

    /// @notice True when `topic` is currently required.
    function isClaimTopicRequired(uint256 topic) external view returns (bool) {
        return _isRequired[topic];
    }
}
