// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title RateLimitBuckets
 * @notice Library containing keccak256 hashed keys for various rate-limited actions.
 */
library RateLimitBuckets {
    bytes32 constant PLACE_ORDER = keccak256("PLACE_ORDER");
    bytes32 constant CANCEL_ORDER = keccak256("CANCEL_ORDER");
    bytes32 constant EXECUTE_MARKET_ORDER = keccak256("EXECUTE_MARKET_ORDER");
    bytes32 constant ADD_LIQUIDITY = keccak256("ADD_LIQUIDITY");
    bytes32 constant APPLY_FUNDING = keccak256("APPLY_FUNDING");
    bytes32 constant REMOVE_LIQUIDITY = keccak256("REMOVE_LIQUIDITY");
    bytes32 constant BORROW_AGAINST_ORDER = keccak256("BORROW_AGAINST_ORDER");
    bytes32 constant STAKE_ORDER_NFT = keccak256("STAKE_ORDER_NFT");
    bytes32 constant CREATE_BASKET = keccak256("CREATE_BASKET");
    bytes32 constant REBALANCE_BASKET = keccak256("REBALANCE_BASKET");
    bytes32 constant PLACE_EVENT_BET = keccak256("PLACE_EVENT_BET");
    bytes32 constant EXECUTE_TWAP = keccak256("EXECUTE_TWAP");
    bytes32 constant CREATE_SCALE_ORDER = keccak256("CREATE_SCALE_ORDER");
    bytes32 constant LIQUIDATE_POSITION = keccak256("LIQUIDATE_POSITION");
    bytes32 constant EXECUTE_ADL = keccak256("EXECUTE_ADL");
    bytes32 constant SETTLE_EVENT = keccak256("SETTLE_EVENT");
}
