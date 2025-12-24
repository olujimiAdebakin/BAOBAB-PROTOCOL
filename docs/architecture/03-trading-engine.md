# BAOBAB Trading Engine Architecture

**Institutional-grade perpetual futures and spot trading with unified cross-margin collateral**

Built for capital efficiency, African market accessibility, and composable Order NFTs.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     Trading Engine Core                       │
│                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐    │
│  │ PerpEngine  │  │ SpotEngine  │  │ CrossMarginEngine│    │
│  │             │  │             │  │                  │    │
│  │ • Leverage  │  │ • AMM Swaps │  │ • Portfolio Mgmt │    │
│  │ • Funding   │  │ • Limit     │  │ • Risk Calc      │    │
│  │ • P&L       │  │ • DEX Route │  │ • Liquidation    │    │
│  └──────┬──────┘  └──────┬──────┘  └────────┬─────────┘    │
│         │                │                   │               │
│         └────────────────┴───────────────────┘               │
│                          ↓                                   │
│         ┌────────────────────────────────┐                  │
│         │    Shared Risk Engine          │                  │
│         │  • Margin checks               │                  │
│         │  • Position limits             │                  │
│         │  • Circuit breakers            │                  │
│         └────────────────────────────────┘                  │
└──────────────────────────────────────────────────────────────┘
                          ↓
              ┌────────────────────┐
              │  Oracle Registry   │
              │  • Pyth (crypto)   │
              │  • Chainlink       │
              │  • TWAP            │
              │  • Trusted (Africa)│
              └────────────────────┘
