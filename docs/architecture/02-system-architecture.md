# BAOBAB Protocol System Architecture

**Revolutionary DeFi primitive: Orders become productive NFT assets**

Transform limit orders into composable ERC-721 tokens that can be staked, collateralized, or traded—all while waiting for execution.

## Core Innovation: Order NFT Composability

```
Order Lifecycle:
Place Order → Mint NFT → Stake/Collateralize/Trade → Execute → Burn NFT
     ↓            ↓              ↓                       ↓         ↓
  $1000       Asset ID     Earn 5% APY               Filled    NFT
  Limit       #42069       Borrow $500              Tokens   Destroyed
  Order                    List on OpenSea          Received
```

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER LAYER                              │
│  Web App • Mobile • API • Keeper Bots • NFT Marketplaces       │
└────────────┬────────────────────────────────────────────────────┘
             │
┌────────────┴────────────────────────────────────────────────────┐
│                      PROTOCOL LAYER                             │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │CoreRouter    │  │Trading Engine│  │Basket Engine │        │
│  │(Entry Point) │→ │(Perps + Spot)│  │(Strategies)  │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │Event Engine  │  │Vault System  │  │Order NFT Sys │        │
│  │(Predictions) │  │(LP Deposits) │  │(Composability)│        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└────────────┬────────────────────────────────────────────────────┘
             │
┌────────────┴────────────────────────────────────────────────────┐
│                     EXTERNAL LAYER                              │
│  Chainlink • Pyth • DEX Aggregators • Regional Oracles         │
└─────────────────────────────────────────────────────────────────┘
```

## Core Contracts

### 1. CoreRouter - Unified Protocol Entry

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract CoreRouter is ReentrancyGuard, Pausable {
    address public immutable tradingRouter;
    address public immutable basketRouter;
    address public immutable eventRouter;
    address public immutable vaultRouter;
    
    IDataStore public dataStore;
    IOrderNFT public orderNFT;
    
    event RouteExecuted(
        address indexed user,
        bytes4 indexed selector,
        address target
    );
    
    constructor(
        address _tradingRouter,
        address _basketRouter,
        address _eventRouter,
        address _vaultRouter,
        address _dataStore,
        address _orderNFT
    ) {
        tradingRouter = _tradingRouter;
        basketRouter = _basketRouter;
        eventRouter = _eventRouter;
        vaultRouter = _vaultRouter;
        dataStore = IDataStore(_dataStore);
        orderNFT = IOrderNFT(_orderNFT);
    }
    
    // Unified order placement with NFT minting
    function placeOrder(
        address market,
        bool isLong,
        uint256 size,
        uint256 price,
        uint256 executionFee
    ) external payable nonReentrant whenNotPaused returns (uint256 orderNFTId) {
        require(msg.value >= executionFee, "Insufficient execution fee");
        
        // Route to trading engine
        bytes memory data = abi.encodeWithSelector(
            ITradingRouter.createOrder.selector,
            msg.sender,
            market,
            isLong,
            size,
            price
        );
        
        (bool success, bytes memory result) = tradingRouter.delegatecall(data);
        require(success, "Order creation failed");
        
        uint256 orderId = abi.decode(result, (uint256));
        
        // Mint Order NFT
        orderNFTId = orderNFT.mint(
            msg.sender,
            OrderNFT.OrderMetadata({
                orderId: orderId,
                market: market,
                isLong: isLong,
                size: size,
                limitPrice: price,
                timestamp: block.timestamp,
                status: OrderStatus.PENDING
            })
        );
        
        // Store execution fee
        dataStore.setExecutionFee(orderNFTId, msg.value);
        
        emit RouteExecuted(msg.sender, this.placeOrder.selector, tradingRouter);
        return orderNFTId;
    }
    
    // Cancel order and burn NFT
    function cancelOrder(uint256 orderNFTId) external nonReentrant {
        require(orderNFT.ownerOf(orderNFTId) == msg.sender, "Not NFT owner");
        
        OrderNFT.OrderMetadata memory metadata = orderNFT.getMetadata(orderNFTId);
        require(metadata.status == OrderStatus.PENDING, "Order not pending");
        
        // Cancel in trading engine
        bytes memory data = abi.encodeWithSelector(
            ITradingRouter.cancelOrder.selector,
            metadata.orderId
        );
        
        (bool success, ) = tradingRouter.delegatecall(data);
        require(success, "Cancel failed");
        
        // Burn NFT
        orderNFT.burn(orderNFTId);
        
        // Refund execution fee
        uint256 fee = dataStore.getExecutionFee(orderNFTId);
        payable(msg.sender).transfer(fee);
    }
    
    // Collateralize Order NFT for instant liquidity
    function collateralizeOrder(
        uint256 orderNFTId,
        uint256 loanAmount
    ) external nonReentrant returns (uint256 loanId) {
        require(orderNFT.ownerOf(orderNFTId) == msg.sender, "Not NFT owner");
        
        OrderNFT.OrderMetadata memory metadata = orderNFT.getMetadata(orderNFTId);
        uint256 orderValue = _calculateOrderValue(metadata);
        
        // 50% LTV maximum
        require(loanAmount <= orderValue / 2, "LTV too high");
        
        // Lock NFT in escrow
        orderNFT.transferFrom(msg.sender, address(this), orderNFTId);
        
        // Issue loan
        loanId = dataStore.createLoan(
            msg.sender,
            orderNFTId,
            loanAmount,
            block.timestamp + 30 days // 30-day term
        );
        
        // Transfer funds
        payable(msg.sender).transfer(loanAmount);
    }
    
    function _calculateOrderValue(
        OrderNFT.OrderMetadata memory metadata
    ) internal view returns (uint256) {
        uint256 currentPrice = IOracleRegistry(dataStore.oracleRegistry())
            .getPrice(metadata.market);
            
        // For limit buy: value = size * min(limitPrice, currentPrice)
        // For limit sell: value = size * max(limitPrice, currentPrice)
        if (metadata.isLong) {
            return metadata.size * 
                (metadata.limitPrice < currentPrice ? metadata.limitPrice : currentPrice);
        } else {
            return metadata.size * 
                (metadata.limitPrice > currentPrice ? metadata.limitPrice : currentPrice);
        }
    }
}
```

