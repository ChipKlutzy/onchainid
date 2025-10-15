// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ClaimTopicsRegistry} from "../contracts/compliance/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../contracts/compliance/TrustedIssuersRegistry.sol";
import {IdentityRegistryStorage} from "../contracts/compliance/IdentityRegistryStorage.sol";
import {IdentityRegistry} from "../contracts/compliance/IdentityRegistry.sol";
import {ModularCompliance} from "../contracts/compliance/ModularCompliance.sol";
import {CompliantToken} from "../contracts/token/CompliantToken.sol";

/// @title DeployRWA — Anvil + Sepolia deployment script (P3 rwa-token)
/// @notice Targets:
///           Anvil:   forge script scripts/DeployRWA.s.sol --rpc-url anvil --broadcast
///           Sepolia: forge script scripts/DeployRWA.s.sol --rpc-url sepolia --broadcast --verify
///         Required env: DEPLOYER_PRIVATE_KEY, TRUSTED_ISSUER, ALLOWED_COUNTRY.
///         TRUSTED_ISSUER is the ClaimIssuer contract address (from Deploy.s.sol);
///         IdentityRegistry verifies claim signatures against it.
///         Optional env: TOKEN_NAME, TOKEN_SYMBOL, KYC_TOPIC, SEPOLIA_RPC_URL.
/// @dev DO NOT run a live (Sepolia/mainnet) deploy without explicit board
///      approval on the tracking issue + SecurityEngineer review gate.
contract DeployRWA is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address trustedIssuer = vm.envAddress("TRUSTED_ISSUER");
        uint16 allowedCountry = uint16(vm.envUint("ALLOWED_COUNTRY"));
        string memory tokenName = vm.envOr("TOKEN_NAME", string("RWA Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("RWA"));
        uint256 kycTopic = vm.envOr("KYC_TOPIC", uint256(1));

        vm.startBroadcast(deployerKey);

        ClaimTopicsRegistry ctr = new ClaimTopicsRegistry();
        ctr.addClaimTopic(kycTopic);
        console.log("ClaimTopicsRegistry:", address(ctr));

        TrustedIssuersRegistry tir = new TrustedIssuersRegistry();
        uint256[] memory topics = new uint256[](1);
        topics[0] = kycTopic;
        tir.addTrustedIssuer(trustedIssuer, topics);
        console.log("TrustedIssuersRegistry:", address(tir));

        IdentityRegistryStorage irs = new IdentityRegistryStorage();
        console.log("IdentityRegistryStorage:", address(irs));

        IdentityRegistry ir = new IdentityRegistry(address(ctr), address(tir), address(irs));
        irs.addAgent(address(ir));
        console.log("IdentityRegistry:", address(ir));

        ModularCompliance mc = new ModularCompliance(address(ir));
        mc.setCountryAllowed(allowedCountry, true);
        console.log("ModularCompliance:", address(mc));

        CompliantToken token = new CompliantToken(tokenName, tokenSymbol, address(ir), address(mc));
        mc.bindToken(address(token));
        console.log("CompliantToken:", address(token));

        vm.stopBroadcast();
    }
}
