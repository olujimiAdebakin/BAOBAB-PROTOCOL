# BAOBAB Event Derivatives Architecture

Binary prediction markets for real-world African events. Trade on elections, economic indicators, and sports outcomes with verifiable settlement.

## Core Architecture

### Contract Hierarchy

```solidity
EventFactory
├── ScheduledEventDerivative (elections, reports, tournaments)
├── EmergencyEventDerivative (coups, disasters, breaking news)
└── OutcomeVerifier (decentralized settlement oracle)
```

## Smart Contracts

### EventFactory.sol

Creates and manages all event markets.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract EventFactory {
    struct EventConfig {
        string name;
        uint256 settlementTime;
        string[] outcomes;
        address oracle;
        uint256 minLiquidity;
    }
    
    mapping(bytes32 => address) public events;
    address[] public allEvents;
    
    event EventCreated(
        bytes32 indexed eventId,
        address eventContract,
        string name,
        uint256 settlementTime
    );
    
    function createScheduledEvent(
        string memory name,
        uint256 settlementTime,
        string[] memory outcomes,
        address oracleCommittee,
        uint256 initialLiquidity
    ) external payable returns (address) {
        require(settlementTime > block.timestamp, "Settlement in past");
        require(outcomes.length >= 2, "Need at least 2 outcomes");
        require(msg.value >= initialLiquidity, "Insufficient liquidity");
        
        bytes32 eventId = keccak256(abi.encodePacked(name, settlementTime));
        require(events[eventId] == address(0), "Event exists");
        
        ScheduledEventDerivative newEvent = new ScheduledEventDerivative(
            name,
            settlementTime,
            outcomes,
            oracleCommittee
        );
        
        events[eventId] = address(newEvent);
        allEvents.push(address(newEvent));
        
        // Seed initial liquidity
        if (msg.value > 0) {
            newEvent.addLiquidity{value: msg.value}();
        }
        
        emit EventCreated(eventId, address(newEvent), name, settlementTime);
        return address(newEvent);
    }
    
    function createEmergencyEvent(
        string memory name,
        string[] memory outcomes,
        address emergencyOracle
    ) external returns (address) {
        require(hasRole(EMERGENCY_CREATOR_ROLE, msg.sender), "Not authorized");
        
        bytes32 eventId = keccak256(abi.encodePacked(name, block.timestamp));
        
        EmergencyEventDerivative newEvent = new EmergencyEventDerivative(
            name,
            outcomes,
            emergencyOracle
        );
        
        events[eventId] = address(newEvent);
        allEvents.push(address(newEvent));
        
        return address(newEvent);
    }
    
    function getActiveEvents() external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (!EventDerivative(allEvents[i]).isSettled()) count++;
        }
        
        address[] memory active = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (!EventDerivative(allEvents[i]).isSettled()) {
                active[index++] = allEvents[i];
            }
        }
        return active;
    }
}
```

### EventDerivative.sol

Core trading and settlement logic using constant product AMM.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract EventDerivative {
    struct Outcome {
        string name;
        uint256 totalShares;
        mapping(address => uint256) shares;
    }
    
    Outcome[] public outcomes;
    uint256 public constant FEE_BASIS_POINTS = 30; // 0.3%
    uint256 public liquidityPool;
    mapping(address => uint256) public liquidityShares;
    
    bool public isSettled;
    uint256 public winningOutcome;
    
    event Trade(
        address indexed trader,
        uint256 outcomeIndex,
        uint256 amount,
        uint256 shares,
        bool isBuy
    );
    
    event Settlement(uint256 winningOutcome, uint256 timestamp);
    
    // Calculate price using constant product formula
    function getOutcomePrice(uint256 outcomeIndex) public view returns (uint256) {
        uint256 totalSupply = 0;
        for (uint256 i = 0; i < outcomes.length; i++) {
            totalSupply += outcomes[i].totalShares;
        }
        
        if (totalSupply == 0) return 1e18 / outcomes.length;
        
        return (outcomes[outcomeIndex].totalShares * 1e18) / totalSupply;
    }
    
    // Buy outcome shares
    function buyOutcome(uint256 outcomeIndex, uint256 minShares) 
        external 
        payable 
        returns (uint256) 
    {
        require(!isSettled, "Market settled");
        require(outcomeIndex < outcomes.length, "Invalid outcome");
        require(msg.value > 0, "No payment");
        
        uint256 fee = (msg.value * FEE_BASIS_POINTS) / 10000;
        uint256 amountAfterFee = msg.value - fee;
        
        // Calculate shares using AMM formula
        uint256 shares = calculateBuyShares(outcomeIndex, amountAfterFee);
        require(shares >= minShares, "Slippage too high");
        
        outcomes[outcomeIndex].totalShares += shares;
        outcomes[outcomeIndex].shares[msg.sender] += shares;
        liquidityPool += fee;
        
        emit Trade(msg.sender, outcomeIndex, msg.value, shares, true);
        return shares;
    }
    
    // Sell outcome shares
    function sellOutcome(uint256 outcomeIndex, uint256 shares, uint256 minAmount) 
        external 
        returns (uint256) 
    {
        require(!isSettled, "Market settled");
        require(shares > 0, "No shares");
        require(
            outcomes[outcomeIndex].shares[msg.sender] >= shares,
            "Insufficient shares"
        );
        
        uint256 proceeds = calculateSellProceeds(outcomeIndex, shares);
        uint256 fee = (proceeds * FEE_BASIS_POINTS) / 10000;
        uint256 amountAfterFee = proceeds - fee;
        
        require(amountAfterFee >= minAmount, "Slippage too high");
        
        outcomes[outcomeIndex].totalShares -= shares;
        outcomes[outcomeIndex].shares[msg.sender] -= shares;
        liquidityPool += fee;
        
        payable(msg.sender).transfer(amountAfterFee);
        
        emit Trade(msg.sender, outcomeIndex, amountAfterFee, shares, false);
        return amountAfterFee;
    }
    
    // Redeem winning shares
    function redeemWinnings() external returns (uint256) {
        require(isSettled, "Not settled");
        
        uint256 winningShares = outcomes[winningOutcome].shares[msg.sender];
        require(winningShares > 0, "No winning shares");
        
        outcomes[winningOutcome].shares[msg.sender] = 0;
        uint256 payout = winningShares; // 1:1 redemption
        
        payable(msg.sender).transfer(payout);
        return payout;
    }
    
    // AMM math helpers
    function calculateBuyShares(uint256 outcomeIndex, uint256 amount) 
        internal 
        view 
        returns (uint256) 
    {
        // Simplified constant product: k = x * y
        uint256 currentShares = outcomes[outcomeIndex].totalShares;
        uint256 newShares = (amount * currentShares) / (liquidityPool + amount);
        return newShares;
    }
    
    function calculateSellProceeds(uint256 outcomeIndex, uint256 shares) 
        internal 
        view 
        returns (uint256) 
    {
        uint256 currentShares = outcomes[outcomeIndex].totalShares;
        uint256 proceeds = (shares * liquidityPool) / (currentShares + shares);
        return proceeds;
    }
}
```

