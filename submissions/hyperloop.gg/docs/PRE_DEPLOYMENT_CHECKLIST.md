# Pre-Deployment Checklist for HypurrLoop Vault

Complete this checklist before deploying to HyperEVM mainnet to ensure a smooth launch.

---

## 1. Contract Preparation

### Smart Contract Review
- [ ] **HypurrAutoLoopVault.sol** compiled without errors
- [ ] **DCAVault.sol** compiled without errors (if deploying)
- [ ] All OpenZeppelin dependencies resolved
- [ ] Solidity version set to `0.8.20`
- [ ] Optimization enabled (200 runs)

### Security Checks
- [ ] Reentrancy guards on all external functions
- [ ] Access control properly implemented (onlyOwner where needed)
- [ ] Emergency pause function exists and tested
- [ ] No hardcoded addresses (all passed via constructor)
- [ ] Integer overflow protection (Solidity 0.8+ default)

### Function Validation
- [ ] `deposit()` - tested with mock data
- [ ] `withdraw()` - tested with mock data
- [ ] `_executeLoop()` - logic reviewed
- [ ] `rebalance()` - health factor thresholds correct
- [ ] `totalAssets()` - calculation verified
- [ ] `convertToShares()` / `convertToAssets()` - math checked

---

## 2. Contract Addresses Collection

### HypurrFi Mainnet Addresses (from docs.hypurr.fi)
- [ ] **Pool (LendingPool)**: `0x________________`
- [ ] **PoolAddressesProvider**: `0x________________`
- [ ] **ProtocolDataProvider**: `0x________________`
- [ ] **PriceOracle**: `0x________________` (if needed)

### Token Addresses
- [ ] **WHYPE**: `0x________________`
- [ ] **USDXL**: `0x________________`
- [ ] **aWHYPE** (aToken): `0x________________` (if needed)
- [ ] **variableDebtUSDXL**: `0x________________` (if needed)

### DEX Addresses
- [ ] **DEX Router** (for USDXL ↔ WHYPE swaps): `0x________________`
- [ ] **WHYPE/USDXL Pair**: `0x________________` (verify liquidity exists)

---

## 3. Wallet & Network Setup

### MetaMask Configuration
- [ ] HyperEVM Mainnet added to MetaMask
- [ ] Network Name: `Hyperliquid`
- [ ] RPC URL: `https://api.hyperliquid-mainnet.xyz/evm` (verify correct URL)
- [ ] Chain ID: `998` (verify mainnet chain ID)
- [ ] Currency Symbol: `HYPE`
- [ ] Block Explorer: `https://explorer.hyperliquid.xyz`

### Wallet Funding
- [ ] Deployer wallet has sufficient HYPE for gas (~0.5-1 HYPE recommended)
- [ ] Test wallet has WHYPE tokens for testing deposits
- [ ] Keeper wallet has HYPE for rebalancing gas (if using keeper bot)

---

## 4. Frontend Configuration

### Update Contract Addresses
- [ ] Edit `client/src/lib/contracts.ts`
- [ ] Set `ASSET_ADDRESSES.WHYPE` to mainnet address
- [ ] Set `ASSET_ADDRESSES.USDXL` to mainnet address
- [ ] Set `ASSET_ADDRESSES.POOL` to mainnet Pool address
- [ ] Set `ASSET_ADDRESSES.DATA_PROVIDER` to mainnet address
- [ ] Set `ASSET_ADDRESSES.DEX_ROUTER` to mainnet DEX address
- [ ] Update chain ID in `web3Config.ts` if needed

### Test Frontend Locally
- [ ] Run `pnpm dev` successfully
- [ ] No console errors on page load
- [ ] "Connect Wallet" button works
- [ ] Wallet connection shows correct network
- [ ] APY ticker displays (even with mock data)
- [ ] Risk calculator slider works
- [ ] Deposit modal opens and closes
- [ ] Withdraw modal opens and closes
- [ ] DCA modal opens and closes (if implemented)

---

## 5. Deployment Execution

### Deploy HypurrAutoLoopVault
- [ ] Open Remix IDE (remix.ethereum.org)
- [ ] Paste contract code
- [ ] Compile successfully
- [ ] Switch MetaMask to HyperEVM Mainnet
- [ ] Prepare constructor arguments:
  - `_asset`: WHYPE address
  - `_hypurrPool`: Pool address
  - `_dexRouter`: DEX Router address
  - `_name`: "HypurrLoop Vault WHYPE"
  - `_symbol`: "hlvWHYPE"
- [ ] Deploy contract
- [ ] **Save deployed address**: `0x________________`
- [ ] **Save deployment tx hash**: `0x________________`
- [ ] Verify contract on block explorer (optional but recommended)

### Deploy DCAVault (Optional)
- [ ] Paste DCAVault.sol code in Remix
- [ ] Compile successfully
- [ ] Prepare constructor arguments:
  - `_baseVault`: HypurrAutoLoopVault address (from above)
  - `_hypurrPool`: Pool address
  - `_dexRouter`: DEX Router address
- [ ] Deploy contract
- [ ] **Save deployed address**: `0x________________`
- [ ] **Save deployment tx hash**: `0x________________`

---

## 6. Post-Deployment Configuration

### Update Frontend with Deployed Addresses
- [ ] Set `ASSET_ADDRESSES.VAULT` to deployed HypurrAutoLoopVault address
- [ ] Set `ASSET_ADDRESSES.DCA_VAULT` to deployed DCAVault address (if applicable)
- [ ] Commit changes to git
- [ ] Push to GitHub repository

