// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ClaimIssuer} from "../contracts/ClaimIssuer.sol";
import {Identity} from "../contracts/Identity.sol";

/// @notice Cross-language check: the signature below was produced by
///         `services/issuer-api` (`POST /v1/claims/sign`) and must validate
///         against `ClaimIssuer`. The signer is the issuer-api test key's
///         address — ephemeral/offline, controls no assets.
///         Fixture (identity=0x..A1, topic=1, data=0xabcd) is deterministic
///         (RFC6979) for the pinned viem version in services/issuer-api.
contract IssuerApiCrossCheckTest is Test {
    address private constant API_SIGNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address private constant IDENTITY = address(0xA1);
    uint256 private constant TOPIC_KYC = 1;
    bytes private constant SIGNATURE =
        hex"02eaf5f953788d35e4b0dfea14766ab8a2ef049a3c1a85f8209795e905f6d61d24cb9753b0f0422c5fe6d14acb84682e6697d78d6ca5b43d99610bf36dffa7b61b";

    function test_IssuerApiSignatureValidates() public {
        ClaimIssuer issuer = new ClaimIssuer(API_SIGNER);
        assertTrue(issuer.isClaimValid(IDENTITY, TOPIC_KYC, hex"abcd", SIGNATURE));
    }

    function test_IssuerApiSignatureRejectsTamperedData() public {
        ClaimIssuer issuer = new ClaimIssuer(API_SIGNER);
        assertFalse(issuer.isClaimValid(IDENTITY, TOPIC_KYC, hex"abce", SIGNATURE));
    }

    function test_IssuerApiSignatureRejectsWrongSignerContract() public {
        ClaimIssuer issuer = new ClaimIssuer(address(0xBEEF));
        assertFalse(issuer.isClaimValid(IDENTITY, TOPIC_KYC, hex"abcd", SIGNATURE));
    }

    /// Mirrors the wired dapp flow: the API signature is stored on the Identity
    /// with `issuer` = the ClaimIssuer contract, then validates against it.
    function test_ApiSignatureStoredOnIdentityAndValidates() public {
        ClaimIssuer claimIssuer = new ClaimIssuer(API_SIGNER);
        Identity idy = new Identity(abi.encode(address(this)));
        // Wired model: the claim's `issuer` is the ClaimIssuer contract (the
        // trusted issuer in IdentityRegistry), and the signature is the API's.
        bytes32 claimId = idy.addClaim(TOPIC_KYC, 1, address(claimIssuer), SIGNATURE, hex"abcd", "");
        (uint256 topic, , address issuer, , , , bool revoked) = idy.getClaim(claimId);
        assertEq(topic, TOPIC_KYC);
        assertEq(issuer, address(claimIssuer));
        assertFalse(revoked);

        // The fixture signature was produced for IDENTITY (0x..A1).
        assertTrue(claimIssuer.isClaimValid(IDENTITY, TOPIC_KYC, hex"abcd", SIGNATURE));
        assertTrue(idy.verifyClaim(claimId));
    }
}