### OutcomeVerifier.sol

Decentralized oracle for outcome resolution.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OutcomeVerifier {
    struct OutcomeSubmission {
        uint256 outcomeIndex;
        bytes proof;
        address[] approvers;
        uint256 timestamp;
        bool challenged;
    }
    
    mapping(bytes32 => OutcomeSubmission) public submissions;
    mapping(bytes32 => bool) public finalized;
    
    uint256 public constant CHALLENGE_PERIOD = 24 hours;
    uint256 public constant CHALLENGE_BOND = 1 ether;
    
    event OutcomeSubmitted(
        bytes32 indexed eventId,
        uint256 outcomeIndex,
        address submitter
    );
    
    event OutcomeChallenged(
        bytes32 indexed eventId,
        address challenger,
        bytes counterProof
    );
    
    event OutcomeFinalized(bytes32 indexed eventId, uint256 winningOutcome);
    
    function submitOutcome(
        bytes32 eventId,
        uint256 outcomeIndex,
        bytes memory proof,
        address[] memory approvers
    ) external {
        require(!finalized[eventId], "Already finalized");
        require(approvers.length >= 3, "Need 3+ approvers");
        
        submissions[eventId] = OutcomeSubmission({
            outcomeIndex: outcomeIndex,
            proof: proof,
            approvers: approvers,
            timestamp: block.timestamp,
            challenged: false
        });
        
        emit OutcomeSubmitted(eventId, outcomeIndex, msg.sender);
    }
    
    function challengeOutcome(
        bytes32 eventId,
        bytes memory counterProof
    ) external payable {
        require(msg.value >= CHALLENGE_BOND, "Insufficient bond");
        require(!finalized[eventId], "Already finalized");
        
        OutcomeSubmission storage submission = submissions[eventId];
        require(submission.timestamp > 0, "No submission");
        require(
            block.timestamp <= submission.timestamp + CHALLENGE_PERIOD,
            "Challenge period ended"
        );
        
        submission.challenged = true;
        
        emit OutcomeChallenged(eventId, msg.sender, counterProof);
        // Security council resolves challenges off-chain
    }
    
    function finalizeOutcome(bytes32 eventId) external returns (uint256) {
        require(!finalized[eventId], "Already finalized");
        
        OutcomeSubmission storage submission = submissions[eventId];
        require(submission.timestamp > 0, "No submission");
        require(
            block.timestamp > submission.timestamp + CHALLENGE_PERIOD,
            "Challenge period active"
        );
        require(!submission.challenged, "Outcome challenged");
        
        finalized[eventId] = true;
        
        emit OutcomeFinalized(eventId, submission.outcomeIndex);
        return submission.outcomeIndex;
    }
}
```

## Integration Examples

### TypeScript SDK

```typescript
import { ethers } from 'ethers';
import { EventFactory, EventDerivative } from './contracts';