```

## Core Contracts

### 1. PerpEngine - Perpetual Futures

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PerpEngine is ReentrancyGuard {
    struct Position {
        address user;
        address market;
        bool isLong;
        uint256 size;              // Position size in base currency
        uint256 collateral;        // Collateral posted
        uint256 entryPrice;        // Entry price
        uint256 entryFundingRate;  // Funding rate at entry
        uint256 lastUpdateTime;    // Last interaction timestamp
        uint256 leverage;          // Actual leverage used
    }
    
    struct Market {
        address baseAsset;
        address quoteAsset;
        uint256 maxLeverage;           // Max 100x
        uint256 initialMarginRate;     // e.g., 1000 = 10%
        uint256 maintenanceMarginRate; // e.g., 500 = 5%
        uint256 fundingRate;           // Current funding rate
        uint256 lastFundingUpdate;     // Last funding calculation
        uint256 openInterestLong;      // Total long exposure
        uint256 openInterestShort;     // Total short exposure
        uint256 maxPositionSize;       // Absolute position limit
        bool isPaused;
    }
    
    // State
    mapping(address => Market) public markets;
    mapping(address => mapping(address => Position[])) public positions; // user => market => positions
    mapping(address => uint256) public totalCollateral; // Cross-margin tracking
    
    ICrossMarginEngine public crossMarginEngine;
    IOracleRegistry public oracleRegistry;
    ILiquidationEngine public liquidationEngine;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant FUNDING_INTERVAL = 8 hours;
    uint256 public constant MAX_LEVERAGE = 100;
    uint256 public constant LIQUIDATION_FEE = 500; // 5%
    
    event PositionOpened(
        address indexed user,
        address indexed market,
        uint256 positionId,
        bool isLong,
        uint256 size,
        uint256 leverage,
        uint256 entryPrice
    );
    
    event PositionClosed(
        address indexed user,
        address indexed market,
        uint256 positionId,
        int256 pnl,
        uint256 exitPrice
    );
    
    event FundingRateUpdated(
        address indexed market,
        int256 fundingRate,
        uint256 timestamp
    );
    
    event PositionLiquidated(
        address indexed user,
        address indexed market,
        uint256 positionId,
        address liquidator,
        uint256 liquidationPrice
    );
    
    // Open perpetual position
    function openPosition(
        address market,
        bool isLong,
        uint256 size,
        uint256 collateralAmount,
        uint256 maxSlippage
    ) external nonReentrant returns (uint256 positionId) {
        require(!markets[market].isPaused, "Market paused");
        require(size > 0 && collateralAmount > 0, "Invalid amounts");
        
        Market storage mkt = markets[market];
        
        // Calculate leverage
        uint256 leverage = (size * 1e18) / collateralAmount;
        require(leverage <= mkt.maxLeverage * 1e18, "Leverage too high");
        
        // Check position limits
        uint256 maxAllowed = _getMaxPositionSize(market, msg.sender);
        require(size <= maxAllowed, "Exceeds position limit");
        
        // Get current price with slippage check
        uint256 entryPrice = oracleRegistry.getPrice(market);
        uint256 slippage = _calculateSlippage(market, isLong, size);
        require(slippage <= maxSlippage, "Slippage too high");
        
        if (isLong) {
            entryPrice = entryPrice + (entryPrice * slippage / BASIS_POINTS);
        } else {
            entryPrice = entryPrice - (entryPrice * slippage / BASIS_POINTS);
        }
        
        // Transfer collateral to cross-margin engine
        crossMarginEngine.depositCollateral(msg.sender, collateralAmount);
        
        // Update funding rate
        _updateFundingRate(market);
        
        // Create position
        Position memory newPosition = Position({
            user: msg.sender,
            market: market,
            isLong: isLong,
            size: size,
            collateral: collateralAmount,
            entryPrice: entryPrice,
            entryFundingRate: mkt.fundingRate,
            lastUpdateTime: block.timestamp,
            leverage: leverage / 1e18
        });
        
        positions[msg.sender][market].push(newPosition);
        positionId = positions[msg.sender][market].length - 1;
        
        // Update open interest
        if (isLong) {
            mkt.openInterestLong += size;
        } else {
            mkt.openInterestShort += size;
        }
        
        emit PositionOpened(
            msg.sender,
            market,
            positionId,
            isLong,
            size,
            leverage / 1e18,
            entryPrice
        );
    }
    
    // Close position
    function closePosition(
        address market,
        uint256 positionId,
        uint256 sizeDelta
    ) external nonReentrant returns (int256 pnl) {
        Position storage position = positions[msg.sender][market][positionId];
        require(position.size > 0, "Position doesn't exist");
        require(sizeDelta <= position.size, "Size exceeds position");
        
        // Update funding
        _updateFundingRate(market);
        
        // Get exit price
        uint256 exitPrice = oracleRegistry.getPrice(market);
        
        // Calculate P&L
        pnl = _calculatePnL(position, exitPrice, sizeDelta);
        
        // Calculate funding payment
        int256 fundingPayment = _calculateFundingPayment(position, sizeDelta);
        pnl -= fundingPayment;
        
        // Update position
        uint256 collateralReturned = (position.collateral * sizeDelta) / position.size;
        
        if (sizeDelta == position.size) {
            // Full close
            delete positions[msg.sender][market][positionId];
        } else {
            // Partial close
            position.size -= sizeDelta;
            position.collateral -= collateralReturned;
        }
        
        // Update open interest
        if (position.isLong) {
            markets[market].openInterestLong -= sizeDelta;
        } else {
            markets[market].openInterestShort -= sizeDelta;
        }
        
        // Settle P&L with cross-margin engine
        if (pnl > 0) {
            crossMarginEngine.creditProfit(msg.sender, uint256(pnl));
        } else {
            crossMarginEngine.debitLoss(msg.sender, uint256(-pnl));
        }
        
        // Return collateral
        crossMarginEngine.withdrawCollateral(msg.sender, collateralReturned);
        
        emit PositionClosed(msg.sender, market, positionId, pnl, exitPrice);
    }
    
    // Update funding rate (called every 8 hours)
    function updateFundingRate(address market) external returns (int256) {
        require(
            block.timestamp >= markets[market].lastFundingUpdate + FUNDING_INTERVAL,
            "Too early"
        );
        
        return _updateFundingRate(market);
    }
    
    function _updateFundingRate(address market) internal returns (int256) {
        Market storage mkt = markets[market];
        
        // Get mark price and spot price
        uint256 markPrice = oracleRegistry.getPrice(market);
        uint256 spotPrice = oracleRegistry.getSpotPrice(market);
        
        // Calculate premium
        int256 premium = int256(markPrice) - int256(spotPrice);
        int256 premiumRate = (premium * 1e18) / int256(spotPrice);
        
        // Apply time factor (8-hour funding)
        int256 fundingRate = (premiumRate * int256(FUNDING_INTERVAL)) / int256(365 days);
        
        mkt.fundingRate = uint256(fundingRate > 0 ? fundingRate : -fundingRate);
        mkt.lastFundingUpdate = block.timestamp;
        
        emit FundingRateUpdated(market, fundingRate, block.timestamp);
        return fundingRate;
    }
    
    // Liquidate underwater position
    function liquidatePosition(
        address user,
        address market,
        uint256 positionId
    ) external nonReentrant {
        Position storage position = positions[user][market][positionId];
        require(position.size > 0, "Position doesn't exist");
        
        // Check if liquidatable
        uint256 currentPrice = oracleRegistry.getPrice(market);
        require(_isLiquidatable(position, currentPrice), "Position healthy");
        
        // Calculate liquidation values
        int256 pnl = _calculatePnL(position, currentPrice, position.size);
        int256 fundingPayment = _calculateFundingPayment(position, position.size);
        
        int256 totalPnL = pnl - fundingPayment;
        uint256 liquidationFee = (position.collateral * LIQUIDATION_FEE) / BASIS_POINTS;
        
        // Liquidator reward (5% of collateral)
        payable(msg.sender).transfer(liquidationFee);
        
        // Update open interest
        if (position.isLong) {
            markets[market].openInterestLong -= position.size;
        } else {
            markets[market].openInterestShort -= position.size;
        }
        
        // Handle bad debt
        if (totalPnL < -int256(position.collateral)) {
            // Position in bad debt - insurance fund covers
            uint256 badDebt = uint256(-totalPnL) - position.collateral;
            liquidationEngine.coverBadDebt(badDebt);
        }
        
        // Delete position
        delete positions[user][market][positionId];
        
        emit PositionLiquidated(user, market, positionId, msg.sender, currentPrice);
    }
    
    // Calculate P&L
    function _calculatePnL(
        Position memory position,
        uint256 exitPrice,
        uint256 sizeDelta
    ) internal pure returns (int256) {
        int256 priceDiff;
        
        if (position.isLong) {
            priceDiff = int256(exitPrice) - int256(position.entryPrice);
        } else {
            priceDiff = int256(position.entryPrice) - int256(exitPrice);
        }
        
        // PnL = (price difference × size) / entry price
        int256 pnl = (priceDiff * int256(sizeDelta)) / int256(position.entryPrice);
        return pnl;
    }
    
    // Calculate funding payment
    function _calculateFundingPayment(
        Position memory position,
        uint256 sizeDelta
    ) internal view returns (int256) {
        Market storage mkt = markets[position.market];
        
        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        uint256 fundingRate = mkt.fundingRate;
        
        int256 payment = int256(
            (sizeDelta * fundingRate * timeElapsed) / (365 days * BASIS_POINTS)
        );
        
        // Longs pay when funding positive, shorts pay when negative
        return position.isLong ? payment : -payment;
    }
    
    // Check if position is liquidatable
    function _isLiquidatable(
        Position memory position,
        uint256 currentPrice
    ) internal view returns (bool) {
        int256 unrealizedPnL = _calculatePnL(position, currentPrice, position.size);
        int256 fundingPayment = _calculateFundingPayment(position, position.size);
        
        int256 accountValue = int256(position.collateral) + unrealizedPnL - fundingPayment;
        
        Market storage mkt = markets[position.market];
        uint256 maintenanceMargin = (position.size * mkt.maintenanceMarginRate) / BASIS_POINTS;
        
        return accountValue <= int256(maintenanceMargin);
    }
    
    // Calculate slippage based on trade size
    function _calculateSlippage(
        address market,
        bool isLong,
        uint256 size
    ) internal view returns (uint256) {
        Market storage mkt = markets[market];
        uint256 totalOI = mkt.openInterestLong + mkt.openInterestShort;
        
        if (totalOI == 0) return 0;
        
        // 0.1% slippage per 1% of open interest
        uint256 impactBps = (size * 1000) / totalOI;
        return impactBps > 1000 ? 1000 : impactBps; // Cap at 10%
    }
    
    // Get max position size for user
    function _getMaxPositionSize(
        address market,
        address user
    ) internal view returns (uint256) {
        Market storage mkt = markets[market];
        
        // 1. Absolute limit per market
        uint256 maxByMarket = mkt.maxPositionSize;
        
        // 2. 10% of total open interest
        uint256 totalOI = mkt.openInterestLong + mkt.openInterestShort;
        uint256 maxByOI = totalOI / 10;
        
        // 3. Based on user's collateral
        uint256 accountValue = crossMarginEngine.getAccountValue(user);
        uint256 maxByCollateral = accountValue * mkt.maxLeverage;
        
        // Return minimum of all limits
        uint256 limit = maxByMarket;
        if (maxByOI < limit) limit = maxByOI;
        if (maxByCollateral < limit) limit = maxByCollateral;
        
        return limit;
    }
    
    // Get position details
    function getPosition(
        address user,
        address market,
        uint256 positionId
    ) external view returns (
        Position memory position,
        int256 unrealizedPnL,
        uint256 liquidationPrice,
        uint256 marginRatio
    ) {
        position = positions[user][market][positionId];
        require(position.size > 0, "Position doesn't exist");
        
        uint256 currentPrice = oracleRegistry.getPrice(market);
        unrealizedPnL = _calculatePnL(position, currentPrice, position.size);
        
        liquidationPrice = _calculateLiquidationPrice(position);
        
        int256 accountValue = int256(position.collateral) + unrealizedPnL;
        Market storage mkt = markets[market];
        uint256 maintenanceMargin = (position.size * mkt.maintenanceMarginRate) / BASIS_POINTS;
        
        marginRatio = accountValue > 0 
            ? (uint256(accountValue) * BASIS_POINTS) / maintenanceMargin
            : 0;
    }
    
    function _calculateLiquidationPrice(
        Position memory position
    ) internal view returns (uint256) {
        Market storage mkt = markets[position.market];
        uint256 maintenanceMargin = (position.size * mkt.maintenanceMarginRate) / BASIS_POINTS;
        
        int256 maxLoss = int256(position.collateral) - int256(maintenanceMargin);
        int256 priceDiff = (maxLoss * int256(position.entryPrice)) / int256(position.size);
        
        if (position.isLong) {
            return uint256(int256(position.entryPrice) - priceDiff);
        } else {
            return uint256(int256(position.entryPrice) + priceDiff);
        }
    }
}
```

