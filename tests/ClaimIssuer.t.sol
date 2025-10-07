// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ClaimIssuer} from "../contracts/ClaimIssuer.sol";

/// @notice Signature-check coverage for ClaimIssuer.isClaimValid.
contract ClaimIssuerTest is Test {
    ClaimIssuer private issuer;
    // Ephemeral, unfunded test-only signing key. Exists only inside Forge's
    // sandbox (vm.sign) and controls no assets on any network.
    uint256 private signerPk = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address private signerAddr;
    address private identity = address(0x1D);
    uint256 private constant TOPIC_KYC = 1;

    function setUp() public {
        signerAddr = vm.addr(signerPk);
        issuer = new ClaimIssuer(signerAddr);
    }

    function _sign(address id_, uint256 topic, bytes memory data) internal view returns (bytes memory sig) {
        bytes32 ethDigest = issuer.ethSignedDigest(id_, topic, data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ethDigest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_ValidSignaturePasses() public view {
        bytes memory data = hex"abcd";
        bytes memory sig = _sign(identity, TOPIC_KYC, data);
        assertTrue(issuer.isClaimValid(identity, TOPIC_KYC, data, sig));
    }

    function test_TamperedDataFails() public view {
        bytes memory sig = _sign(identity, TOPIC_KYC, hex"abcd");
        assertFalse(issuer.isClaimValid(identity, TOPIC_KYC, hex"abce", sig));
    }

    function test_WrongTopicFails() public view {
        bytes memory data = hex"abcd";
        bytes memory sig = _sign(identity, TOPIC_KYC, data);
        assertFalse(issuer.isClaimValid(identity, TOPIC_KYC + 1, data, sig));
    }

    function test_WrongIdentityFails() public view {
        bytes memory data = hex"abcd";
        bytes memory sig = _sign(identity, TOPIC_KYC, data);
        assertFalse(issuer.isClaimValid(address(0x2D), TOPIC_KYC, data, sig));
    }

    function test_UnknownSignerFails() public view {
        uint256 otherPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef; // unfunded test vector, sandbox only
        bytes32 ethDigest = issuer.ethSignedDigest(identity, TOPIC_KYC, hex"abcd");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, ethDigest);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertFalse(issuer.isClaimValid(identity, TOPIC_KYC, hex"abcd", sig));
    }

    function test_MalformedSignatureFails() public view {
        assertFalse(issuer.isClaimValid(identity, TOPIC_KYC, hex"abcd", hex"1234"));
    }

    function test_SignerRotation() public {
        address newSigner = address(0xBE57);
        issuer.setSigner(newSigner);
        assertEq(issuer.signer(), newSigner);
        // Old signer's signature no longer validates.
        bytes memory data = hex"abcd";
        bytes memory sig = _sign(identity, TOPIC_KYC, data);
        assertFalse(issuer.isClaimValid(identity, TOPIC_KYC, data, sig));
    }

    function test_NonOwnerCannotRotateSigner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(ClaimIssuer.NotOwner.selector);
        issuer.setSigner(address(0xBE57));
    }
}