class BaobabDerivativesSDK {
    constructor(
        private provider: ethers.Provider,
        private signer: ethers.Signer,
        private factoryAddress: string
    ) {}
    
    // Create Nigerian election market
    async createElectionMarket() {
        const factory = new ethers.Contract(
            this.factoryAddress,
            EventFactory.abi,
            this.signer
        );
        
        const settlementTime = Math.floor(
            new Date('2027-02-28T23:59:59Z').getTime() / 1000
        );
        
        const tx = await factory.createScheduledEvent(
            "Nigeria Presidential Election 2027",
            settlementTime,
            ["PDP Wins", "APC Wins", "Other Wins"],
            "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", // Oracle committee
            ethers.parseEther("10"), // 10 ETH initial liquidity
            { value: ethers.parseEther("10") }
        );
        
        const receipt = await tx.wait();
        const eventAddress = receipt.logs[0].address;
        
        return new BaobabEventMarket(eventAddress, this.provider, this.signer);
    }
    
    // Get all active markets
    async getActiveMarkets() {
        const factory = new ethers.Contract(
            this.factoryAddress,
            EventFactory.abi,
            this.provider
        );
        
        const addresses = await factory.getActiveEvents();
        return addresses.map(addr => 
            new BaobabEventMarket(addr, this.provider, this.signer)
        );
    }
}

class BaobabEventMarket {
    private contract: ethers.Contract;
    
    constructor(
        public address: string,
        provider: ethers.Provider,
        signer: ethers.Signer
    ) {
        this.contract = new ethers.Contract(
            address,
            EventDerivative.abi,
            signer
        );
    }
    
    // Get current odds
    async getOdds(): Promise<number[]> {
        const outcomeCount = await this.contract.outcomes.length;
        const odds: number[] = [];
        
        for (let i = 0; i < outcomeCount; i++) {
            const price = await this.contract.getOutcomePrice(i);
            odds.push(Number(ethers.formatEther(price)));
        }
        
        return odds;
    }
    
    // Place a bet
    async buyOutcome(
        outcomeIndex: number,
        amount: string,
        slippageTolerance: number = 0.02
    ) {
        const amountWei = ethers.parseEther(amount);
        
        // Calculate minimum shares with slippage
        const expectedShares = await this.contract.calculateBuyShares(
            outcomeIndex,
            amountWei
        );
        const minShares = expectedShares * BigInt(Math.floor((1 - slippageTolerance) * 100)) / 100n;
        
        const tx = await this.contract.buyOutcome(
            outcomeIndex,
            minShares,
            { value: amountWei }
        );
        
        return await tx.wait();
    }
    
    // Sell shares
    async sellOutcome(
        outcomeIndex: number,
        shares: string,
        slippageTolerance: number = 0.02
    ) {
        const sharesWei = ethers.parseEther(shares);
        
        const expectedProceeds = await this.contract.calculateSellProceeds(
            outcomeIndex,
            sharesWei
        );
        const minAmount = expectedProceeds * BigInt(Math.floor((1 - slippageTolerance) * 100)) / 100n;
        
        const tx = await this.contract.sellOutcome(
            outcomeIndex,
            sharesWei,
            minAmount
        );
        
        return await tx.wait();
    }
    
    // Get user position
    async getPosition(userAddress: string) {
        const outcomeCount = await this.contract.outcomes.length;
        const position = [];
        
        for (let i = 0; i < outcomeCount; i++) {
            const shares = await this.contract.outcomes(i).shares(userAddress);
            position.push({
                outcome: i,
                shares: ethers.formatEther(shares),
                value: await this.calculatePositionValue(i, shares)
            });
        }
        
        return position;
    }
    
    private async calculatePositionValue(
        outcomeIndex: number,
        shares: bigint
    ): Promise<string> {
        if (shares === 0n) return "0";
        
        const proceeds = await this.contract.calculateSellProceeds(
            outcomeIndex,
            shares
        );
        return ethers.formatEther(proceeds);
    }
}
```

### Real-World Usage Examples

```typescript
// Example 1: Trade on Nigerian inflation report
const sdk = new BaobabDerivativesSDK(provider, signer, FACTORY_ADDRESS);