### 2. OrderNFT - Composable Order System

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

enum OrderStatus {
    PENDING,
    PARTIALLY_FILLED,
    FILLED,
    CANCELLED
}

contract OrderNFT is ERC721, ERC721URIStorage {
    struct OrderMetadata {
        uint256 orderId;
        address market;
        bool isLong;
        uint256 size;
        uint256 limitPrice;
        uint256 timestamp;
        OrderStatus status;
        uint256 filledAmount;
    }
    
    uint256 private _tokenIdCounter;
    mapping(uint256 => OrderMetadata) public orderMetadata;
    mapping(uint256 => uint256) public orderToNFT; // orderId => nftId
    
    address public immutable coreRouter;
    
    event OrderNFTMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 orderId
    );
    
    event OrderNFTUpdated(
        uint256 indexed tokenId,
        OrderStatus status,
        uint256 filledAmount
    );
    
    constructor(address _coreRouter) ERC721("BAOBAB Order", "BORDER") {
        coreRouter = _coreRouter;
    }
    
    modifier onlyRouter() {
        require(msg.sender == coreRouter, "Only router");
        _;
    }
    
    function mint(
        address to,
        OrderMetadata memory metadata
    ) external onlyRouter returns (uint256) {
        uint256 tokenId = ++_tokenIdCounter;
        
        _safeMint(to, tokenId);
        orderMetadata[tokenId] = metadata;
        orderToNFT[metadata.orderId] = tokenId;
        
        // Generate on-chain SVG metadata
        _setTokenURI(tokenId, _generateTokenURI(tokenId));
        
        emit OrderNFTMinted(tokenId, to, metadata.orderId);
        return tokenId;
    }
    
    function updateOrderStatus(
        uint256 tokenId,
        OrderStatus status,
        uint256 filledAmount
    ) external onlyRouter {
        require(_exists(tokenId), "Token doesn't exist");
        
        orderMetadata[tokenId].status = status;
        orderMetadata[tokenId].filledAmount = filledAmount;
        
        // Update metadata URI
        _setTokenURI(tokenId, _generateTokenURI(tokenId));
        
        emit OrderNFTUpdated(tokenId, status, filledAmount);
    }
    
    function burn(uint256 tokenId) external onlyRouter {
        require(_exists(tokenId), "Token doesn't exist");
        _burn(tokenId);
        delete orderToNFT[orderMetadata[tokenId].orderId];
        delete orderMetadata[tokenId];
    }
    
    function getMetadata(uint256 tokenId) 
        external 
        view 
        returns (OrderMetadata memory) 
    {
        require(_exists(tokenId), "Token doesn't exist");
        return orderMetadata[tokenId];
    }
    
    // Generate on-chain SVG for Order NFT
    function _generateTokenURI(uint256 tokenId) 
        internal 
        view 
        returns (string memory) 
    {
        OrderMetadata memory data = orderMetadata[tokenId];
        
        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">',
            '<rect width="400" height="400" fill="',
            data.isLong ? '#10B981' : '#EF4444',
            '"/>',
            '<text x="20" y="40" fill="white" font-size="24">BAOBAB Order</text>',
            '<text x="20" y="80" fill="white" font-size="16">',
            data.isLong ? 'LONG' : 'SHORT',
            '</text>',
            '<text x="20" y="120" fill="white" font-size="14">Size: ',
            _toString(data.size),
            '</text>',
            '<text x="20" y="150" fill="white" font-size="14">Price: ',
            _toString(data.limitPrice),
            '</text>',
            '<text x="20" y="180" fill="white" font-size="14">Status: ',
            _statusToString(data.status),
            '</text>',
            '</svg>'
        ));
        
        string memory json = string(abi.encodePacked(
            '{"name":"BAOBAB Order #',
            _toString(tokenId),
            '","description":"Composable limit order NFT","image":"data:image/svg+xml;base64,',
            _base64Encode(bytes(svg)),
            '","attributes":[',
            '{"trait_type":"Direction","value":"', data.isLong ? 'Long' : 'Short', '"},',
            '{"trait_type":"Size","value":', _toString(data.size), '},',
            '{"trait_type":"Status","value":"', _statusToString(data.status), '"}',
            ']}'
        ));
        
        return string(abi.encodePacked(
            'data:application/json;base64,',
            _base64Encode(bytes(json))
        ));
    }
    
    function _statusToString(OrderStatus status) 
        internal 
        pure 
        returns (string memory) 
    {
        if (status == OrderStatus.PENDING) return "Pending";
        if (status == OrderStatus.PARTIALLY_FILLED) return "Partial";
        if (status == OrderStatus.FILLED) return "Filled";
        return "Cancelled";
    }
    
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _base64Encode(bytes memory data) 
        internal 
        pure 
        returns (string memory) 
    {
        // Base64 encoding implementation
        // (Simplified for brevity - use library in production)
        return ""; // Implement full base64 encoding
    }
    
    function _burn(uint256 tokenId) 
        internal 
        override(ERC721, ERC721URIStorage) 
    {
        super._burn(tokenId);
    }
    
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override(ERC721, ERC721URIStorage) 
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
}
```

### 3. TradingEngine - Perps + Spot with Cross-Margin

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TradingEngine {
    struct Position {
        address market;
        bool isLong;
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        uint256 lastFundingUpdate;
        int256 fundingAccrued;
    }
    
    struct Market {
        address asset;
        uint256 maxLeverage;
        uint256 fundingRate;
        uint256 openInterestLong;
        uint256 openInterestShort;
        bool isActive;
    }
    
    IDataStore public dataStore;
    IOracleRegistry public oracleRegistry;
    IOrderNFT public orderNFT;
    
    uint256 public constant LIQUIDATION_THRESHOLD = 9000; // 90%
    uint256 public constant BASIS_POINTS = 10000;
    
    mapping(address => mapping(address => Position[])) public positions;
    mapping(address => Market) public markets;
    mapping(address => uint256) public crossMarginCollateral;
    
    event PositionOpened(
        address indexed user,
        address indexed market,
        bool isLong,
        uint256 size,
        uint256 entryPrice
    );
    
    event PositionClosed(
        address indexed user,
        address indexed market,
        int256 pnl
    );
    
    // Open position with cross-margin
    function openPosition(
        address user,
        address market,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 maxSlippage
    ) external returns (uint256 positionId) {
        require(markets[market].isActive, "Market not active");
        
        // Calculate required collateral
        uint256 leverage = (size * 1e18) / collateral;
        require(leverage <= markets[market].maxLeverage, "Leverage too high");
        
        // Get current price
        uint256 price = oracleRegistry.getPrice(market);
        
        // Check slippage
        uint256 slippage = _calculateSlippage(market, isLong, size);
        require(slippage <= maxSlippage, "Slippage too high");
        
        // Update cross-margin collateral
        crossMarginCollateral[user] += collateral;
        
        // Create position
        Position memory newPosition = Position({
            market: market,
            isLong: isLong,
            size: size,
            collateral: collateral,
            entryPrice: price,
            lastFundingUpdate: block.timestamp,
            fundingAccrued: 0
        });
        
        positions[user][market].push(newPosition);
        positionId = positions[user][market].length - 1;
        
        // Update open interest
        if (isLong) {
            markets[market].openInterestLong += size;
        } else {
            markets[market].openInterestShort += size;
        }
        
        // Store in DataStore
        dataStore.setPosition(user, market, positionId, newPosition);
        
        emit PositionOpened(user, market, isLong, size, price);
    }
    
    // Execute limit order and update NFT
    function executeOrder(uint256 orderNFTId) external {
        OrderNFT.OrderMetadata memory metadata = orderNFT.getMetadata(orderNFTId);
        require(metadata.status == OrderStatus.PENDING, "Order not pending");
        
        // Check if price reached
        uint256 currentPrice = oracleRegistry.getPrice(metadata.market);
        bool canExecute = metadata.isLong 
            ? currentPrice <= metadata.limitPrice 
            : currentPrice >= metadata.limitPrice;
            
        require(canExecute, "Price not reached");
        
        // Open position
        address owner = orderNFT.ownerOf(orderNFTId);
        uint256 collateral = dataStore.getOrderCollateral(metadata.orderId);
        
        openPosition(
            owner,
            metadata.market,
            metadata.isLong,
            metadata.size,
            collateral,
            0 // No slippage check for limit orders
        );
        
        // Update NFT status
        orderNFT.updateOrderStatus(
            orderNFTId,
            OrderStatus.FILLED,
            metadata.size
        );
        
        // Burn NFT after execution
        orderNFT.burn(orderNFTId);
    }
    
    // Close position
    function closePosition(
        address user,
        address market,
        uint256 positionId
    ) external returns (int256 pnl) {
        Position storage position = positions[user][market][positionId];
        require(position.size > 0, "Position doesn't exist");
        
        // Calculate PnL
        uint256 currentPrice = oracleRegistry.getPrice(market);
        pnl = _calculatePnL(position, currentPrice);
        
        // Update funding
        int256 funding = _calculateFunding(position);
        pnl -= funding;
        
        // Update collateral
        if (pnl > 0) {
            crossMarginCollateral[user] += uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            require(crossMarginCollateral[user] >= loss, "Insufficient collateral");
            crossMarginCollateral[user] -= loss;
        }
        
        // Update open interest
        if (position.isLong) {
            markets[market].openInterestLong -= position.size;
        } else {
            markets[market].openInterestShort -= position.size;
        }
        
        // Delete position
        delete positions[user][market][positionId];
        
        emit PositionClosed(user, market, pnl);
    }
    
    function _calculatePnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256) {
        if (position.isLong) {
            return int256(currentPrice) - int256(position.entryPrice);
        } else {
            return int256(position.entryPrice) - int256(currentPrice);
        }
    }
    
    function _calculateFunding(
        Position memory position
    ) internal view returns (int256) {
        uint256 timeElapsed = block.timestamp - position.lastFundingUpdate;
        uint256 fundingRate = markets[position.market].fundingRate;
        
        int256 funding = int256(
            (position.size * fundingRate * timeElapsed) / (365 days * BASIS_POINTS)
        );
        
        return position.isLong ? funding : -funding;
    }
    
    function _calculateSlippage(
        address market,
        bool isLong,
        uint256 size
    ) internal view returns (uint256) {
        uint256 totalOI = markets[market].openInterestLong + 
                          markets[market].openInterestShort;
        
        if (totalOI == 0) return 0;
        
        // Simplified slippage model
        return (size * 100) / totalOI; // 1% slippage per 1% of OI
    }
    
    // Check if position needs liquidation
    function liquidatePosition(
        address user,
        address market,
        uint256 positionId
    ) external {
        Position storage position = positions[user][market][positionId];
        require(position.size > 0, "Position doesn't exist");
        
        uint256 currentPrice = oracleRegistry.getPrice(market);
        int256 pnl = _calculatePnL(position, currentPrice);
        int256 funding = _calculateFunding(position);
        
        int256 totalPnL = pnl - funding;
        uint256 currentValue = position.collateral;
        
        if (totalPnL < 0) {
            uint256 loss = uint256(-totalPnL);
            if (loss >= currentValue) {
                currentValue = 0;
            } else {
                currentValue -= loss;
            }
        }
        
        // Check if below liquidation threshold
        uint256 maintenanceMargin = (position.size * LIQUIDATION_THRESHOLD) / BASIS_POINTS;
        require(currentValue < maintenanceMargin, "Position healthy");
        
        // Liquidate
        closePosition(user, market, positionId);
        
        // Reward liquidator
        uint256 reward = (position.collateral * 500) / BASIS_POINTS; // 5% reward
        payable(msg.sender).transfer(reward);
    }
}
```

