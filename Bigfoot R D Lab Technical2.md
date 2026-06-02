# **Bigfoot R&D Lab: Technical Ecosystem Report**

This document serves as the comprehensive technical overview for the **Bigfoot Token (BFT)** ecosystem, designed for publication on **GitHub** to ensure transparency for the public and analytical tools like **Blockaid**.

## **1. Executive Summary: The Web3 R&D Laboratory**
The **Bigfoot Token (BFT)** is the core engine of a dedicated **smart contract research and development laboratory**. Every component within this ecosystem is designed as a **public, scientific experiment** dedicated to optimizing decentralized finance (DeFi), AI automation, and on-chain infrastructure. 

The lab operates on a **non-speculative model**, where the token supply is primarily held by secure vaults, liquidity pools, and internal development wallets to maintain a stable environment for innovation.

## **2. Core Infrastructure & Verified Addresses**
The following addresses represent the "Source of Truth" for the laboratory's operations on the **Polygon Network**:

### **Token & Governance Hub**
*   **Bigfoot Token (BFT):** `0x140098cCcdad0D8e63f8EF213cB3939e4d82d557`.
*   **Original Safe Proxy (Vault):** `0x5f0abd8d46b94f1734fcb9ecde6f1006d0ffc549`. This is a Gnosis Safe multisig vault that serves as the ultimate owner of the architectural contracts.
*   **Bigfoot Registry:** The central hub for application discovery and role management (`registerApp`, `updateBigfootTokens`).

### **Automation & Utility Apps**
*   **Cerebro Core (AI Engine):** An enterprise-grade AI automation engine featuring role-based access control and execution limits.
*   **Bigfoot Marketplace:** A multi-currency swap engine supporting BFT, WBFT, POL, and WETH.
*   **Cerebro Billing:** Manages payments for AI services, currently priced at **500 BFT per analysis**.
*   **Bigfoot Liquid Staking:** A yield optimization protocol utilizing `SafeERC20` and `ReentrancyGuard` for asset security.

### **External Integrations**
*   **Uniswap V3 QuoterV2 (Polygon):** `0x61FCe191b3384e5F761c4096c868228b59e6416c`.
*   **Legacy Staking Contract:** `0xa303462f5ef07b4a1b11ae254737e75497384823`. (Active for redistribution of tokens to holders).
*   **Liquid staking testing contract:** '0x495c1Eec213123D73A6436E2387A05Ce7301Ba73 (not active)

## **3. Technical Pivot: Sovereign Governance**
To overcome the rigidity of third-party platforms, the laboratory has transitioned to a **Sovereign Governor** model [Conversation History].
*   **The Voting Asset:** **BigfootDAO_VotingNFT** (ERC721Votes/EIP712 v4.9.0).https://polygonscan.com/address/0x7304c84e0a4029a8e80c5ea051182925e3e6fa2a
*   **On-Chain Identity:** Metadata and images are generated entirely on-chain (Image CID: `bafybeig7zc6xgscet7tjpw5kyukll5idgquhs4nidogg3zzf2uzi4key5e`) to ensure immutability.
*   **Fluid Execution:** The Governor interacts directly with the **IVotes** interface to track power at specific block numbers, protecting the lab from flash-loan manipulation.

## **4. Hardcoded Security Architecture**
The ecosystem is built with "hardcoded" resilience to prevent unauthorized access and maintain public trust:
*   **Multisig-First Governance:** Control is secured by the **Gnosis Safe Proxy** paired with a **Timelock**, ensuring no single entity has absolute power.
*   **Arbitrary Call Mitigation:** The AI agent (**Cerebro**) can only interact with contracts explicitly added to a **Target Whitelist** (`_whitelistedTargetContracts`) by the Governor.
*   **Role-Based Security:** Sensitive functions require specific identifiers like **`CEREBRO_GOVERNOR`** or **`CEREBRO_AI_EXECUTOR`**.
*   **Anti-Exploit Measures:** Every financial and execution-heavy contract implements **`ReentrancyGuard`** and **`SafeERC20`** to prevent nested call exploits and ensure transfer integrity.

## **5. Public Transparency & Immutability**
*   **Lab Manifesto:** The vision and technical specifications are archived immutably on IPFS under CID: `bafkreia2mvfkgxfr2fl4kkxsqafj2bcqgcqo4vgq3ah5zmce3hotvsfbv4`.
*   **Open Web3:** All smart contracts are **fully public and verified on-chain**, serving as open-source infrastructure for everyone.

***

*Note: For the complete source code and technical implementation details, please refer to the `/contracts` directory in this repository.*
