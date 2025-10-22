// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Identity} from "../Identity.sol";
import {ClaimTopicsRegistry} from "./ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "./TrustedIssuersRegistry.sol";
import {IdentityRegistryStorage} from "./IdentityRegistryStorage.sol";

/// @notice Minimal view of a ClaimIssuer contract used to verify claim signatures.
interface IClaimIssuer {
    function isClaimValid(address identity, uint256 topic, bytes memory data, bytes memory signature)
        external
        view
        returns (bool);
}

/// @title IdentityRegistry — ERC-3643 identity verification entry point
/// @notice A wallet `isVerified` when it is bound to an Identity contract
///         that holds a live (present + not revoked) claim for every required
///         claim topic, each issued by an issuer trusted for that topic.
contract IdentityRegistry {
    address public owner;

    ClaimTopicsRegistry public claimTopicsRegistry;
    TrustedIssuersRegistry public trustedIssuersRegistry;
    IdentityRegistryStorage public identityStorage;

    mapping(address => bool) private _agents;

    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event RegistryUpdated(address indexed topicsRegistry, address indexed issuersRegistry, address indexed storage_);

    error NotAuthorized();
    error ZeroAddress();

    modifier onlyAgentOrOwner() {
        if (msg.sender != owner && !_agents[msg.sender]) revert NotAuthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(
        address topicsRegistry,
        address issuersRegistry,
        address identityStorage_
    ) {
        if (topicsRegistry == address(0) || issuersRegistry == address(0) || identityStorage_ == address(0)) {
            revert ZeroAddress();
        }
        owner = msg.sender;
        claimTopicsRegistry = ClaimTopicsRegistry(topicsRegistry);
        trustedIssuersRegistry = TrustedIssuersRegistry(issuersRegistry);
        identityStorage = IdentityRegistryStorage(identityStorage_);
    }

    /// @notice Authorize an agent (e.g. the token) to register identities. Owner only.
    function addAgent(address agent) external onlyOwner {
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    /// @notice Deauthorize an agent. Owner only.
    function removeAgent(address agent) external onlyOwner {
        delete _agents[agent];
        emit AgentRemoved(agent);
    }

    /// @notice True when `agent` may register identities through this registry.
    function isAgent(address agent) external view returns (bool) {
        return _agents[agent];
    }

    /// @notice Point this registry at new backing registries. Owner only.
    function setRegistries(address topicsRegistry, address issuersRegistry, address identityStorage_)
        external
        onlyOwner
    {
        if (topicsRegistry == address(0) || issuersRegistry == address(0) || identityStorage_ == address(0)) {
            revert ZeroAddress();
        }
        claimTopicsRegistry = ClaimTopicsRegistry(topicsRegistry);
        trustedIssuersRegistry = TrustedIssuersRegistry(issuersRegistry);
        identityStorage = IdentityRegistryStorage(identityStorage_);
        emit RegistryUpdated(topicsRegistry, issuersRegistry, identityStorage_);
    }

    /// @notice Bind `wallet` to `identity` with `country`. Agent or owner.
    function registerIdentity(address wallet, address identity, uint16 country) external onlyAgentOrOwner {
        identityStorage.registerIdentity(wallet, identity, country);
    }

    /// @notice Remove the identity binding for `wallet`. Agent or owner.
    function deleteIdentity(address wallet) external onlyAgentOrOwner {
        identityStorage.removeIdentity(wallet);
    }

    /// @notice Update the country code for `wallet`. Agent or owner.
    function setCountry(address wallet, uint16 country) external onlyAgentOrOwner {
        identityStorage.setCountry(wallet, country);
    }

    /// @notice Identity contract bound to `wallet`.
    function identity(address wallet) external view returns (address) {
        return identityStorage.storedIdentity(wallet);
    }

    /// @notice Country code recorded for `wallet`.
    function country(address wallet) external view returns (uint16) {
        return identityStorage.storedCountry(wallet);
    }

    /// @notice ERC-3643 verification: every required topic must be covered by
    ///         a live claim from an issuer trusted for that topic.
    function isVerified(address wallet) external view returns (bool) {
        address identity_ = identityStorage.storedIdentity(wallet);
        if (identity_ == address(0)) return false;
        uint256[] memory topics = claimTopicsRegistry.getClaimTopics();
        address[] memory issuers = trustedIssuersRegistry.getTrustedIssuers();
        for (uint256 t = 0; t < topics.length; t++) {
            if (!_topicCovered(identity_, topics[t], issuers)) return false;
        }
        return true;
    }

    function _topicCovered(address identity_, uint256 topic, address[] memory issuers)
        internal
        view
        returns (bool)
    {
        if (identity_.code.length == 0) return false;
        for (uint256 i = 0; i < issuers.length; i++) {
            if (!trustedIssuersRegistry.isIssuerAuthorizedForTopic(issuers[i], topic)) continue;
            bytes32 claimId = keccak256(abi.encode(issuers[i], topic));
            if (!Identity(identity_).verifyClaim(claimId)) continue;
            // On-chain signature check: the claim must carry a signature from the
            // trusted issuer over (identity, topic, data). Without this, an
            // identity owner could self-attest eligibility by naming a trusted
            // issuer on a claim with no valid signature.
            (, , , bytes memory signature, bytes memory data, , ) = Identity(identity_).getClaim(claimId);
            if (_issuerSignatureValid(issuers[i], identity_, topic, data, signature)) return true;
        }
        return false;
    }

    /// @dev Calls the trusted issuer's `isClaimValid`. Returns false (rather
    ///      than reverting) when the issuer is not a contract or does not
    ///      implement the interface.
    function _issuerSignatureValid(
        address issuer,
        address identity_,
        uint256 topic,
        bytes memory data,
        bytes memory signature
    ) internal view returns (bool) {
        if (issuer.code.length == 0) return false;
        try IClaimIssuer(issuer).isClaimValid(identity_, topic, data, signature) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }
}
