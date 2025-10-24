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
        bytes32 finalSalt = _finalSalt(salt, managementKey);
        address predicted = _computeAddress(finalSalt, keccak256(_bytecode(managementKey)));
        if (predicted.code.length != 0) revert AlreadyDeployed();
        identity = address(new Identity{salt: finalSalt}(managementKey));
        if (identity != predicted) revert DeploymentFailed();
        emit IdentityDeployed(identity, salt, abi.decode(managementKey, (address)));
    }

    /// @notice Predict the deployment address without deploying.
    function computeAddress(bytes32 salt, bytes memory managementKey) external view returns (address) {
        return _computeAddress(_finalSalt(salt, managementKey), keccak256(_bytecode(managementKey)));
    }

    function _finalSalt(bytes32 salt, bytes memory managementKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(salt, keccak256(managementKey)));
    }

    function _bytecode(bytes memory managementKey) internal pure returns (bytes memory) {
        return abi.encodePacked(type(Identity).creationCode, abi.encode(managementKey));
    }

    function _computeAddress(bytes32 finalSalt, bytes32 bytecodeHash) internal view returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), finalSalt, bytecodeHash)))));
    }
}
