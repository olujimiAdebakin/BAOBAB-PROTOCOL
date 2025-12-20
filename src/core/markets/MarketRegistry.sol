// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";

/**
 * @title MarketRegistry
 * @author BAOBAB Protocol
 * @notice Central registry for all trading markets with configuration management
 * @dev Maintains market metadata, risk parameters, and enables market discovery
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      MARKET REGISTRY
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *
 * PURPOSE:
 * - Register and manage all trading markets in the protocol
 * - Store market metadata (baseAsset, quoteAsset, oracle, etc.)
 * - Maintain market risk parameters (leverage, margin requirements, fees)
 * - Enable market discovery by traders and external integrations
 * - Enforce market operational status (active, paused, closed)
 *
 * MARKET LIFECYCLE:
 * 1. CREATE: Admin registers new market with metadata and risk parameters
 * 2. ACTIVATE: Market becomes tradeable once oracle is configured
 * 3. TRADE: Traders can open/modify positions in active markets
 * 4. PAUSE: Admin can pause market for maintenance or risk mitigation
 * 5. RESUME: Paused market can be resumed for trading
 * 6. CLOSE: Market can be permanently closed (no new positions allowed)
 *
 * SUPPORTED ASSET CLASSES:
 * - CRYPTO: Bitcoin, Ethereum, altcoins (BTC/USD, ETH/USD)
 * - STOCK: Equities (DANGCEM, MTNN, ZENITHBANK)
 * - FOREX: Currency pairs (NGN/USD, GHS/USD, KES/USD)
 * - COMMODITY: Physical commodities (Gold, Brent Crude, Cocoa)
 */
