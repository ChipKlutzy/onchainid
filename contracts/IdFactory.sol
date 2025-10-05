// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Identity} from "./Identity.sol";

/// @title IdFactory — deterministic CREATE2 deployment of Identity contracts
/// @notice The same (salt, managementKey) always resolves to the same address
///         on every chain where this factory is deployed at the same address,
///         giving cross-chain address consistency for identities.
contract IdFactory {
    event IdentityDeployed(address indexed identity, bytes32 indexed salt, address indexed managementKey);

    error AlreadyDeployed();
    error DeploymentFailed();

    /// @notice Deploy an Identity with CREATE2.
    /// @param salt Caller-chosen salt (e.g. keccak256(userId)).
    /// @param managementKey Raw key bytes for the identity's first MANAGEMENT key.
    function createIdentity(bytes32 salt, bytes memory managementKey) external returns (address identity) {
        bytes32 finalSalt = keccak256(abi.encode(salt, keccak256(managementKey)));
        bytes memory bytecode = abi.encodePacked(type(Identity).creationCode, abi.encode(managementKey));
        bytes32 bytecodeHash = keccak256(bytecode);
        address predicted = _computeAddress(finalSalt, bytecodeHash);
        if (predicted.code.length != 0) revert AlreadyDeployed();
        assembly {
            identity := create2(0, add(bytecode, 0x20), mload(bytecode), finalSalt)
        }
        if (identity == address(0) || identity != predicted) revert DeploymentFailed();
        emit IdentityDeployed(identity, salt, abi.decode(managementKey, (address)));
    }

    /// @notice Predict the deployment address without deploying.
    function computeAddress(bytes32 salt, bytes memory managementKey) external view returns (address) {
        bytes32 finalSalt = keccak256(abi.encode(salt, keccak256(managementKey)));
        bytes memory bytecode = abi.encodePacked(type(Identity).creationCode, abi.encode(managementKey));
        return _computeAddress(finalSalt, keccak256(bytecode));
    }

    function _computeAddress(bytes32 finalSalt, bytes32 bytecodeHash) internal view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), finalSalt, bytecodeHash))))
        );
    }
}
