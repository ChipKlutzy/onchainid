// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IdentityRegistry} from "../compliance/IdentityRegistry.sol";
import {ModularCompliance} from "../compliance/ModularCompliance.sol";

/// @title CompliantToken — ERC-20 gated on ERC-3643 identity verification
/// @notice `mint` and every transfer require the receiver to be verified
///         (`IdentityRegistry.isVerified`) and the move to pass the
///         `ModularCompliance` country-allowlist + freeze gate. Minimal
///         self-contained ERC-20 (no external dependencies).
contract CompliantToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;
    mapping(address => bool) private _agents;

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event ComplianceBound(address indexed compliance_);
    event IdentityRegistryBound(address indexed registry);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);

    error NotAuthorized();
    error ReceiverNotVerified();
    error TransferBlockedByCompliance();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

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
    ) {
        if (identityRegistry_ == address(0) || compliance_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        name = name_;
        symbol = symbol_;
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
        if (to == address(0)) revert ZeroAddress();
        if (!identityRegistry.isVerified(to)) revert ReceiverNotVerified();
        if (!compliance.canTransfer(address(0), to)) revert TransferBlockedByCompliance();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn `amount` from the caller.
    function burn(uint256 amount) external {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Agent-only recovery: move `amount` from `from` to `to`,
    ///         bypassing verification and compliance gates (standard ERC-3643
    ///         recovery semantics for frozen / lost wallets).
    function forceTransfer(address from, address to, uint256 amount) external onlyAgent {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (!identityRegistry.isVerified(to)) revert ReceiverNotVerified();
        if (!compliance.canTransfer(from, to)) revert TransferBlockedByCompliance();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
