// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Identity} from "../contracts/Identity.sol";

/// @notice Claim add/verify/revoke (ERC-735) coverage for Identity.
contract IdentityClaimsTest is Test {
    Identity private id_;
    address private manager = address(0xA11CE);
    address private issuer = address(0x155E5);
    address private stranger = address(0xBAD);

    uint256 private constant TOPIC_KYC = 1;
    uint256 private constant SCHEME_ECDSA = 1;

    function setUp() public {
        id_ = new Identity(abi.encode(manager));
    }

    function _addClaim() internal returns (bytes32 claimId) {
        vm.prank(issuer);
        claimId = id_.addClaim(TOPIC_KYC, SCHEME_ECDSA, issuer, hex"1234", hex"abcd", "https://example.com/kyc");
    }

    function test_AddClaimByIssuer() public {
        bytes32 claimId = _addClaim();
        assertEq(claimId, keccak256(abi.encode(issuer, TOPIC_KYC)));
        assertTrue(id_.verifyClaim(claimId));
        (uint256 topic, uint256 scheme, address gotIssuer,,, string memory uri, bool revoked) =
            id_.getClaim(claimId);
        assertEq(topic, TOPIC_KYC);
        assertEq(scheme, SCHEME_ECDSA);
        assertEq(gotIssuer, issuer);
        assertEq(uri, "https://example.com/kyc");
        assertFalse(revoked);
    }

    function test_AddClaimByManager() public {
        vm.prank(manager);
        bytes32 claimId = id_.addClaim(TOPIC_KYC, SCHEME_ECDSA, issuer, hex"1234", hex"abcd", "");
        assertTrue(id_.verifyClaim(claimId));
    }

    function test_StrangerCannotAddClaim() public {
        vm.prank(stranger);
        vm.expectRevert(Identity.NotAuthorized.selector);
        id_.addClaim(TOPIC_KYC, SCHEME_ECDSA, issuer, hex"1234", hex"abcd", "");
    }

    function test_RevokeClaimByIssuer() public {
        bytes32 claimId = _addClaim();
        vm.prank(issuer);
        id_.revokeClaim(claimId);
        assertFalse(id_.verifyClaim(claimId));
        (,,,,,, bool revoked) = id_.getClaim(claimId);
        assertTrue(revoked);
    }

    function test_RevokeClaimByManager() public {
        bytes32 claimId = _addClaim();
        vm.prank(manager);
        id_.revokeClaim(claimId);
        assertFalse(id_.verifyClaim(claimId));
    }

    function test_StrangerCannotRevokeClaim() public {
        bytes32 claimId = _addClaim();
        vm.prank(stranger);
        vm.expectRevert(Identity.NotAuthorized.selector);
        id_.revokeClaim(claimId);
    }

    function test_RemoveClaimByIssuer() public {
        bytes32 claimId = _addClaim();
        vm.prank(issuer);
        id_.removeClaim(claimId);
        assertFalse(id_.verifyClaim(claimId));
        vm.expectRevert(Identity.ClaimNotFound.selector);
        id_.getClaim(claimId);
    }

    function test_VerifyMissingClaimIsFalse() public view {
        assertFalse(id_.verifyClaim(bytes32(uint256(0xDEAD))));
    }
}
