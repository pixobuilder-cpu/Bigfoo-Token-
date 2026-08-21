 BigfootAMM Architecture — Bigfoot-lab (bigfoot-lab.eth.limo)
Welcome to the official technical documentation for BigfootAMM, the native Automated Market Maker (AMM) custom-built for the Bigfoot-lab ecosystem.

This contract implements a decentralized, dual-pool liquidity engine supporting BFT/WPOL and BFT/USDC pairs. It uses a modified constant product formula ($x \times y = k$) engineered to autonomously funnel system trading fees back into the BigfootVault protocol to maximize capital efficiency.

⚡ Core Architecture & Economic Loop
Unlike standard AMMs that merely compound collected fees directly back into the trading pools, BigfootAMM acts as a value-capture primitive for long-term ecosystem stakers.

Fee Breakdown (30 Basis Points / 0.3% Total Swap Fee)
Liquidity Providers Share (0.2%): Automatically added back to the active pool reserves to incentivize external liquidity depth.
Protocol Ecosystem Share (0.1%): Extracted instantly at every swap execution and routed directly to the BigfootVault via the depositYield() interface.
Financial Flywheel Mechanism
Users execute market swaps (e.g., selling BFT for USDC).
The AMM calculates output parameters and splits the 30 bps swap fee.
The 10 bps Protocol Fee is pushed directly into the BigfootVault.
The Vault appreciation rate (convertToAssets) increases in real-time, instantly rewarding bfSHARES holders without token inflation.
🛡️ Production-Grade Security Features
The contract is built using OpenZeppelin v4.9.3 primitives and includes defensive engineering to guarantee protocol safety on the Polygon network:

Multi-Pair Isolation: Distinct storage layout and tracking for BFT/WPOL and BFT/USDC liquidity distributions, accounting for decimal variations (BFT/WPOL use 18 decimals; USDC uses 6 decimals).
Anti-Front Running & Flash Loan Protection: Implements an exact block operation lock (antiFrontRun modifier), preventing MEV sandwich bots or malicious actors from executing multiple mint/burn/swap operations within a single blockchain block.
Slippage Bounds Enforcement: Strict _validateSlippage verification logic asserting that executed outputs never fall below user-specified amountOutMin tolerances.
Asynchronous Vault Resiliency: Fees routed to the vault utilize a low-level try/catch safety net. If the vault sub-routine fails or rejects a specific collateral token asset, the swap transaction does not revert, preserving end-user execution experience while locking assets in the AMM for manual recovery.
Emergency Circuit Breaker: Integrated Pausable state allowing the contract owner to halt trading operations under volatile market conditions, paired with an emergencyWithdraw pipeline.
🕹️ Interface Functions Reference
Liquidity Management
addLiquidityBFTWPOL / addLiquidityBFTUSDC: Deposits asset ratios to mint custom pool-specific tracking indicators.
removeLiquidityBFTWPOL / removeLiquidityBFTUSDC: Burns existing lp balances to retrieve base pair reserves plus accumulated fees.
Swapping Executions
swapWPOLForBFT(uint256 amountWPOLIn, uint256 amountBFTOutMin)
swapBFTForWPOL(uint256 amountBFTIn, uint256 amountWPOLOutMin)
swapUSDCForBFT(uint256 amountUSDCIn, uint256 amountBFTOutMin)
swapBFTForUSDC(uint256 amountBFTIn, uint256 amountUSDCOutMin)
🛠️ Testing Environment Configuration on Remix IDE
To test your AMM on Remix IDE using the virtual environment:

Deploy Mock Tokens: Deploy your own test contracts for BFT, USDC (6 decimals), and WPOL.
Deploy Vault: Initialize your BigfootVault pointing to the BFT asset contract address.
Deploy AMM: Instantiate BigfootAMM by passing the 4 deployed target addresses directly to the constructor input fields.
Approve Allocations: Execute standard ERC-20 approvals from test wallets toward the AMM contract to enable pool provisioning.