### 2. SpotEngine - AMM + Limit Orders

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SpotEngine is ReentrancyGuard {
    struct LimitOrder {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 limitPrice; // Price in tokenOut per tokenIn
        bool postOnly;
        uint256 expiryTime;
        OrderStatus status;
    }
    
    enum OrderStatus {
        PENDING,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED,
        EXPIRED
    }
    
    mapping(uint256 => LimitOrder) public limitOrders;
    uint256 public orderIdCounter;
    
    IUniswapV3Router public dexRouter;
    IOrderNFT public orderNFT;
    
    event LimitOrderCreated(
        uint256 indexed orderId,
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 limitPrice
    );
    
    event LimitOrderExecuted(
        uint256 indexed orderId,
        uint256 amountOut,
        uint256 executionPrice
    );
    
    // Create limit order
    function createLimitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 limitPrice,
        bool postOnly,
        uint256 expiryTime
    ) external returns (uint256 orderId, uint256 orderNFTId) {
        require(amountIn > 0, "Invalid amount");
        require(expiryTime > block.timestamp, "Invalid expiry");
        
        // Transfer tokens to contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Create limit order
        orderId = ++orderIdCounter;
        limitOrders[orderId] = LimitOrder({
            user: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            limitPrice: limitPrice,
            postOnly: postOnly,
            expiryTime: expiryTime,
            status: OrderStatus.PENDING
        });
        
        // Mint Order NFT
        orderNFTId = orderNFT.mint(
            msg.sender,
            OrderNFT.OrderMetadata({
                orderId: orderId,
                market: tokenOut,
                isLong: true,
                size: amountIn,
                limitPrice: limitPrice,
                timestamp: block.timestamp,
                status: OrderStatus.PENDING
            })
        );
        
        emit LimitOrderCreated(
            orderId,
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            limitPrice
        );
    }
    
    // Execute limit order when price reached
    function executeLimitOrder(uint256 orderId) external nonReentrant {
        LimitOrder storage order = limitOrders[orderId];
        require(order.status == OrderStatus.PENDING, "Order not pending");
        require(block.timestamp <= order.expiryTime, "Order expired");
        
        // Get current price from DEX
        uint256 currentPrice = _getPrice(order.tokenIn, order.tokenOut, order.amountIn);
        
        // Check if price reached
        require(currentPrice >= order.limitPrice, "Price not reached");
        
        // Execute swap
        uint256 amountOut = _executeSwap(
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.limitPrice // Minimum amount out
        );
        
        // Transfer to user
        IERC20(order.tokenOut).transfer(order.user, amountOut);
        
        // Update order status
        order.status = OrderStatus.FILLED;
        
        // Update Order NFT
        orderNFT.updateOrderStatus(
            orderIdCounter, // Use stored NFT ID
            OrderStatus.FILLED,
            amountOut
        );
        
        emit LimitOrderExecuted(orderId, amountOut, currentPrice);
    }
    
    // Market swap with slippage protection
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Execute swap through DEX aggregator
        amountOut = _executeSwap(tokenIn, tokenOut, amountIn, minAmountOut);
        
        // Transfer to user
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
    
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256) {
        // Approve router
        IERC20(tokenIn).approve(address(dexRouter), amountIn);
        
        // Execute swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });
        
        return dexRouter.exactInputSingle(params);
    }
    
    function _getPrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        // Get quote from DEX
        // Simplified - implement actual quoter logic
        return 0;
    }
}
```

### 3. CrossMarginEngine - Unified Collateral

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CrossMarginEngine {
    struct Account {
        mapping(address => uint256) collateral; // asset => amount
        int256 unrealizedPnL;
        uint256 totalPositionValue;
        uint256 lastUpdateTime;
    }
    
    mapping(address => Account) public accounts;
    mapping(address => uint256) public assetWeights; // Collateral haircuts
    
    IOracleRegistry public oracleRegistry;
    
    uint256 public constant BASIS_POINTS = 10000;
    
    event CollateralDeposited(
        address indexed user,
        address indexed asset,
        uint256 amount
    );
    
    event CollateralWithdrawn(
        address indexed user,
        address indexed asset,
        uint256 amount
    );
    
    // Deposit collateral
    function depositCollateral(
        address user,
        address asset,
        uint256 amount
    ) external {
        require(amount > 0, "Invalid amount");
        require(assetWeights[asset] > 0, "Asset not supported");
        
        accounts[user].collateral[asset] += amount;
        
        // Transfer tokens
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        emit CollateralDeposited(user, asset, amount);
    }
    
    // Withdraw collateral
    function withdrawCollateral(
        address user,
        address asset,
        uint256 amount
    ) external {
        require(accounts[user].collateral[asset] >= amount, "Insufficient collateral");
        
        // Check if withdrawal maintains healthy margin
        accounts[user].collateral[asset] -= amount;
        require(_isAccountHealthy(user), "Would break margin requirements");
        
        // Transfer tokens
        IERC20(asset).transfer(msg.sender, amount);
        
        emit CollateralWithdrawn(user, asset, amount);
    }
    
    // Get total account value in USD
    function getAccountValue(address user) external view returns (uint256) {
        Account storage account = accounts[user];
        int256 totalValue = 0;
        
        // Sum all collateral (with haircuts)
        address[] memory supportedAssets = _getSupportedAssets();
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            uint256 balance = account.collateral[asset];
            
            if (balance > 0) {
                uint256 price = oracleRegistry.getPrice(asset);
                uint256 value = (balance * price) / 1e18;
                
                // Apply haircut
                uint256 weight = assetWeights[asset];
                value = (value * weight) / BASIS_POINTS;
                
                totalValue += int256(value);
            }
        }
        
        // Add unrealized P&L
        totalValue += account.unrealizedPnL;
        
        return totalValue > 0 ? uint256(totalValue) : 0;
    }
    
    // Calculate margin ratio
    function getMarginRatio(address user) external view returns (uint256) {
        uint256 accountValue = this.getAccountValue(user);
        uint256 positionValue = accounts[user].totalPositionValue;
        
        if (positionValue == 0) return type(uint256).max;
        
        return (accountValue * BASIS_POINTS) / positionValue;
    }
    
    // Credit profit from closed position
    function creditProfit(address user, uint256 amount) external {
        accounts[user].unrealizedPnL += int256(amount);
    }
    
    // Debit loss from closed position
    function debitLoss(address user, uint256 amount) external {
        accounts[user].unrealizedPnL -= int256(amount);
    }
    
    function _isAccountHealthy(address user) internal view returns (bool) {
        uint256 marginRatio = this.getMarginRatio(user);
        return marginRatio >= 1000; // 10% minimum
    }
    
    function _getSupportedAssets() internal view returns (address[] memory) {
        // Return list of supported collateral assets
        address[] memory assets = new address[](3);
        assets[0] = address(0); // ETH
        assets[1] = address(0); // USDC
        assets[2] = address(0); // WBTC
        return assets;
    }
}
```

