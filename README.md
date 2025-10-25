# 🏦 KipuBank V2 Smart Contract

**Version:** 2.0.0  
**Author:** [DiegoNG90](https://github.com/DiegoNG90)  
**License:** MIT

**KipuBank V2** is an educational smart contract that implements a minimalistic multi-asset banking system supporting **Ether (ETH)** and **USDC** deposits and withdrawals.  
All internal accounting is **denominated in USD (6 decimals)** using a **Chainlink ETH/USD price feed**, enabling:

- A **global deposit limit** (`BANKCAP`) expressed in USD.
- A **per-transaction withdrawal limit** (`MAXIMUM_WITHDRAWAL_IN_USD`) expressed in USD.
- A **multi-token balance mapping** `balances[user][token]`, where `address(0)` represents native ETH.

> ⚠️ **Disclaimer:** This contract is a hands-on educational project.  
> It is **not intended for production use** and should be deployed only in testing or learning environments.

---

## 📝 Project Overview (V2 Enhancements)

The original `KipuBank` (V1) was a simple ETH vault. **KipuBank V2** has been refactored into a **Multi-Asset, USD-Denominated Deposit Vault**.

All financial limits and internal balances are now tracked in **USD (6 decimals)**, ensuring consistent risk management regardless of the volatile asset deposited (ETH).

### Key Features and TP3 Requirements

| Feature                    | V2 Implementation                                                                                                                                            | Consigna Requirement                                 |
| :------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------- |
| **Multi-Token Support**    | Implemented `depositEther()` and `depositToken()` (for USDC) using `IERC20`.                                                                                 | **Soporte Multi-token**                              |
| **Financial Oracle**       | Integrated **Chainlink Aggregator V3** to fetch the real-time **ETH/USD** price.                                                                             | **Data Feeds**                                       |
| **Global Limit (BankCap)** | The global limit (`BANKCAP`) is denominated in **USD** and is enforced using Chainlink data to prevent total bank over-exposure.                             | **Controlar el límite global**                       |
| **Advanced Accounting**    | Utilizes a **nested mapping** (`balances[user][token]`) to track multi-token holdings. **`address(0)`** is used as the unique identifier key for native ETH. | **Mappings anidados** & **Contabilidad Multi-token** |
| **Access Control**         | Inherits from OpenZeppelin’s **`Ownable`** to restrict critical administrative functions, such as updating the Oracle (`setFeeds`), to the contract owner.   | **Control de Acceso**                                |
| **Safety**                 | Implements robust **Custom Errors**, `immutable` variables, and the **Checks-Effects-Interactions (CEI)** pattern.                                           | **Seguridad y Eficiencia**                           |
| **Advanced Security**      | Uses ReentrancyGuard to protect withdrawEther() from reentrancy attacks, even though the CEI pattern is correctly followed.                                  | **Seguridad y Eficiencia**                           |

---

## 🛠️ Deployment Instructions (Sepolia Testnet)

The contract must be deployed on the **Sepolia Testnet**. The constructor requires four mandatory parameters for initial configuration:

| Parameter             | Type                    | Description                                                | Unit / Example Value                                  |
| :-------------------- | :---------------------- | :--------------------------------------------------------- | :---------------------------------------------------- |
| `_bankCap`            | `uint256`               | The **absolute maximum total deposit limit** for the bank. | USD (6 decimals). **i.e., $1M USD:** `1000000000000`  |
| `_maxWithdrawalInUSD` | `uint256`               | The maximum value a user can withdraw per transaction.     | USD (6 decimals). **i.e., $10K USD:** `10000000000`   |
| `_oracle`             | `AggregatorV3Interface` | The ETH/USD Chainlink Data Feed address.                   | Sepolia: `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| `_usdcToken`          | `IERC20`                | The USDC ERC-20 token address supported by the bank.       | Sepolia: `0x1c7d4b196cb0c7b01d743fbc6116a902379c7a9c` |

### Address of Deployed Contract (Post-Verification)

| Network             | Contract Address                       | Verified Etherscan Link                     |
| :------------------ | :------------------------------------- | :------------------------------------------ |
| **Sepolia Testnet** | `[INSERT FINAL DEPLOYED ADDRESS HERE]` | `[INSERT Etherscan Verification Link HERE]` |

---

## 🤝 Interaction Guide

### 1. Deposits

| Function         | Asset         | Requirement                                                                                | Key Logic                                                                                       |
| :--------------- | :------------ | :----------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------- |
| `depositEther()` | ETH (Native)  | Must send ETH via the **`Value`** field.                                                   | Converts `msg.value` (Wei) to USD via Chainlink for limit checking.                             |
| `depositToken()` | USDC (ERC-20) | Must call **`IERC20.approve()`** first to grant the KipuBank contract spending permission. | Uses `transferFrom()` to pull USDC. No oracle needed (1 USDC = $1 USD for internal accounting). |

### 2. Withdrawals

| Function                                                | Asset             | Parameters                                                 | Key Logic                                                                                 |
| :------------------------------------------------------ | :---------------- | :--------------------------------------------------------- | :---------------------------------------------------------------------------------------- |
| `withdrawEther(uint256 _amount)`                        | ETH (Wei)         | `_amount` in **Wei**                                       | Checks `_amount` in USD against `MAXIMUM_WITHDRAWAL_IN_USD` before transfer.              |
| `withdrawToken(address _tokenAddress, uint256 _amount)` | USDC (6 decimals) | `_tokenAddress` (must be USDC) and `_amount` (6 decimals). | Checks `_amount` directly against `MAXIMUM_WITHDRAWAL_IN_USD` and uses `USDC.transfer()`. |

### 3. Administrative Functions (Owner Only)

| Function                  | Role        | Description                                                                  |
| :------------------------ | :---------- | :--------------------------------------------------------------------------- |
| `setFeeds(address _feed)` | `onlyOwner` | Updates the Chainlink Oracle address. Protected by the `onlyOwner` modifier. |

---

## 💡 Notes on Design Decisions

### Why Nested Mappings and `address(0)`?

I've chosen `mapping(address => mapping(address => uint256))` over a simple `struct` to adhere to the TP3 requirement for **Mappings Anidados** and to ensure **scalability**. The internal accounting can easily be extended to support DAI or WBTC in the future by simply updating the deposit logic, without changing the core storage structure. `address(0)` is used by convention to denote native ETH within this multi-token storage.

### Why USD-Denominated Limits?

Since the bank accepts a volatile asset (ETH) and a stable asset (USDC), all risk limits (`BANKCAP`, `MAXIMUM_WITHDRAWAL_IN_USD`) must be based on a stable unit (USD). This design ensures that a massive spike in the price of ETH does not accidentally cause the bank's total value to exceed the `BANKCAP` when comparing a Wei balance against a Wei limit. This is a core financial safety feature.

### Robust Security Architecture

To achieve the highest level of security and robustness, the contract incorporates the following external libraries:

- Reentrancy Protection: use OpenZeppelin's ReentrancyGuard with the nonReentrant modifier on the withdrawEther() function. Although the function follows the Checks-Effects-Interactions (CEI) pattern, this library provides an extra, standardized layer of defense against potential reentrancy attacks via a malicious recipient contract.

- ETH Handling: The contract implements a dedicated receive() external payable function. This ensures that any Ether sent directly to the contract address (without specifying a function) is correctly redirected to the primary depositEther() logic, guaranteeing that all incoming ETH is subject to the BANKCAP check and is properly accounted for.

### Gas Optimization via unchecked

The internal counter functions (incrementDepositsOperations() and incrementWithdrawalsOperations()) utilize Solidity's unchecked block. Since these counters are uint256 and are only incremented (making mathematical overflow virtually impossible in real-world use), bypassing the default safety checks provides a small, but safe, gas optimization.