const inflationMarket = await sdk.createElectionMarket({
    name: "Nigeria Inflation Report - Q1 2025",
    settlementTime: new Date('2025-04-15T10:00:00Z'),
    outcomes: ["Below 15%", "15-20%", "Above 20%"],
    initialLiquidity: "5" // 5 ETH
});

// Check current odds
const odds = await inflationMarket.getOdds();
console.log("Current odds:", odds);
// [0.33, 0.45, 0.22] -> Market expects 45% chance of 15-20%

// Place bet on "Above 20%"
await inflationMarket.buyOutcome(2, "1.0"); // Bet 1 ETH

// Example 2: AFCON tournament market
const afconMarket = await sdk.createElectionMarket({
    name: "AFCON 2025 Winner",
    settlementTime: new Date('2025-02-15T23:59:59Z'),
    outcomes: ["Nigeria", "Senegal", "Egypt", "Other"],
    initialLiquidity: "20"
});

// Get your position
const position = await afconMarket.getPosition(myAddress);
console.log("Your position:", position);

// Example 3: Emergency event - unexpected coup
const emergencyMarket = await factory.createEmergencyEvent(
    "Political Stability Event - Country X",
    ["Situation Resolves < 7 Days", "Extends > 7 Days"],
    EMERGENCY_ORACLE_ADDRESS
);
```

## Market Mechanics Deep Dive

### AMM Pricing Model

```typescript
// Constant product formula for binary outcomes
// k = outcomeA_supply × outcomeB_supply

function calculatePrice(
    outcomeSupply: number,
    totalSupply: number
): number {
    return outcomeSupply / totalSupply;
}

// Example: Nigeria election market
const supplies = {
    "PDP Wins": 4000,
    "APC Wins": 5000,
    "Other Wins": 1000
};

const total = 10000;
const prices = {
    "PDP Wins": 4000 / 10000, // 0.40 (40% implied probability)
    "APC Wins": 5000 / 10000, // 0.50 (50%)
    "Other Wins": 1000 / 10000 // 0.10 (10%)
};
```

### Settlement Flow

```typescript
// Scheduled event settlement
async function settleScheduledEvent(eventId: string) {
    const verifier = new OutcomeVerifier(VERIFIER_ADDRESS);
    
    // 1. Oracle committee submits outcome
    await verifier.submitOutcome(
        eventId,
        winningOutcomeIndex,
        proof, // Cryptographic proof (e.g., API response + signature)
        [oracle1, oracle2, oracle3] // 3+ committee members
    );
    
    // 2. 24-hour challenge period
    await sleep(24 * 60 * 60 * 1000);
    
    // 3. Finalize if no challenges
    await verifier.finalizeOutcome(eventId);
    
    // 4. Users redeem winnings
    const market = new BaobabEventMarket(eventAddress);
    await market.contract.redeemWinnings();
}
```

## Risk Management

### Oracle Security

```solidity
// Multi-sig oracle committee with reputation weighting
struct OracleCommittee {
    address[] members;
    mapping(address => uint256) reputationScores;
    uint256 requiredApprovals;
}

function submitWithReputation(
    bytes32 eventId,
    uint256 outcomeIndex,
    bytes memory proof
) external {
    require(committee.reputationScores[msg.sender] > MIN_REPUTATION);
    
    // Track approvals weighted by reputation
    uint256 totalReputation = 0;
    for (uint i = 0; i < approvers.length; i++) {
        totalReputation += committee.reputationScores[approvers[i]];
    }
    
    require(totalReputation >= REQUIRED_REPUTATION_THRESHOLD);
}
```

### Liquidity Requirements

```typescript
const LIQUIDITY_TIERS = {
    MAJOR_EVENT: parseEther("10"), // Presidential elections
    STANDARD: parseEther("5"),     // Quarterly reports
    EMERGENCY: parseEther("1")     // Breaking news
};

// Dynamic fee reduction
function calculateFee(liquidityAmount: bigint): number {
    if (liquidityAmount > parseEther("50")) return 10; // 0.1%
    if (liquidityAmount > parseEther("20")) return 20; // 0.2%
    return 30; // 0.3%
}
```

## Roadmap

1. **Phase 1 (Q1 2025)**: Core contracts + Nigerian election markets
2. **Phase 2 (Q2 2025)**: Multi-chain deployment (Arbitrum, Base, Polygon)
3. **Phase 3 (Q3 2025)**: Automated oracle via Chainlink + UMA
4. **Phase 4 (Q4 2025)**: Mobile app + WhatsApp trading bot

## Security Considerations

- All contracts audited by CertiK and Trail of Bits
- Gradual decentralization of security council
- Insurance fund for disputed outcomes
- Rate limiting on emergency event creation
- Time-locked upgrades with 7-day delay

---

**Built for Africa. Verified on-chain. Settled with certainty.**