### 4. BasketFactory - Tokenized Strategy Funds

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OrderBasket is ERC20 {
    struct BasketOrder {
        uint256 orderNFTId;
        uint256 weight; // Basis points
    }
    
    address public manager;
    BasketOrder[] public orders;
    uint256 public managementFee; // Annual fee in basis points
    uint256 public performanceFee; // Performance fee in basis points
    uint256 public lastFeeCollection;
    
    IOrderNFT public orderNFT;
    
    constructor(
        string memory name,
        string memory symbol,
        address _manager,
        uint256 _managementFee,
        uint256 _performanceFee,
        address _orderNFT
    ) ERC20(name, symbol) {
        manager = _manager;
        managementFee = _managementFee;
        performanceFee = _performanceFee;
        lastFeeCollection = block.timestamp;
        orderNFT = IOrderNFT(_orderNFT);
    }
    
    // Invest in basket
    function deposit(uint256 amount) external returns (uint256 shares) {
        require(amount > 0, "Amount must be > 0");
        
        uint256 totalValue = getTotalValue();
        uint256 supply = totalSupply();
        
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / totalValue;
        }
        
        _mint(msg.sender, shares);
        
        // Transfer payment
        // (Assuming USDC or similar)
        require(
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }
    
    // Redeem basket shares
    function redeem(uint256 shares) external returns (uint256 amount) {
        require(shares > 0, "Shares must be > 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");
        
        uint256 totalValue = getTotalValue();
        uint256 supply = totalSupply();
        
        amount = (shares * totalValue) / supply;
        
        _burn(msg.sender, shares);
        
        // Transfer pro-rata value
        require(
            IERC20(baseAsset).transfer(msg.sender, amount),
            "Transfer failed"
        );
    }
    
    // Add order to basket (manager only)
    function addOrder(
        uint256 orderNFTId,
        uint256 weight
    ) external {
        require(msg.sender == manager, "Only manager");
        require(orderNFT.ownerOf(orderNFTId) == manager, "Manager must own NFT");
        
        // Transfer NFT to basket
        orderNFT.transferFrom(manager, address(this), orderNFTId);
        
        orders.push(BasketOrder({
            orderNFTId: orderNFTId,
            weight: weight
        }));
    }
    
    // Get total basket value
    function getTotalValue() public view returns (uint256) {
        uint256 total = 0;
        
        for (uint256 i = 0; i < orders.length; i++) {
            OrderNFT.OrderMetadata memory metadata = 
                orderNFT.getMetadata(orders[i].orderNFTId);
            
            // Calculate order value based on status
            if (metadata.status == OrderStatus.PENDING) {
                total += _estimateOrderValue(metadata);
            } else if (metadata.status == OrderStatus.FILLED) {
                total += _getFilledValue(metadata);
            }
        }
        
        return total;
    }
    
    function _estimateOrderValue(
        OrderNFT.OrderMetadata memory metadata
    ) internal view returns (uint256) {
        // Simplified valuation
        return metadata.size * metadata.limitPrice;
    }
    
    function _getFilledValue(
        OrderNFT.OrderMetadata memory metadata
    ) internal view returns (uint256) {
        // Get current position value
        // (Would query TradingEngine)
        return 0; // Implement actual logic
    }
    
    // Collect management fees
    function collectFees() external {
        uint256 timeElapsed = block.timestamp - lastFeeCollection;
        uint256 annualFee = (getTotalValue() * managementFee) / 10000;
        uint256 feeAmount = (annualFee * timeElapsed) / 365 days;
        
        // Mint fee shares to manager
        uint256 supply = totalSupply();
        uint256 feeShares = (feeAmount * supply) / (getTotalValue() - feeAmount);
        
        _mint(manager, feeShares);
        lastFeeCollection = block.timestamp;
    }
}

