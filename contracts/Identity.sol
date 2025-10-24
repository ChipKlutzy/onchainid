// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Identity — minimal ERC-734 (key management) + ERC-735 (claim management)
/// @notice Self-sovereign identity contract in the ONCHAINID style.
///         MANAGEMENT keys (purpose 1) administer keys and claims.
///         Key purposes follow ERC-734: 1 = MANAGEMENT, 2 = ACTION,
///         3 = CLAIM signer, 4 = ENCRYPTION.
contract Identity {
    // ------------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------------

    struct Key {
        uint256 keyType; // e.g. 1 = ECDSA, 2 = RSA, ...
        uint256[] purposes;
        bool revoked;
    }

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
        bool revoked;
    }

    // ------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------

    /// @dev keyId (keccak256 of the raw key bytes) => Key
    mapping(bytes32 => Key) private _keys;
    /// @dev purpose => keyId => has purpose
    mapping(uint256 => mapping(bytes32 => bool)) private _purposeKeys;
    bytes32[] private _keyIds;

    /// @dev claimId (keccak256(issuer, topic)) => Claim
    mapping(bytes32 => Claim) private _claims;
    bytes32[] private _claimIds;

    // ------------------------------------------------------------------------
    // Events (ERC-734 / ERC-735 shapes)
    // ------------------------------------------------------------------------

    event KeyAdded(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event KeyRemoved(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRemoved(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRevoked(bytes32 indexed claimId, address indexed revokedBy);
    event Executed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------

    error NotManagementKey();
    error KeyAlreadyExists();
    error KeyNotFound();
    error ClaimNotFound();
    error NotAuthorized();
    error ExecutionFailed();

    uint256 private _executionNonce;

    // ------------------------------------------------------------------------
    // Construction
    // ------------------------------------------------------------------------

    /// @param managementKey Raw key bytes (typically abi.encode(address)) that
    ///        becomes the first MANAGEMENT key of this identity.
    constructor(bytes memory managementKey) {
        bytes32 keyId = keccak256(managementKey);
        uint256[] memory purposes = new uint256[](1);
        purposes[0] = 1; // MANAGEMENT
        _keys[keyId] = Key({keyType: 1, purposes: purposes, revoked: false});
        _purposeKeys[1][keyId] = true;
        _keyIds.push(keyId);
        emit KeyAdded(keyId, 1, 1);
    }

    // ------------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------------

    modifier onlyManagement() {
        if (!_purposeKeys[1][keccak256(abi.encode(msg.sender))]) revert NotManagementKey();
        _;
    }

    // ------------------------------------------------------------------------
    // ERC-734 — key management
    // ------------------------------------------------------------------------

    /// @notice Add a key with the given purposes. MANAGEMENT only.
    function addKey(bytes memory key, uint256[] memory purposes, uint256 keyType) external onlyManagement {
        bytes32 keyId = keccak256(key);
        if (_keys[keyId].keyType != 0) revert KeyAlreadyExists();
        _keys[keyId] = Key({keyType: keyType, purposes: purposes, revoked: false});
        _keyIds.push(keyId);
        for (uint256 i = 0; i < purposes.length; i++) {
            _purposeKeys[purposes[i]][keyId] = true;
            emit KeyAdded(keyId, purposes[i], keyType);
        }
    }

    /// @notice Remove a key entirely. MANAGEMENT only.
    function removeKey(bytes32 keyId) external onlyManagement {
        if (!_keyIdsContains(keyId)) revert KeyNotFound();
        uint256 keyType = _keys[keyId].keyType;
        uint256[] memory purposes = _keys[keyId].purposes;
        for (uint256 i = 0; i < purposes.length; i++) {
            delete _purposeKeys[purposes[i]][keyId];
            emit KeyRemoved(keyId, purposes[i], keyType);
        }
        delete _keys[keyId];
        _removeKeyId(keyId);
    }

    /// @notice ERC-734 execute: MANAGEMENT or ACTION key may execute calls.
    function execute(address to, uint256 value, bytes memory data) external returns (uint256 executionId) {
        bytes32 senderId = keccak256(abi.encode(msg.sender));
        if (!_purposeKeys[1][senderId] && !_purposeKeys[2][senderId]) revert NotManagementKey();
        executionId = _executionNonce++;
        (bool ok,) = to.call{value: value}(data);
        if (!ok) revert ExecutionFailed();
        emit Executed(executionId, to, value, data);
    }

    function getKey(bytes32 keyId) external view returns (uint256 keyType, uint256[] memory purposes, bool revoked) {
        Key storage k = _keys[keyId];
        if (k.keyType == 0) revert KeyNotFound();
        return (k.keyType, k.purposes, k.revoked);
    }

    function keyHasPurpose(bytes32 keyId, uint256 purpose) external view returns (bool) {
        return _purposeKeys[purpose][keyId];
    }

    function getKeyIds() external view returns (bytes32[] memory) {
        return _keyIds;
    }

    // ------------------------------------------------------------------------
    // ERC-735 — claim management
    // ------------------------------------------------------------------------

    /// @notice Add (or overwrite) a claim. Callable by the claim issuer or a
    ///         MANAGEMENT key holder (self).
    /// @return claimId keccak256(abi.encode(issuer, topic)).
    function addClaim(
        uint256 topic,
        uint256 scheme,
        address issuer,
        bytes memory signature,
        bytes memory data,
        string memory uri
    ) external returns (bytes32 claimId) {
        bytes32 senderId = keccak256(abi.encode(msg.sender));
        if (msg.sender != issuer && !_purposeKeys[1][senderId]) revert NotAuthorized();
        claimId = keccak256(abi.encode(issuer, topic));
        bool fresh = _claims[claimId].issuer == address(0);
        _claims[claimId] = Claim({
            topic: topic,
            scheme: scheme,
            issuer: issuer,
            signature: signature,
            data: data,
            uri: uri,
            revoked: false
        });
        if (fresh) _claimIds.push(claimId);
        emit ClaimAdded(claimId, topic, scheme, issuer, signature, data, uri);
    }

    /// @notice Delete a claim. Callable by the claim issuer or MANAGEMENT.
    function removeClaim(bytes32 claimId) external {
        Claim storage c = _claims[claimId];
        if (c.issuer == address(0)) revert ClaimNotFound();
        bytes32 senderId = keccak256(abi.encode(msg.sender));
        if (msg.sender != c.issuer && !_purposeKeys[1][senderId]) revert NotAuthorized();
        emit ClaimRemoved(claimId, c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri);
        delete _claims[claimId];
        _removeClaimId(claimId);
    }

    /// @notice Flag a claim as revoked without deleting it. Issuer or MANAGEMENT.
    function revokeClaim(bytes32 claimId) external {
        Claim storage c = _claims[claimId];
        if (c.issuer == address(0)) revert ClaimNotFound();
        bytes32 senderId = keccak256(abi.encode(msg.sender));
        if (msg.sender != c.issuer && !_purposeKeys[1][senderId]) revert NotAuthorized();
        c.revoked = true;
        emit ClaimRevoked(claimId, msg.sender);
    }

    /// @notice Off-chain style validity check: claim exists and is not revoked.
    ///         Cryptographic validity of the issuer signature is checked via
    ///         ClaimIssuer.isClaimValid.
    function verifyClaim(bytes32 claimId) external view returns (bool) {
        Claim storage c = _claims[claimId];
        return c.issuer != address(0) && !c.revoked;
    }

    function getClaim(bytes32 claimId)
        external
        view
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri,
            bool revoked
        )
    {
        Claim storage c = _claims[claimId];
        if (c.issuer == address(0)) revert ClaimNotFound();
        return (c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri, c.revoked);
    }

    function getClaimIds() external view returns (bytes32[] memory) {
        return _claimIds;
    }

    // ------------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------------

    function _keyIdsContains(bytes32 keyId) internal view returns (bool) {
        for (uint256 i = 0; i < _keyIds.length; i++) {
            if (_keyIds[i] == keyId) return true;
        }
        return false;
    }

    function _removeKeyId(bytes32 keyId) internal {
        for (uint256 i = 0; i < _keyIds.length; i++) {
            if (_keyIds[i] == keyId) {
                _keyIds[i] = _keyIds[_keyIds.length - 1];
                _keyIds.pop();
                return;
            }
        }
    }

    function _removeClaimId(bytes32 claimId) internal {
        for (uint256 i = 0; i < _claimIds.length; i++) {
            if (_claimIds[i] == claimId) {
                _claimIds[i] = _claimIds[_claimIds.length - 1];
                _claimIds.pop();
                return;
            }
        }
    }
}
