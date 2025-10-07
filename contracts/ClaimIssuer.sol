// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ClaimIssuer — issues ONCHAINID-style claims with signature checks
/// @notice The issuer signs keccak256(identity, topic, data) with its private
///         key; anyone can verify via isClaimValid. The issuer address can be
///         rotated by the owner.
contract ClaimIssuer {
    address public signer;
    address public owner;

    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event ClaimIssued(address indexed identity, uint256 indexed topic, bytes data);

    error NotOwner();
    error InvalidSignature();
    error ZeroSigner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address initialSigner) {
        if (initialSigner == address(0)) revert ZeroSigner();
        owner = msg.sender;
        signer = initialSigner;
    }

    /// @notice Rotate the authorized claim signer. Owner only.
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroSigner();
        emit SignerUpdated(signer, newSigner);
        signer = newSigner;
    }

    /// @notice Digest that must be signed for a claim to be valid.
    function claimDigest(address identity, uint256 topic, bytes memory data) public pure returns (bytes32) {
        return keccak256(abi.encode(identity, topic, data));
    }

    /// @notice EIP-191 prefixed hash of the claim digest (as produced by
    ///         `wallet.signMessage` / `eth_sign`).
    function ethSignedDigest(address identity, uint256 topic, bytes memory data) public pure returns (bytes32) {
        bytes32 digest = claimDigest(identity, topic, data);
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    /// @notice Returns true when `signature` over this claim was produced by
    ///         the authorized signer.
    function isClaimValid(address identity, uint256 topic, bytes memory data, bytes memory signature)
        public
        view
        returns (bool)
    {
        if (signature.length != 65) return false;
        bytes32 ethDigest = ethSignedDigest(identity, topic, data);
        (bytes32 r, bytes32 s, uint8 v) = _split(signature);
        address recovered = ecrecover(ethDigest, v, r, s);
        return recovered == signer;
    }

    /// @notice Convenience wrapper that reverts on invalid signatures.
    function requireValidClaim(address identity, uint256 topic, bytes memory data, bytes memory signature)
        external
        view
    {
        if (!isClaimValid(identity, topic, data, signature)) revert InvalidSignature();
    }

    /// @notice Announce issuance of a claim (the claim itself is stored on the
    ///         Identity contract; this event is the issuer-side audit trail).
    function announceClaim(address identity, uint256 topic, bytes memory data) external onlyOwner {
        emit ClaimIssued(identity, topic, data);
    }

    function _split(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