### Initial Contract Setup (if needed)
- [ ] Call `setMaxLeverage()` if you want to limit initial leverage
- [ ] Call `setRebalanceThresholds()` if defaults need adjustment
- [ ] Transfer ownership to multisig (if using one)

---

## 7. Testing on Mainnet

### Smoke Tests (Small Amounts!)
- [ ] **Test 1: Deposit**
  - Amount: 0.1 WHYPE
  - Leverage: 2x (Conservative)
  - Expected: Position opens, shares minted
  - Result: ✅ / ❌
  - Tx Hash: `0x________________`

- [ ] **Test 2: Check Position**
  - Dashboard shows collateral amount
  - Dashboard shows debt amount
  - Health factor displays correctly
  - Health factor > 1.5 (safe zone)
  - Result: ✅ / ❌

- [ ] **Test 3: Withdraw Partial**
  - Amount: 50% of shares
  - Expected: Partial unwind, WHYPE returned
  - Result: ✅ / ❌
  - Tx Hash: `0x________________`

- [ ] **Test 4: Withdraw Full**
  - Amount: 100% of remaining shares
  - Expected: Full unwind, all WHYPE returned
  - Result: ✅ / ❌
  - Tx Hash: `0x________________`

### DCA Tests (if deployed)
- [ ] **Test 5: Configure DCA**
  - Schedule: Daily, 0.1 WHYPE
  - Max LTV: 70%
  - Expected: DCA schedule created
  - Result: ✅ / ❌
  - Tx Hash: `0x________________`

- [ ] **Test 6: Execute DCA** (manual trigger or wait for keeper)
  - Expected: Incremental deposit executed
  - Result: ✅ / ❌
  - Tx Hash: `0x________________`

### Keeper Bot Tests (if deployed)
- [ ] Keeper bot running without errors
- [ ] Keeper monitors health factor correctly
- [ ] Keeper triggers rebalance when HF < 1.5
- [ ] Keeper executes DCA on schedule

---

## 8. Documentation & Submission

### Update Documentation
- [ ] Update `README.md` with:
  - Deployed contract addresses
  - Live demo link (if frontend hosted)
  - Architecture diagrams
  - How to use guide
- [ ] Update `ADDRESSES.md` with mainnet addresses
- [ ] Add deployment tx hashes to docs
- [ ] Create `ARCHITECTURE.md` with diagrams

### Record Demo Video
- [ ] Follow `DEMO_VIDEO_SCRIPT.md`
- [ ] Record 3-minute walkthrough
- [ ] Show live mainnet transactions
- [ ] Highlight key features (leverage, DCA, auto-rebalancing)
- [ ] Upload to YouTube
- [ ] Add video link to README

### Prepare Hackathon Submission
- [ ] GitHub repository is public
- [ ] README is comprehensive
- [ ] All contracts are in `/contracts` folder
- [ ] Frontend code is in `/client` folder
- [ ] Deployment guide is clear
- [ ] Demo video is linked
- [ ] Architecture diagrams are included
- [ ] License file added (MIT recommended)

---

## 9. Gas Fee Reimbursement

### Collect Transaction Details
- [ ] List all deployment tx hashes
- [ ] List all testing tx hashes
- [ ] Calculate total gas cost in HYPE
- [ ] Screenshot transactions from block explorer

### Submit to HypurrFi
- [ ] Contact Kurt via Telegram (HypurrFi hackathon group)
- [ ] Provide wallet address for reimbursement
- [ ] Provide list of tx hashes
- [ ] Provide total HYPE spent on gas
- [ ] Brief description of each transaction

---

## 10. Final Checks

### Security
- [ ] No private keys committed to git
- [ ] `.env` file in `.gitignore`
- [ ] Admin functions protected with `onlyOwner`
- [ ] Emergency pause function accessible

### User Experience
- [ ] Landing page loads quickly
- [ ] Interactive calculator works smoothly
- [ ] FAQ section explains everything clearly
- [ ] Error messages are helpful
- [ ] Loading states show during transactions

### Hackathon Requirements
- [ ] Uses HypurrFi Pool for supply/borrow
- [ ] Integrates USDXL (bonus points!)
- [ ] Demonstrates technical creativity (leverage loops)
- [ ] Shows execution quality (polished UI)
- [ ] Includes comprehensive documentation
- [ ] Has working demo on mainnet

---

## Deployment Day Timeline

### Morning (2-3 hours)
1. Complete checklist items 1-4
2. Gather all contract addresses
3. Test frontend locally
4. Review contracts one final time

### Afternoon (2-3 hours)
5. Deploy contracts to mainnet
6. Update frontend with deployed addresses
7. Run smoke tests with small amounts
8. Fix any issues discovered

### Evening (2-3 hours)
9. Record demo video
10. Update all documentation
11. Submit for hackathon
12. Submit gas reimbursement request

---

## Emergency Contacts

- **HypurrFi Support**: Telegram hackathon group
- **Kurt (HypurrFi)**: @Kurt_BTW on Telegram
- **HyperEVM Explorer**: https://explorer.hyperliquid.xyz
- **HypurrFi Docs**: https://docs.hypurr.fi

---

## Notes

Use this space to track any issues or observations during deployment:

```
Issue 1: [Description]
Solution: [How you fixed it]

Issue 2: [Description]
Solution: [How you fixed it]
```

---

**Good luck with your deployment! 🚀**

Remember: Start with small test amounts, verify each step works, then scale up. HypurrFi will reimburse your gas fees, so don't hesitate to test thoroughly.
