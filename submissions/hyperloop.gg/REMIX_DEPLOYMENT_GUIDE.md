# HyperLoop Vault - Remix Deployment Guide

## 📦 Smart Contracts Overview

Your zip file contains the following contracts:

### Main Contracts (Deploy These)
1. **HypurrAutoLoopVault.sol** - ⭐ RECOMMENDED - Latest version with auto-loop functionality
2. **HyperLoopVaultV2.sol** - Alternative version with manual loop control
3. **DCAVault.sol** - Dollar-Cost Averaging vault (optional, for DCA feature)

### Supporting Files
- `interfaces/` - IHypurrFiPool.sol, ISwapRouter.sol
- `mocks/` - MockERC20.sol, MockHypurrFiPool.sol (for testing only)

---

## 🚀 Step-by-Step Deployment Instructions

### Step 1: Setup MetaMask for HyperEVM Mainnet

1. Open MetaMask
2. Click network dropdown → "Add Network" → "Add a network manually"
3. Enter the following details:
   ```
   Network Name: HyperEVM Mainnet
   RPC URL: https://rpc.hyperliquid.xyz/evm
   Chain ID: 998
   Currency Symbol: HYPE
   Block Explorer: https://explorer.hyperliquid.xyz
   ```
4. Click "Save"
5. Switch to HyperEVM Mainnet
6. Ensure you have HYPE tokens for gas fees

### Step 2: Upload Contracts to Remix

1. Go to https://remix.ethereum.org/
2. In the File Explorer (left panel), create a new folder: `contracts`
3. Extract your zip file locally
4. Upload all files from the extracted folder to Remix:
   - Right-click on `contracts` folder → "Upload files"
   - Select all `.sol` files from your extracted folder
   - OR drag and drop the entire `contracts` folder

### Step 3: Compile the Contract

1. Click on "Solidity Compiler" icon (left sidebar)
2. Select compiler version: **0.8.20** (or 0.8.19+)
3. Click on `contracts/HypurrAutoLoopVault.sol` in the file explorer
4. Click "Compile HypurrAutoLoopVault.sol"
5. Verify no errors appear (warnings are OK)

### Step 4: Deploy HypurrAutoLoopVault

1. Click "Deploy & Run Transactions" icon (left sidebar)
2. Set **ENVIRONMENT** to "Injected Provider - MetaMask"
3. MetaMask will popup → Connect your wallet
4. Verify the network shows "Custom (998) network" (HyperEVM)
5. In the **CONTRACT** dropdown, select `HypurrAutoLoopVault`

6. **Expand the Deploy section** and enter constructor parameters:

   ```
   _POOL: 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b
   _WHYPE: 0x5555555555555555555555555555555555555555
   _USDXL: 0xca79db4b49f608ef54a5cb813fbed3a6387bc645
   ```

7. Click **"Deploy"**
8. MetaMask will popup → **Confirm the transaction**
9. Wait for deployment confirmation (15-30 seconds)

### Step 5: Verify Deployment

1. After deployment, the contract will appear under "Deployed Contracts" section
2. Click the copy icon next to the contract address
3. **SAVE THIS ADDRESS** - you'll need it for the frontend!
4. Visit https://explorer.hyperliquid.xyz and paste the address to verify

### Step 6: Update Frontend with Contract Address

1. Go back to your Manus project
2. Open `client/src/lib/contracts.ts`
3. Find the line:
   ```typescript
   export const VAULT_ADDRESS = '0x0000000000000000000000000000000000000000';
   ```
4. Replace with your deployed contract address:
   ```typescript
   export const VAULT_ADDRESS = '0xYOUR_DEPLOYED_CONTRACT_ADDRESS';
   ```
5. Save the file
6. Create a new checkpoint in Manus

---

## 🧪 Testing Your Deployed Contract

### Quick Test in Remix

1. Under "Deployed Contracts", expand your contract
2. Test read functions (orange buttons):
   - Click `pool()` → Should return: `0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b`
   - Click `whype()` → Should return: `0x5555555555555555555555555555555555555555`
   - Click `usdxl()` → Should return: `0xca79db4b49f608ef54a5cb813fbed3a6387bc645`

3. Test owner function:
   - Click `owner()` → Should return your wallet address

### Test Deposit (Optional - Use Frontend Instead)

**⚠️ IMPORTANT: Test with small amounts first!**

1. First approve WHYPE spending:
   - Deploy WHYPE token contract at `0x5555555555555555555555555555555555555555`
   - Call `approve(spender, amount)`:
     - `spender`: Your vault contract address
     - `amount`: `1000000000000000000` (1 WHYPE with 18 decimals)

2. Then deposit:
   - In your vault contract, call `deposit(amount, receiver, leverage)`:
     - `amount`: `1000000000000000000` (1 WHYPE)
     - `receiver`: Your wallet address
     - `leverage`: `2` (2x leverage)

---

## 📋 Constructor Parameters Explained

| Parameter | Address | Description |
|-----------|---------|-------------|
| `_POOL` | `0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b` | HypurrFi Pool contract - handles supply/borrow |
| `_WHYPE` | `0x5555555555555555555555555555555555555555` | Wrapped HYPE token - collateral asset |
| `_USDXL` | `0xca79db4b49f608ef54a5cb813fbed3a6387bc645` | USDXL synthetic dollar - borrow asset |

---

## ⚠️ Common Issues & Solutions

### Issue: "Gas estimation failed"
**Solution:** Increase gas limit manually:
- Click "Advanced" in MetaMask
- Set Gas Limit to: `5000000`

### Issue: "Insufficient funds for gas"
**Solution:** You need HYPE tokens for gas:
- Bridge HYPE from HyperCore to HyperEVM
- Send HYPE to address: `0x2222222222222222222222222222222222222222`

### Issue: "Contract creation code storage out of gas"
**Solution:** Enable optimizer in Remix:
- Go to "Solidity Compiler"
- Check "Enable optimization"
- Set runs to: `200`
- Recompile and deploy

### Issue: "Invalid address" in constructor
**Solution:** Make sure addresses:
- Start with `0x`
- Are exactly 42 characters long
- Have no spaces or extra characters

---

## 🎯 After Deployment Checklist

- [ ] Contract deployed successfully
- [ ] Contract address copied and saved
- [ ] Verified contract on block explorer
- [ ] Updated `VAULT_ADDRESS` in frontend code
- [ ] Created new checkpoint in Manus
- [ ] Published updated site
- [ ] Tested deposit with small amount
- [ ] Verified position shows in dashboard

---

## 📝 For Hackathon Submission

Include in your submission README:

```markdown
## Deployed Contracts

- **HypurrAutoLoopVault**: `0xYOUR_DEPLOYED_ADDRESS`
- **Network**: HyperEVM Mainnet (Chain ID: 998)
- **Block Explorer**: https://explorer.hyperliquid.xyz/address/0xYOUR_DEPLOYED_ADDRESS

## Contract Verification

The contract interacts with:
- HypurrFi Pool: `0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b`
- WHYPE Token: `0x5555555555555555555555555555555555555555`
- USDXL Token: `0xca79db4b49f608ef54a5cb813fbed3a6387bc645`
```

---

## 🆘 Need Help?

If you encounter any issues:
1. Check Remix console for error messages
2. Verify you're on HyperEVM Mainnet (Chain ID: 998)
3. Ensure you have enough HYPE for gas
4. Try deploying with optimizer enabled
5. Check that all constructor parameters are correct

**Good luck with your deployment! 🚀**
