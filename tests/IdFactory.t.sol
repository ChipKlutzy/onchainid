// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IdFactory} from "../contracts/IdFactory.sol";
import {Identity} from "../contracts/Identity.sol";

/// @notice CREATE2 deterministic deployment coverage for IdFactory.
///         Same (salt, managementKey) => same address on every chain where the
///         factory itself lives at the same address (cross-chain consistency).
contract IdFactoryTest is Test {
    IdFactory private factory;
    address private manager = address(0xA11CE);

    function setUp() public {
        factory = new IdFactory();
    }

    function test_ComputeMatchesDeploy() public {
        bytes32 salt = keccak256("user-1");
        bytes memory key = abi.encode(manager);
        address predicted = factory.computeAddress(salt, key);
        address deployed = factory.createIdentity(salt, key);
        assertEq(deployed, predicted);
    }

    function test_SameSaltSameKeySameAddress() public {
        bytes32 salt = keccak256("user-2");
        bytes memory key = abi.encode(manager);
        address first = factory.createIdentity(salt, key);
        // Second deploy with identical inputs must revert (already deployed).
        vm.expectRevert(IdFactory.AlreadyDeployed.selector);
        factory.createIdentity(salt, key);
        // ...and the predicted address is unchanged.
        assertEq(factory.computeAddress(salt, key), first);
    }

    function test_DifferentSaltDifferentAddress() public {
        bytes memory key = abi.encode(manager);
        address a = factory.createIdentity(keccak256("user-a"), key);
        address b = factory.createIdentity(keccak256("user-b"), key);
        assertTrue(a != b);
    }

    function test_DifferentKeyDifferentAddress() public {
        bytes32 salt = keccak256("shared-salt");
        address a = factory.createIdentity(salt, abi.encode(manager));
        address b = factory.createIdentity(salt, abi.encode(address(0xBEEF)));
        assertTrue(a != b);
    }

    function test_DeployedIdentityIsFunctional() public {
        bytes32 salt = keccak256("user-3");
        address deployed = factory.createIdentity(salt, abi.encode(manager));
        Identity id_ = Identity(deployed);
        assertTrue(id_.keyHasPurpose(keccak256(abi.encode(manager)), 1));
    }
}
