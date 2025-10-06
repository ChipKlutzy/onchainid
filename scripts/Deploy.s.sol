// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IdFactory} from "../contracts/IdFactory.sol";
import {ClaimIssuer} from "../contracts/ClaimIssuer.sol";

/// @title Deploy — Anvil + Sepolia deployment script (P1 onchainid-core, P2 claim-issuer)
/// @notice Targets:
///           Anvil:   forge script scripts/Deploy.s.sol --rpc-url anvil --broadcast
///           Sepolia: forge script scripts/Deploy.s.sol --rpc-url sepolia --broadcast --verify
///         Required env: DEPLOYER_PRIVATE_KEY, INITIAL_CLAIM_SIGNER.
///         Optional env: SEPOLIA_RPC_URL (for the `sepolia` rpc alias).
/// @dev DO NOT run a live (Sepolia/mainnet) deploy without explicit board
///      approval on the tracking issue.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address initialSigner = vm.envAddress("INITIAL_CLAIM_SIGNER");

        vm.startBroadcast(deployerKey);

        IdFactory factory = new IdFactory();
        console.log("IdFactory deployed at:", address(factory));

        ClaimIssuer claimIssuer = new ClaimIssuer(initialSigner);
        console.log("ClaimIssuer deployed at:", address(claimIssuer));
        console.log("ClaimIssuer.signer:", claimIssuer.signer());

        vm.stopBroadcast();
    }
}