contract MarketRegistry is SecurityBase {
    using AddressUtils for address;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice All registered markets indexed by marketId
    mapping(bytes32 => CommonStructs.Market) public markets;

    /// @notice Risk parameters for each market
    mapping(bytes32 => CommonStructs.RiskParameters) public riskParameters;

    /// @notice Array of all market IDs for enumeration
    bytes32[] public marketIds;

    /// @notice Mapping to check if a market ID exists
    mapping(bytes32 => bool) public marketExists;

    /// @notice Market ID counter for generating unique IDs
    uint256 private marketIdCounter;

    /// @notice Quote asset address for each market (for FeeCalculator integration)
    mapping(bytes32 => address) public marketQuoteAsset;

    /// @notice Base asset address for each market (optional, for advanced features)
    mapping(bytes32 => address) public marketBaseAsset;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new market is registered
     * @param marketId Unique identifier for the market
     * @param baseAsset Name of the base asset (e.g., "BTC")
     * @param quoteAsset Name of the quote asset (e.g., "USD")
     * @param assetClass Category of asset (CRYPTO, STOCK, FOREX, COMMODITY)
     * @param oracleAdapter Address of oracle providing prices
     */
    event MarketRegistered(
        bytes32 indexed marketId,
        string baseAsset,
        string quoteAsset,
        CommonStructs.AssetClass assetClass,
        address indexed oracleAdapter
    );

    /**
     * @notice Emitted when market risk parameters are updated
     * @param marketId Market identifier
     * @param maxLeverage New maximum leverage
     * @param maintenanceMarginBps New maintenance margin in basis points
     * @param liquidationFeeBps New liquidation fee in basis points
     * @param tradingFeeBps New trading fee in basis points
     */
    event RiskParametersUpdated(
        bytes32 indexed marketId,
        uint16 maxLeverage,
        uint16 maintenanceMarginBps,
        uint16 liquidationFeeBps,
        uint16 tradingFeeBps
    );

    /**
     * @notice Emitted when market status changes
     * @param marketId Market identifier
     * @param status New operational status
     */
    event MarketStatusChanged(bytes32 indexed marketId, CommonStructs.MarketStatus status);

    /**
     * @notice Emitted when oracle adapter is updated
     * @param marketId Market identifier
     * @param newOracle New oracle adapter address
     */
    event OracleAdapterUpdated(bytes32 indexed marketId, address indexed newOracle);

    /**
     * @notice Emitted when quote asset address is set
     * @param marketId Market identifier
     * @param quoteAssetAddress Token address of quote asset
     */
    event QuoteAssetSet(bytes32 indexed marketId, address indexed quoteAssetAddress);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when attempting to register a market that already exists
    error MarketRegistry__MarketAlreadyExists();

    /// @notice Thrown when market ID does not exist
    error MarketRegistry__MarketNotFound();

    /// @notice Thrown when invalid leverage is provided (zero or exceeding maximum)
    error MarketRegistry__InvalidLeverage();

    /// @notice Thrown when invalid margin parameters are provided
    error MarketRegistry__InvalidMarginParameters();

    /// @notice Thrown when oracle adapter address is invalid
    error MarketRegistry__InvalidOracleAdapter();

    /// @notice Thrown when attempting operation on inactive market
    error MarketRegistry__MarketInactive();

    /// @notice Thrown when quote asset is not configured
    error MarketRegistry__QuoteAssetNotConfigured();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize MarketRegistry with admin
     * @param _admin Protocol admin address
     */
    constructor(address _admin) {
        _admin.validateNotZero();
        BaobabAdmin = _admin;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Restrict access to only the protocol admin
    modifier onlyAdmin() {
        if (msg.sender != BaobabAdmin) revert MarketRegistry__Unauthorized();
        _;
    }

    /// @notice Verify market exists and is active
    modifier onlyActiveMarket(bytes32 marketId) {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        if (markets[marketId].status != CommonStructs.MarketStatus.ACTIVE) {
            revert MarketRegistry__MarketInactive();
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    REGISTRATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Register a new market in the protocol
     * @param baseAsset Name of base asset (e.g., "BTC", "DANGCEM")
     * @param quoteAsset Name of quote asset (e.g., "USD", "USDC")
     * @param assetClass Asset category (CRYPTO, STOCK, FOREX, COMMODITY)
     * @param oracleAdapter Address providing price feeds for this market
     * @param maxLeverage Maximum allowed leverage for this market
     * @param maintenanceMarginBps Maintenance margin requirement (basis points)
     * @param liquidationFeeBps Liquidation fee percentage (basis points)
     * @param maxOpenInterest Maximum total open interest allowed
     * @param tradingFeeBps Base trading fee (basis points)
     * @return marketId Unique identifier for the registered market
     *
     * @dev Flow:
     * 1. Validate inputs (leverage, margins, oracle)
     * 2. Generate unique market ID
     * 3. Store market metadata
     * 4. Store risk parameters
     * 5. Emit MarketRegistered event
     *
     * @dev Requirements:
     * - Caller must be protocol admin
     * - Market must not already exist
     * - Leverage must be between 1x and 100x
     * - Maintenance margin must be less than initial margin
     * - Oracle adapter must be valid contract
     */
    function registerMarket(
        string calldata baseAsset,
        string calldata quoteAsset,
        CommonStructs.AssetClass assetClass,
        address oracleAdapter,
        uint16 maxLeverage,
        uint16 maintenanceMarginBps,
        uint16 liquidationFeeBps,
        uint256 maxOpenInterest,
        uint16 tradingFeeBps
    ) external onlyAdmin returns (bytes32 marketId) {
        // Validate leverage
        if (maxLeverage < 1 || maxLeverage > 100) revert MarketRegistry__InvalidLeverage();

        // Validate margin parameters
        if (maintenanceMarginBps == 0 || maintenanceMarginBps >= 10000) {
            revert MarketRegistry__InvalidMarginParameters();
        }

        // Validate oracle adapter
        oracleAdapter.validateContract();

        // Generate unique market ID from base and quote assets
        marketId = keccak256(abi.encodePacked(baseAsset, quoteAsset, marketIdCounter++));

        // Check market doesn't already exist
        if (marketExists[marketId]) revert MarketRegistry__MarketAlreadyExists();

        // Create and store market
        markets[marketId] = CommonStructs.Market({
            marketId: marketId,
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            assetClass: assetClass,
            status: CommonStructs.MarketStatus.ACTIVE,
            createdAt: block.timestamp,
            oracleAdapter: oracleAdapter
        });

        // Store risk parameters
        riskParameters[marketId] = CommonStructs.RiskParameters({
            maxLeverage: maxLeverage,
            maintenanceMarginBps: maintenanceMarginBps,
            liquidationFeeBps: liquidationFeeBps,
            maxOpenInterest: maxOpenInterest,
            maxPositionSize: maxOpenInterest, // Default: max position = max OI
            tradingFeeBps: tradingFeeBps,
            fundingRateCoefficient: 1e18 // Default coefficient
        });

        // Mark market as existing and add to enumeration
        marketExists[marketId] = true;
        marketIds.push(marketId);

        emit MarketRegistered(marketId, baseAsset, quoteAsset, assetClass, oracleAdapter);

        return marketId;
    }

    /**
     * @notice Set the quote asset token address for a market (required for FeeCalculator)
     * @param marketId Market identifier
     * @param quoteAssetAddress Token address of the quote asset
     *
     * @dev This is critical for fee calculations:
     * - FeeCalculator.calculateTradingFeeTaker(asset, user, notional) requires asset address
     * - This mapping provides the bridge between marketId and actual token address
     * - Must be set before positions can be opened in the market
     */
    function setQuoteAsset(bytes32 marketId, address quoteAssetAddress)
        external
        onlyAdmin
    {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        quoteAssetAddress.validateContract();

        marketQuoteAsset[marketId] = quoteAssetAddress;
        emit QuoteAssetSet(marketId, quoteAssetAddress);
    }

    /**
     * @notice Set the base asset token address for a market (optional, for advanced features)
     * @param marketId Market identifier
     * @param baseAssetAddress Token address of the base asset
     */
    function setBaseAsset(bytes32 marketId, address baseAssetAddress)
        external
        onlyAdmin
    {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        baseAssetAddress.validateContract();

        marketBaseAsset[marketId] = baseAssetAddress;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    CONFIGURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update risk parameters for a market
     * @param marketId Market identifier
     * @param newMaxLeverage New maximum leverage
     * @param newMaintenanceMarginBps New maintenance margin in basis points
     * @param newLiquidationFeeBps New liquidation fee in basis points
     * @param newMaxOpenInterest New maximum open interest
     * @param newTradingFeeBps New base trading fee in basis points
     *
     * @dev Can be used to adjust market risk dynamically
     * @dev Requirements:
     * - Caller must be protocol admin
     * - Market must exist
     * - Leverage must be 1-100x
     * - Margins must be valid (non-zero, less than 100%)
     */
    function updateRiskParameters(
        bytes32 marketId,
        uint16 newMaxLeverage,
        uint16 newMaintenanceMarginBps,
        uint16 newLiquidationFeeBps,
        uint256 newMaxOpenInterest,
        uint16 newTradingFeeBps
    ) external onlyAdmin {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        if (newMaxLeverage < 1 || newMaxLeverage > 100) {
            revert MarketRegistry__InvalidLeverage();
        }
        if (newMaintenanceMarginBps == 0 || newMaintenanceMarginBps >= 10000) {
            revert MarketRegistry__InvalidMarginParameters();
        }

        riskParameters[marketId].maxLeverage = newMaxLeverage;
        riskParameters[marketId].maintenanceMarginBps = newMaintenanceMarginBps;
        riskParameters[marketId].liquidationFeeBps = newLiquidationFeeBps;
        riskParameters[marketId].maxOpenInterest = newMaxOpenInterest;
        riskParameters[marketId].tradingFeeBps = newTradingFeeBps;

        emit RiskParametersUpdated(
            marketId,
            newMaxLeverage,
            newMaintenanceMarginBps,
            newLiquidationFeeBps,
            newTradingFeeBps
        );
    }

    /**
     * @notice Update oracle adapter for a market
     * @param marketId Market identifier
     * @param newOracleAdapter New oracle adapter address
     *
     * @dev Allows switching oracle providers if needed
     * @dev Requirements:
     * - Caller must be protocol admin
     * - Market must exist
     * - New adapter must be valid contract
     */
    function updateOracleAdapter(bytes32 marketId, address newOracleAdapter)
        external
        onlyAdmin
    {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        newOracleAdapter.validateContract();

        markets[marketId].oracleAdapter = newOracleAdapter;
        emit OracleAdapterUpdated(marketId, newOracleAdapter);
    }

    /**
     * @notice Pause a market (no new positions allowed)
     * @param marketId Market identifier
     *
     * @dev Used for maintenance, risk mitigation, or emergency scenarios
     */
    function pauseMarket(bytes32 marketId) external onlyAdmin {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        markets[marketId].status = CommonStructs.MarketStatus.PAUSED;
        emit MarketStatusChanged(marketId, CommonStructs.MarketStatus.PAUSED);
    }

    /**
     * @notice Resume a paused market
     * @param marketId Market identifier
     */
    function resumeMarket(bytes32 marketId) external onlyAdmin {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        markets[marketId].status = CommonStructs.MarketStatus.ACTIVE;
        emit MarketStatusChanged(marketId, CommonStructs.MarketStatus.ACTIVE);
    }

    /**
     * @notice Close a market permanently (no new positions, existing can close)
     * @param marketId Market identifier
     */
    function closeMarket(bytes32 marketId) external onlyAdmin {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        markets[marketId].status = CommonStructs.MarketStatus.CLOSED;
        emit MarketStatusChanged(marketId, CommonStructs.MarketStatus.CLOSED);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get market by ID
     * @param marketId Market identifier
     * @return Market struct with all metadata
     */
    function getMarket(bytes32 marketId)
        external
        view
        returns (CommonStructs.Market memory)
    {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        return markets[marketId];
    }

    /**
     * @notice Get risk parameters for a market
     * @param marketId Market identifier
     * @return Risk parameters struct
     */
    function getRiskParameters(bytes32 marketId)
        external
        view
        returns (CommonStructs.RiskParameters memory)
    {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        return riskParameters[marketId];
    }

    /**
     * @notice Get quote asset address for a market
     * @param marketId Market identifier
     * @return Address of the quote asset token
     *
     * @dev Used by PositionManager to integrate with FeeCalculator
     * @dev Reverts if quote asset not configured
     */
    function getQuoteAsset(bytes32 marketId) external view returns (address) {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        address quoteAsset = marketQuoteAsset[marketId];
        if (quoteAsset == address(0)) revert MarketRegistry__QuoteAssetNotConfigured();
        return quoteAsset;
    }

    /**
     * @notice Get base asset address for a market (if configured)
     * @param marketId Market identifier
     * @return Address of the base asset token (may be zero if not configured)
     */
    function getBaseAsset(bytes32 marketId) external view returns (address) {
        if (!marketExists[marketId]) revert MarketRegistry__MarketNotFound();
        return marketBaseAsset[marketId];
    }

    /**
     * @notice Get all market IDs
     * @return Array of all registered market IDs
     */
    function getAllMarkets() external view returns (bytes32[] memory) {
        return marketIds;
    }

    /**
     * @notice Get number of registered markets
     * @return Count of markets
     */
    function getMarketCount() external view returns (uint256) {
        return marketIds.length;
    }

    /**
     * @notice Check if a market is active
     * @param marketId Market identifier
     * @return True if market exists and is in ACTIVE status
     */
    function isMarketActive(bytes32 marketId) external view returns (bool) {
        return marketExists[marketId]
            && markets[marketId].status == CommonStructs.MarketStatus.ACTIVE;
    }

    /**
     * @notice Check if a market exists
     * @param marketId Market identifier
     * @return True if market is registered
     */
    function isMarketExists(bytes32 marketId) external view returns (bool) {
        return marketExists[marketId];
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                        ADMIN STORAGE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    address public BaobabAdmin;

    error MarketRegistry__Unauthorized();
}