## TypeScript SDK

```typescript
import { ethers } from 'ethers';

class BaobabTradingSDK {
    private perpEngine: ethers.Contract;
    private spotEngine: ethers.Contract;
    private crossMargin: ethers.Contract;
    
    // Open leveraged perpetual position
    async openPerpPosition(params: {
        market: string;
        isLong: boolean;
        size: string;
        collateral: string;
        leverage: number;
        maxSlippage?: number;
    }) {
        const maxSlippage = params.maxSlippage || 50; // 0.5%
        
        // Calculate position size from leverage
        const collateralWei = ethers.parseEther(params.collateral);
        const sizeWei = collateralWei * BigInt(params.leverage);
        
        const tx = await this.perpEngine.openPosition(
            params.market,
            params.isLong,
            sizeWei,
            collateralWei,
            maxSlippage
        );
        
        const receipt = await tx.wait();
        const event = receipt.logs.find((log: any) => 
            log.eventName === 'PositionOpened'
        );
        
        return {
            positionId: event.args.positionId,
            entryPrice: ethers.formatEther(event.args.entryPrice),
            txHash: receipt.hash
        };
    }
    
    // Close position with P&L calculation
    async closePerpPosition(
        market: string,
        positionId: number,
        sizeDelta?: string
    ) {
        const position = await this.getPosition(market, positionId);
        const size = sizeDelta 
            ? ethers.parseEther(sizeDelta)
            : ethers.parseEther(position.size);
        
        const tx = await this.perpEngine.closePosition(
            market,
            positionId,
            size
        );
        
        const receipt = await tx.wait();
        const event = receipt.logs.find((log: any) => 
            log.eventName === 'PositionClosed'
        );
        
        return {
            pnl: ethers.formatEther(event.args.pnl),
            exitPrice: ethers.formatEther(event.args.exitPrice),
            txHash: receipt.hash
        };
    }
    
    // Get position details with real-time P&L
    async getPosition(
