File,Imports,Imported By
libraries/math/FixedPointMath.sol,—,"PercentageMath.sol, FundingRateCalculator.sol"
libraries/math/PercentageMath.sol,FixedPointMath.sol,"RiskParameterManager.sol, LiquidationEngine.sol"
libraries/utils/SafeTransfer.sol,—,"LiquidityVault.sol, TreasuryVault.sol"
libraries/structs/TradingStructs.sol,—,"OrderManager.sol, PositionManager.sol"
tokens/erc20/BAOBABToken.sol,"ERC20Votes, Ownable","TreasuryVault.sol, LiquidityVault.sol, BAOBABGovernor.sol"
tokens/erc20/VaultShareToken.sol,ERC4626,LiquidityVault.sol
tokens/erc721/OrderNFT.sol,ERC721,"OrderManager.sol, BasketFactory.sol, VaultRouter.sol"
core/trading/OrderManager.sol,"OrderNFT.sol, TradingStructs.sol","TradingRouter.sol, OrderBook.sol"
core/trading/PositionManager.sol,TradingStructs.sol,"PerpEngine.sol, LiquidationEngine.sol"
core/trading/PerpEngine.sol,PositionManager.sol,TradingRouter.sol
core/trading/OrderBook.sol,OrderManager.sol,OrderBookReader.sol
core/trading/LiquidationEngine.sol,"PositionManager.sol, PercentageMath.sol",VaultManager.sol
core/trading/FundingRateCalculator.sol,FixedPointMath.sol,PerpEngine.sol
markets/MarketFactory.sol,OrderManager.sol,CoreRouter.sol
markets/RiskParameterManager.sol,PercentageMath.sol,VaultManager.sol
oracles/adapters/ChainlinkAdapter.sol,—,OracleRegistry.sol
oracles/adapters/PythAdapter.sol,—,OracleRegistry.sol
oracles/adapters/TWAPAdapter.sol,—,OracleRegistry.sol
oracles/OracleRegistry.sol,All adapters,PriceFeedAdapter.sol
vaults/LiquidityVault.sol,"VaultShareToken.sol, BAOBABToken.sol, SafeTransfer.sol","VaultRouter.sol, TreasuryVault.sol, PortfolioReader.sol"
vaults/TreasuryVault.sol,"BAOBABToken.sol, LiquidityVault.sol","TimelockController.sol, IncentiveManager.sol"
vaults/InsuranceVault.sol,—,LiquidationEngine.sol
vaults/VaultManager.sol,"LiquidityVault.sol, LiquidationEngine.sol","VaultRouter.sol, TradingRouter.sol"
governance/BAOBABGovernor.sol,"BAOBABToken.sol, Governor, GovernorVotes, TimelockControl",—
governance/TimelockController.sol,OpenZeppelin Timelock,"BAOBABGovernor.sol, TreasuryVault.sol"
governance/ProposalFactory.sol,BAOBABGovernor.sol,Scripts
routers/TradingRouter.sol,"OrderManager.sol, VaultManager.sol",User
routers/VaultRouter.sol,"LiquidityVault.sol, VaultManager.sol",User
routers/BasketRouter.sol,BasketFactory.sol,User
baskets/BasketFactory.sol,OrderNFT.sol,BasketRouter.sol
baskets/BasketEngine.sol,BasketFactory.sol,BasketRouter.sol
readers/PortfolioReader.sol,"PositionManager.sol, LiquidityVault.sol",Frontend
readers/OrderBookReader.sol,OrderBook.sol,Frontend
fees/IncentiveManager.sol,"LiquidityVault.sol, BAOBABToken.sol",TreasuryVault.sol
access/AccessManager.sol,TimelockController.sol,All admin functions
keeper-bots/marketMaker.ts,"TreasuryVault.sol, RiskParameterManager.sol",Off-chain