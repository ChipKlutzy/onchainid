// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Identity} from "../contracts/Identity.sol";
import {ClaimIssuer} from "../contracts/ClaimIssuer.sol";
import {ClaimTopicsRegistry} from "../contracts/compliance/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../contracts/compliance/TrustedIssuersRegistry.sol";
import {IdentityRegistryStorage} from "../contracts/compliance/IdentityRegistryStorage.sol";
import {IdentityRegistry} from "../contracts/compliance/IdentityRegistry.sol";
import {ModularCompliance} from "../contracts/compliance/ModularCompliance.sol";
import {CompliantToken} from "../contracts/token/CompliantToken.sol";

/// @notice ERC-3643 happy path + gate coverage: mint/transfer succeed for
///         verified wallets; unclaimed, revoked, frozen, and
///         non-allowlisted-country receivers revert.
contract ComplianceTest is Test {
    uint256 private constant TOPIC_KYC = 1;
    uint16 private constant COUNTRY_OK = 42;
    uint16 private constant COUNTRY_BLOCKED = 999;

    ClaimTopicsRegistry private ctr;
    TrustedIssuersRegistry private tir;
    IdentityRegistryStorage private irs;
    IdentityRegistry private ir;
    ModularCompliance private mc;
    CompliantToken private token;

    // Ephemeral, unfunded test-only signing key (sandbox only, controls no assets).
    uint256 private constant ISSUER_PK = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    ClaimIssuer private claimIssuer;
    address private issuer; // = address(claimIssuer): the trusted issuer contract
    address private manager = address(0xA11CE);
    address private alice = address(0xA11CE + 1);
    address private bob = address(0xB0B);
    address private stranger = address(0xBAD);

    function setUp() public {
        claimIssuer = new ClaimIssuer(vm.addr(ISSUER_PK));
        issuer = address(claimIssuer);

        ctr = new ClaimTopicsRegistry();
        ctr.addClaimTopic(TOPIC_KYC);

        tir = new TrustedIssuersRegistry();
        uint256[] memory topics = new uint256[](1);
        topics[0] = TOPIC_KYC;
        tir.addTrustedIssuer(issuer, topics);

        irs = new IdentityRegistryStorage();
        ir = new IdentityRegistry(address(ctr), address(tir), address(irs));
        irs.addAgent(address(ir));

        mc = new ModularCompliance(address(ir));
        mc.setCountryAllowed(COUNTRY_OK, true);

        token = new CompliantToken("RWA Token", "RWA", address(ir), address(mc));

        _registerVerified(alice, COUNTRY_OK);
        _registerVerified(bob, COUNTRY_OK);
    }

    /// @dev Sign (identity, topic, data) with the issuer key; returns a 65-byte sig.
    function _sign(address id_, uint256 topic, bytes memory data) internal view returns (bytes memory sig) {
        bytes32 ethDigest = claimIssuer.ethSignedDigest(id_, topic, data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, ethDigest);
        sig = abi.encodePacked(r, s, v);
    }

    /// @dev Deploy an Identity for `wallet`, store a KYC claim signed by the
    ///      trusted issuer contract, and bind it in the registry.
    function _registerVerified(address wallet, uint16 country) internal returns (Identity id_) {
        id_ = new Identity(abi.encode(manager));
        bytes memory data = hex"abcd";
        bytes memory sig = _sign(address(id_), TOPIC_KYC, data);
        // Only management can write a claim naming a ClaimIssuer contract; the
        // registry then verifies the signature on-chain.
        vm.prank(manager);
        id_.addClaim(TOPIC_KYC, 1, issuer, sig, data, "");
        ir.registerIdentity(wallet, address(id_), country);
        assertTrue(ir.isVerified(wallet));
    }

    function _claimId() internal view returns (bytes32) {
        return keccak256(abi.encode(issuer, TOPIC_KYC));
    }

    function test_HappyMintAndTransfer() public {
        token.mint(alice, 1000 ether);
        assertEq(token.balanceOf(alice), 1000 ether);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(alice), 900 ether);
    }

    function test_UnclaimedWalletCannotReceive() public {
        // Stranger has no identity at all.
        assertFalse(ir.isVerified(stranger));
        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.mint(stranger, 100 ether);

        // Registered identity but no claim => still unverified.
        Identity bare = new Identity(abi.encode(manager));
        ir.registerIdentity(stranger, address(bare), COUNTRY_OK);
        assertFalse(ir.isVerified(stranger));
        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.mint(stranger, 100 ether);
    }

    function test_RevokedClaimFails() public {
        token.mint(alice, 1000 ether);

        // Revoke alice's KYC claim (management-side revocation).
        Identity idAlice = Identity(ir.identity(alice));
        vm.prank(manager);
        idAlice.revokeClaim(_claimId());
        assertFalse(ir.isVerified(alice));

        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.mint(alice, 1 ether);

        token.mint(bob, 50 ether);
        vm.prank(bob);
        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.transfer(alice, 1 ether);
    }

    function test_FrozenWalletCannotReceive() public {
        token.mint(alice, 1000 ether);

        mc.freeze(bob);
        assertTrue(mc.isFrozen(bob));
        vm.prank(alice);
        vm.expectRevert(CompliantToken.TransferBlockedByCompliance.selector);
        token.transfer(bob, 10 ether);

        mc.unfreeze(bob);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_BlockedCountryCannotReceive() public {
        address dave = address(0xDA9E);
        _registerVerified(dave, COUNTRY_BLOCKED);
        // Verified identity, but the country is not allowlisted: the
        // compliance gate (not the identity gate) must reject.
        assertTrue(ir.isVerified(dave));
        assertFalse(mc.canTransfer(address(0), dave));
        vm.expectRevert(CompliantToken.TransferBlockedByCompliance.selector);
        token.mint(dave, 10 ether);
    }

    function test_ForceTransferRecovery() public {
        token.mint(alice, 1000 ether);

        // Alice's wallet is frozen: normal transfers out still pass the
        // sender gate only if sender not frozen — freeze blocks receipt,
        // so recover her funds to bob via agent-only forceTransfer.
        mc.freeze(alice);
        assertTrue(mc.isFrozen(alice));
        // Frozen alice cannot receive, but recovery moves funds OUT of the
        // frozen wallet, bypassing gates.
        token.forceTransfer(alice, bob, 250 ether);
        assertEq(token.balanceOf(alice), 750 ether);
        assertEq(token.balanceOf(bob), 250 ether);

        // Non-agents cannot force-move funds.
        vm.prank(stranger);
        vm.expectRevert(CompliantToken.NotAuthorized.selector);
        token.forceTransfer(alice, bob, 1 ether);
    }

    function test_UntrustedIssuerDoesNotVerify() public {
        address mallory = address(0xBA11);
        address erin = address(0xE121);
        Identity idErin = new Identity(abi.encode(manager));
        // Claim from an issuer nobody trusts.
        vm.prank(mallory);
        idErin.addClaim(TOPIC_KYC, 1, mallory, hex"1234", hex"abcd", "");
        ir.registerIdentity(erin, address(idErin), COUNTRY_OK);
        assertFalse(ir.isVerified(erin));
        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.mint(erin, 10 ether);
    }

    /// Core of the on-chain signature check: naming the trusted issuer is not
    /// enough — the claim must carry a valid issuer signature.
    function test_TrustedIssuerNameWithoutValidSignatureFails() public {
        address erin = address(0xE121);
        Identity idErin = new Identity(abi.encode(manager));
        // Management names the trusted issuer but supplies no valid signature.
        vm.prank(manager);
        idErin.addClaim(TOPIC_KYC, 1, issuer, hex"1234", hex"abcd", "");
        ir.registerIdentity(erin, address(idErin), COUNTRY_OK);
        assertFalse(ir.isVerified(erin));
        vm.expectRevert(CompliantToken.ReceiverNotVerified.selector);
        token.mint(erin, 10 ether);
    }

    /// A signature that is valid but bound to a different identity must fail.
    function test_SignatureForDifferentIdentityFails() public {
        address erin = address(0xE121);
        Identity idErin = new Identity(abi.encode(manager));
        bytes memory data = hex"abcd";
        bytes memory wrongSig = _sign(address(0xDEAD), TOPIC_KYC, data);
        vm.prank(manager);
        idErin.addClaim(TOPIC_KYC, 1, issuer, wrongSig, data, "");
        ir.registerIdentity(erin, address(idErin), COUNTRY_OK);
        assertFalse(ir.isVerified(erin));
    }
}
