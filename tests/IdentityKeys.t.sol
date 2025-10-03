// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Identity} from "../contracts/Identity.sol";

/// @notice Key add/remove (ERC-734) coverage for Identity.
contract IdentityKeyTest is Test {
    Identity private id_;
    address private manager = address(0xA11CE);
    address private action = address(0xAC710);
    address private stranger = address(0xBAD);

    function setUp() public {
        id_ = new Identity(abi.encode(manager));
    }

    function _purposes(uint256 a) internal pure returns (uint256[] memory p) {
        p = new uint256[](1);
        p[0] = a;
    }

    function test_ManagerKeyExistsAtDeploy() public view {
        bytes32 keyId = keccak256(abi.encode(manager));
        assertTrue(id_.keyHasPurpose(keyId, 1));
        (uint256 keyType,,) = id_.getKey(keyId);
        assertEq(keyType, 1);
    }

    function test_AddKey() public {
        vm.prank(manager);
        uint256[] memory p = _purposes(2); // ACTION
        id_.addKey(abi.encode(action), p, 1);
        bytes32 keyId = keccak256(abi.encode(action));
        assertTrue(id_.keyHasPurpose(keyId, 2));
        assertFalse(id_.keyHasPurpose(keyId, 1));
    }

    function test_RemoveKey() public {
        vm.prank(manager);
        id_.addKey(abi.encode(action), _purposes(2), 1);
        bytes32 keyId = keccak256(abi.encode(action));
        vm.prank(manager);
        id_.removeKey(keyId);
        assertFalse(id_.keyHasPurpose(keyId, 2));
        vm.expectRevert(Identity.KeyNotFound.selector);
        id_.getKey(keyId);
    }

    function test_NonManagerCannotAddKey() public {
        vm.prank(stranger);
        vm.expectRevert(Identity.NotManagementKey.selector);
        id_.addKey(abi.encode(stranger), _purposes(2), 1);
    }

    function test_NonManagerCannotRemoveKey() public {
        bytes32 keyId = keccak256(abi.encode(manager));
        vm.prank(stranger);
        vm.expectRevert(Identity.NotManagementKey.selector);
        id_.removeKey(keyId);
    }

    function test_AddDuplicateKeyReverts() public {
        vm.prank(manager);
        vm.expectRevert(Identity.KeyAlreadyExists.selector);
        id_.addKey(abi.encode(manager), _purposes(2), 1);
    }

    function test_RemoveMissingKeyReverts() public {
        vm.prank(manager);
        vm.expectRevert(Identity.KeyNotFound.selector);
        id_.removeKey(bytes32(uint256(0xDEAD)));
    }

    function test_ActionKeyCanExecute() public {
        vm.prank(manager);
        id_.addKey(abi.encode(action), _purposes(2), 1);
        vm.prank(action);
        uint256 execId = id_.execute(address(0xCAFE), 0, hex"");
        assertEq(execId, 0);
    }
}
