
Event Derivatives Architecture
Overview
BAOBAB Event Derivatives enable prediction markets for real-world events with a focus on African politics, economics, and sports. These binary options settle based on verifiable real-world outcomes.

Event Types
Scheduled Events
Fixed-date events with known settlement time

Elections (Nigeria 2027, Ghana 2028)

Economic announcements (Nigeria inflation, SA unemployment)

Corporate earnings (Dangote, MTN Nigeria)

Sports tournaments (AFCON, World Cup)

Emergency Events
Unexpected events requiring rapid market creation

Geopolitical developments (coups, policy changes)

Natural disasters (floods, droughts affecting economies)

Major corporate announcements (mergers, scandals)

Significant economic policy changes

Core Components
EventFactory
Purpose: Event market creation and template management

solidity
function createScheduledEvent(
    string memory eventName,
    uint256 settlementTime,
    string[] memory outcomes,
    address oracleCommittee
) → address eventContract

function createEmergencyEvent(
    string memory eventName, 
    string[] memory outcomes,
    address emergencyOracle
) → address eventContract
EventDerivative (Base Contract)
Purpose: Core event trading and settlement logic

solidity
// Key functions
function buyOutcome(uint outcomeIndex, uint amount) → uint shares
function sellOutcome(uint outcomeIndex, uint amount) → uint proceeds
function redeemWinnings() → uint payout
function triggerSettlement(uint winningOutcome)
OutcomeVerifier
Purpose: Decentralized outcome resolution

solidity
function submitOutcome(uint eventId, uint outcomeIndex, bytes memory proof)
function challengeOutcome(uint eventId, bytes memory counterProof)
function finalizeOutcome(uint eventId) → uint winningOutcome
Market Mechanics
Binary Options Structure
text
Event: "Nigeria Presidential Election 2027"
Outcomes: ["Candidate A Wins", "Candidate B Wins"]

- Each outcome token priced between 0-1.0
- All outcomes sum to 1.0 before settlement
- Winning outcome redeems for 1.0, losers for 0.0
AMM-based Trading
solidity
// Constant product AMM for each outcome
k = outcomeASupply × outcomeBSupply

// Price determined by relative supplies
outcomeAPrice = outcomeBSupply / (outcomeASupply + outcomeBSupply)
Liquidity Provision
Liquidity providers earn fees on all trades

Impermanent loss protection for balanced outcomes

Minimum liquidity requirements for market creation

Settlement Process
Scheduled Event Settlement
text
1. Settlement time reached
2. Oracle committee submits outcome with cryptographic proof
3. 24-hour challenge period for disputes
4. If no challenges, outcome finalized automatically
5. If challenged, security council resolves
6. Winning shares redeemable at 1:1
Emergency Event Settlement
text
1. Emergency oracle (multi-sig) triggers settlement
2. 48-hour redemption period begins immediately
3. Security council can override within 24 hours
4. Final settlement after override period expires
African Market Focus
Political Events
National and regional elections

Policy announcements and reforms

International treaty ratifications

Economic Events
Central bank interest rate decisions

Inflation and unemployment reports

Commodity price movements (oil, cocoa, etc.)

Sports & Culture
AFCON and other continental tournaments

Entertainment awards and events

Significant cultural celebrations

Risk Management
Oracle Security
Multi-sig committees for important events

Reputation-weighted voting for outcome resolution

Cryptographic proof requirements for submissions

Liquidity Requirements
Minimum $10,000 liquidity for scheduled events

Emergency events can launch with lower requirements

Gradual fee reduction as liquidity increases

Dispute Resolution
Security council for contested settlements

Bond-based challenge system to prevent spam

Gradual decentralization over time

Integration Examples
Nigerian Election Market
javascript
// Create election market
const electionEvent = await protocol.createScheduledEvent({
    name: "Nigeria Presidential Election 2027",
    settlementTime: "2027-02-28T23:59:59Z", 
    outcomes: ["PDP Wins", "APC Wins", "Other Wins"],
    oracleCommittee: "0x123...abc"
});

// Trade based on predictions
await electionEvent.buyOutcome(0, "1000000000000000000"); // Buy 1.0 PDP shares
Economic Announcement
javascript
// Inflation report market
// Inflation report market

const inflationEvent = await protocol.createScheduledEvent({
    name: "Nigeria Inflation Report - Q1 2025",
    settlementTime: "2025-04-15T10:00:00Z",
    outcomes: ["Below 15%", "15-20%", "Above 20%"],
    oracleCommittee: "0x456...def"
});
