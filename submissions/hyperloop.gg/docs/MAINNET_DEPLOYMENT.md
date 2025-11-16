# HypurrLoop Vault - Mainnet Deployment Guide

**Important**: HypurrFi has confirmed that you should deploy to **HyperEVM Mainnet** (not testnet) for the hackathon. They will reimburse your gas fees for deployment and testing.

---

## Prerequisites

Before deploying, ensure you have:

1. **MetaMask or compatible wallet** with HyperEVM mainnet configured
2. **HYPE tokens** for gas fees (HypurrFi will reimburse)
3. **HyperEVM Mainnet RPC configured**:
   - Network Name: `Hyperliquid`
   - RPC URL: `https://api.hyperliquid-testnet.xyz/evm` (update with mainnet RPC when available)
   - Chain ID: `998` (verify mainnet chain ID)
   - Currency Symbol: `HYPE`
   - Block Explorer: `https://explorer.hyperliquid.xyz`

4. **HypurrFi Mainnet Contract Addresses** (get from https://docs.hypurr.fi/developers/addresses):
   - Pool (LendingPool): `0x...` (update with mainnet address)
   - PoolAddressesProvider: `0x...`
   - ProtocolDataProvider: `0x...`
   - WHYPE Token: `0x...`
   - USDXL Token: `0x...`
   - DEX Router (for swaps): `0x...`

---

## Step 1: Deploy HypurrAutoLoopVault Contract

### Option A: Deploy via Remix IDE (Recommended for Hackathon)

1. **Open Remix IDE**: Navigate to https://remix.ethereum.org

2. **Create Contract File**:
   - Create new file: `HypurrAutoLoopVault.sol`
   - Copy the complete contract code from `/home/ubuntu/hyperloop-vault/contracts/HypurrAutoLoopVault.sol`
   - Paste into Remix

3. **Install Dependencies**:
   - Create `@openzeppelin/contracts` folder structure in Remix
   - Import required OpenZeppelin contracts (ERC20, ERC4626, Ownable, ReentrancyGuard)
   - Or use Remix's GitHub import: `import "@openzeppelin/contracts@4.9.0/..."`

4. **Compile Contract**:
   - Select Solidity compiler version: `0.8.20`
   - Enable optimization: `200` runs
   - Click "Compile HypurrAutoLoopVault.sol"
   - Verify no errors

5. **Configure MetaMask**:
   - Switch to HyperEVM Mainnet
   - Ensure you have HYPE for gas

6. **Deploy Contract**:
   - Go to "Deploy & Run Transactions" tab
   - Environment: `Injected Provider - MetaMask`
   - Select contract: `HypurrAutoLoopVault`
   - Constructor parameters:
     ```
     _asset (WHYPE address): 0x... (mainnet WHYPE)
     _hypurrPool (Pool address): 0x... (mainnet Pool)
     _dexRouter (DEX Router): 0x... (mainnet DEX)
     _name: "HypurrLoop Vault WHYPE"
     _symbol: "hlvWHYPE"
     ```
   - Click "Deploy"
   - Confirm transaction in MetaMask
   - **Save the deployed contract address!**

7. **Verify Contract** (Optional but recommended):
   - Go to HyperEVM block explorer
   - Find your deployed contract
   - Click "Verify & Publish"
   - Paste flattened source code
   - Enter constructor arguments (ABI-encoded)
   - Submit for verification

### Option B: Deploy via Hardhat (For Advanced Users)

```bash
# Install dependencies
cd /home/ubuntu/hyperloop-vault
pnpm install

# Create .env file
cp .env.example .env

# Add your private key and RPC URL
echo "PRIVATE_KEY=your_private_key_here" >> .env
echo "HYPERVM_RPC_URL=https://api.hyperliquid-mainnet.xyz/evm" >> .env

# Update hardhat.config.ts with mainnet config
# Deploy
npx hardhat run scripts/deploy.js --network hyperevm_mainnet
```

---

## Step 2: Deploy DCAVault Contract (Optional - Stretch Feature)

Follow the same process as Step 1, but deploy `DCAVault.sol` instead. Constructor parameters:

```
_baseVault (HypurrAutoLoopVault address): 0x... (from Step 1)
_hypurrPool: 0x... (mainnet Pool)
_dexRouter: 0x... (mainnet DEX)
```

---

## Step 3: Update Frontend with Deployed Addresses

1. **Update Contract Addresses**:

Edit `client/src/lib/contracts.ts`:

```typescript
export const ASSET_ADDRESSES = {
  WHYPE: '0x...', // Mainnet WHYPE address
  USDXL: '0x...', // Mainnet USDXL address
  VAULT: '0x...', // Your deployed HypurrAutoLoopVault address
  POOL: '0x...', // Mainnet HypurrFi Pool address
  DATA_PROVIDER: '0x...', // Mainnet ProtocolDataProvider
  DEX_ROUTER: '0x...', // Mainnet DEX Router
};
```

2. **Update Chain ID** (if needed):

Edit `client/src/lib/web3Config.ts`:

```typescript
export const HYPERVM_CHAIN_ID = 998; // Verify mainnet chain ID
```

3. **Test Locally**:

```bash
cd /home/ubuntu/hyperloop-vault
pnpm dev
```

Open http://localhost:3000 and verify:
- Connect wallet works
- Contract addresses are correct
- APY data loads (if Pool is live)

---

## Step 4: Test on Mainnet

### Critical Tests:

1. **Connect Wallet**:
   - Click "Connect Wallet"
   - Approve connection
   - Verify wallet address displays

2. **Check Balances**:
   - Verify your WHYPE balance shows correctly
   - Check vault stats load

3. **Test Deposit Flow** (with small amount first!):
   - Click "Open Position"
   - Enter small amount (e.g., 0.1 WHYPE)
   - Select 2x leverage (Conservative)
   - Review projected APY and health factor
   - Click "Open Position"
   - Approve WHYPE spending (if first time)
   - Confirm deposit transaction
   - Wait for confirmation
   - Verify position appears in dashboard
   - Check health factor updates

4. **Test Withdraw Flow**:
   - Click "Withdraw"
   - Enter amount to withdraw
   - Confirm transaction
   - Verify WHYPE returned to wallet

5. **Test DCA Configuration** (if deployed):
   - Click "Configure DCA"
   - Set schedule and amount
   - Confirm transaction

---

## Step 5: Deploy Keeper Bot (Optional)

The keeper bot monitors positions and triggers rebalancing/DCA execution.

```bash
cd /home/ubuntu/hyperloop-vault/keeper

# Install dependencies
pnpm install

# Configure environment
cp .env.example .env
nano .env

# Add:
PRIVATE_KEY=your_keeper_wallet_private_key
RPC_URL=https://api.hyperliquid-mainnet.xyz/evm
VAULT_ADDRESS=0x... (your deployed vault)
CHECK_INTERVAL=300000 # 5 minutes

# Run keeper
pnpm start
```

**Important**: The keeper wallet needs HYPE for gas fees to execute rebalancing transactions.

---

## Step 6: Submit for Gas Reimbursement

Kurt from HypurrFi confirmed they'll reimburse gas fees. After deployment:

1. **Collect Transaction Hashes**:
   - Vault deployment tx
   - DCA vault deployment tx (if applicable)
   - Test deposit tx
   - Test withdraw tx
   - Any other testing transactions

2. **Calculate Total Gas Costs**:
   - Check each transaction on HyperEVM explorer
   - Note gas used and gas price
   - Calculate total HYPE spent

3. **Submit Reimbursement Request**:
   - Contact Kurt via Telegram (HypurrFi hackathon group)
   - Provide:
     - Your wallet address
     - List of transaction hashes
     - Total gas cost in HYPE
     - Brief description of what each tx was for

---

## Troubleshooting

### "Insufficient HYPE for gas"
- Get HYPE from HypurrFi team or exchange
- They confirmed they'll reimburse, so don't worry about upfront costs

### "Pool address not found"
- Verify you're using mainnet Pool address from docs.hypurr.fi
- Check you're connected to HyperEVM mainnet (not testnet)

### "WHYPE approval failed"
- Ensure WHYPE contract address is correct
- Check you have WHYPE balance
- Try increasing gas limit

### "Leverage loop failed"
- Check DEX router address is correct
- Verify WHYPE/USDXL pair has liquidity
- Reduce leverage multiplier and try again

### "Health factor calculation error"
- Ensure ProtocolDataProvider address is correct
- Check Pool is returning valid data
- Verify oracle prices are available

---

## Post-Deployment Checklist

- [ ] Vault contract deployed and verified
- [ ] DCA vault deployed (optional)
- [ ] Frontend updated with deployed addresses
- [ ] Deposit flow tested with real WHYPE
- [ ] Withdraw flow tested successfully
- [ ] Health factor monitoring works
- [ ] Keeper bot running (optional)
- [ ] Gas receipts collected for reimbursement
- [ ] Demo video recorded showing live transactions
- [ ] GitHub repository updated with deployed addresses
- [ ] Hackathon submission completed

---

## Security Notes

**Before Mainnet Deployment:**

1. **Audit Critical Functions**:
   - Review `deposit()`, `withdraw()`, `_executeLoop()`, `rebalance()`
   - Ensure proper access controls on admin functions
   - Verify reentrancy guards are in place

2. **Test Edge Cases**:
   - What happens if DEX swap fails?
   - What if health factor drops to 1.0?
   - Can users withdraw during rebalancing?

3. **Set Conservative Limits**:
   - Consider adding deposit cap for initial launch
   - Set maximum leverage to 3x or 4x initially
   - Implement emergency pause function

4. **Monitor Closely**:
   - Watch first few deposits carefully
   - Be ready to pause if issues arise
   - Keep keeper bot funded and running

---

## Support

- **HypurrFi Documentation**: https://docs.hypurr.fi
- **HypurrFi Telegram**: (hackathon group)
- **HyperEVM Explorer**: https://explorer.hyperliquid.xyz
- **Project Repository**: https://github.com/yourusername/hypurrloop-vault

---

## Next Steps After Deployment

1. **Record Demo Video** - Use `DEMO_VIDEO_SCRIPT.md` to create compelling 3-minute walkthrough
2. **Update README** - Add deployed contract addresses and live demo link
3. **Create Architecture Diagrams** - Add visual flowcharts to documentation
4. **Prepare Submission** - Gather all materials for hackathon judges
5. **Test with Real Users** - Share with community and gather feedback

Good luck with your deployment! 🚀