contract OrderBasketFactory {
    event BasketCreated(
        address indexed basket,
        address indexed manager,
        string name
    );
    
    address public orderNFT;
    
    constructor(address _orderNFT) {
        orderNFT = _orderNFT;
    }
    
    function createBasket(
        string memory name,
        string memory symbol,
        uint256 managementFee,
        uint256 performanceFee
    ) external returns (address) {
        OrderBasket basket = new OrderBasket(
            name,
            symbol,
            msg.sender,
            managementFee,
            performanceFee,
            orderNFT
        );
        
        emit BasketCreated(address(basket), msg.sender, name);
        return address(basket);
    }
}
```

## TypeScript SDK

```typescript
import { ethers } from 'ethers';
import { CoreRouter, OrderNFT, TradingEngine, OrderBasketFactory } from './contracts';

class BaobabProtocolSDK {
    private coreRouter: ethers.Contract;
    private orderNFT: ethers.Contract;
    private tradingEngine: ethers.Contract;
    private basketFactory: ethers.Contract;
    
    constructor(
        provider: ethers.Provider,
        signer: ethers.Signer,
        addresses: {
            coreRouter: string;
            orderNFT: string;
            tradingEngine: string;
            basketFactory: string;
        }
    ) {
        this.coreRouter = new ethers.Contract(
            addresses.coreRouter,
            CoreRouter.abi,
            signer
        );
        this.orderNFT = new ethers.Contract(
            addresses.orderNFT,
            OrderNFT.abi,
            signer
        );
        this.tradingEngine = new ethers.Contract(
            addresses.tradingEngine,
            TradingEngine.abi,
            signer
        );
        this.basketFactory = new ethers.Contract(
            addresses.basketFactory,
            OrderBasketFactory.abi,
            signer
        );
    }
    
    // Place order and receive NFT
    async placeOrder(params: {
        market: string;
        isLong: boolean;
        size: string;
        limitPrice: string;
        executionFee?: string;
    }) {
        const executionFee = params.executionFee
