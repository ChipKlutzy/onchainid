// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IdentityRegistry} from "../compliance/IdentityRegistry.sol";
import {ModularCompliance} from "../compliance/ModularCompliance.sol";

/// @title CompliantToken — ERC-20 gated on ERC-3643 identity verification
/// @notice Every mint and transfer requires the receiver to be verified
///         (`IdentityRegistry.isVerified`) and the move to pass the
///         `ModularCompliance` country-allowlist + freeze gate (enforced in
///         `_update`, so mint/transfer/transferFrom all share one gate).
contract CompliantToken is ERC20 {
    address public owner;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;
    mapping(address => bool) private _agents;
    /// @dev True while forceTransfer runs: recovery bypasses the gates.
    bool private _recovering;

    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event ComplianceBound(address indexed compliance_);
    event IdentityRegistryBound(address indexed registry);

    error NotAuthorized();
    error ReceiverNotVerified();
    error TransferBlockedByCompliance();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != owner && !_agents[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address identityRegistry_,
        address compliance_
    ) ERC20(name_, symbol_) {
        if (identityRegistry_ == address(0) || compliance_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        identityRegistry = IdentityRegistry(identityRegistry_);
        compliance = ModularCompliance(compliance_);
    }

    /// @notice Authorize a mint agent. Owner only.
    function addAgent(address agent) external onlyOwner {
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    /// @notice Deauthorize a mint agent. Owner only.
    function removeAgent(address agent) external onlyOwner {
        delete _agents[agent];
        emit AgentRemoved(agent);
    }

    /// @notice True when `agent` may mint.
    function isAgent(address agent) external view returns (bool) {
        return _agents[agent];
    }

    /// @notice Point the token at a new compliance module. Owner only.
    function setCompliance(address compliance_) external onlyOwner {
        if (compliance_ == address(0)) revert ZeroAddress();
        compliance = ModularCompliance(compliance_);
        emit ComplianceBound(compliance_);
    }

    /// @notice Point the token at a new identity registry. Owner only.
    function setIdentityRegistry(address registry) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        identityRegistry = IdentityRegistry(registry);
        emit IdentityRegistryBound(registry);
    }

    /// @notice Mint `amount` to a verified, compliance-passing receiver. Agent only.
    function mint(address to, uint256 amount) external onlyAgent {
        _mint(to, amount);
    }

    /// @notice Burn `amount` from the caller.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Agent-only recovery: move `amount` from `from` to `to`,
    ///         bypassing verification and compliance gates (standard ERC-3643
    ///         recovery semantics for frozen / lost wallets).
    function forceTransfer(address from, address to, uint256 amount) external onlyAgent {
        _recovering = true;
        _transfer(from, to, amount);
        _recovering = false;
    }

    /// @notice Single transfer gate for mint (from == 0), burns excluded
    ///         (to == 0), and all transfers: receiver verified + compliance.
    function _update(address from, address to, uint256 value) internal override {
        if (!_recovering && to != address(0)) {
            if (!identityRegistry.isVerified(to)) revert ReceiverNotVerified();
            if (!compliance.canTransfer(from, to)) revert TransferBlockedByCompliance();
        }
        super._update(from, to, value);
    }
}
