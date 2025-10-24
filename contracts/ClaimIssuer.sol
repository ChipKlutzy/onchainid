// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title ClaimIssuer — issues ONCHAINID-style claims with signature checks
/// @notice The issuer signs keccak256(identity, topic, data) with its private
///         key; anyone can verify via isClaimValid. The issuer address can be
///         rotated by the owner.
contract ClaimIssuer {
    address public signer;
    address public owner;

    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

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
        return MessageHashUtils.toEthSignedMessageHash(claimDigest(identity, topic, data));
    }

    /// @notice Returns true when `signature` over this claim was produced by
    ///         the authorized signer.
    function isClaimValid(address identity, uint256 topic, bytes memory data, bytes memory signature)
        public
        view
        returns (bool)
    {
        if (signature.length != 65) return false;
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(ethSignedDigest(identity, topic, data), signature);
        return err == ECDSA.RecoverError.NoError && recovered == signer;
    }

    /// @notice Convenience wrapper that reverts on invalid signatures.
    function requireValidClaim(address identity, uint256 topic, bytes memory data, bytes memory signature)
        external
        view
    {
        if (!isClaimValid(identity, topic, data, signature)) revert InvalidSignature();
    }
}
