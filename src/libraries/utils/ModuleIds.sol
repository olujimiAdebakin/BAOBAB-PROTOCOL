// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ModuleIds
 * @notice Centralized registry of all module identifiers for the protocol
 */
library ModuleIds {
    bytes32 public constant POSITION_MANAGER = keccak256("POSITION_MANAGER");
    bytes32 public constant LIQUIDATION_ENGINE = keccak256("LIQUIDATION_ENGINE");
    bytes32 public constant ADL_ENGINE = keccak256("ADL_ENGINE");
    bytes32 public constant FUNDING_ENGINE = keccak256("FUNDING_ENGINE");
    bytes32 public constant ORACLE_REGISTRY = keccak256("ORACLE_REGISTRY");
    bytes32 public constant RISK_ENGINE = keccak256("RISK_ENGINE");
    bytes32 public constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");
}
