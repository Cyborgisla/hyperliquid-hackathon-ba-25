# Task Title
Unlocking Yield Optimization with GlueX Yields API

## 1. Problem Statement

APY volatility is huge. This means, there is a very big opportunity for strong yield optimization services that can reallocate lending positions across HyperEVM markets. Users should get the best sharpe for their capital, i.e. highest yield at lowest risk.

## 2. Goal / What to Build
Use GlueX Yields API and GlueX Router API for off-chain yield optimization and ERC-7540 or BoringVault for on-chain custody to build a yield optimizer protocol. 

## 3. Core Requirements (Acceptance Criteria)
List **exactly what must be working** for the task to be considered complete.

- [ ] ERC-7540 or BoringVault to custody assets and restrict the vaults with which the optimizer can interact.
- [ ] Use GlueX Yields API to identify the highest yield opportunity at the given moment.
- [ ] Use GlueX Router API to reallocate the assets to the highest yield opportunity.
- [ ] Include GlueX Vaults in the set of whitelisted vaults among which capital is allocated.

## 4. Deliverables
What teams need to submit.

- GitHub repo (public or private w/ access granted)
- README with setup instructions
- Short demo video (≤ 3 minutes)

If something else is required, add it here.

## 5. Technical Notes / Helpful Links

- GlueX Portal (to get access credentials): https://portal.gluex.xyz
- GlueX Router API docs: https://docs.gluex.xyz/api-reference/router-api/post-quote
- GlueX Yields API docs: https://docs.gluex.xyz/api-reference/yield-api/post-historical-apy
- GlueX Vault addresses: 0xe25514992597786e07872e6c5517fe1906c0cadd, 0xcdc3975df9d1cf054f44ed238edfb708880292ea, 0x8f9291606862eef771a97e5b71e4b98fd1fa216a, 0x9f75eac57d1c6f7248bd2aede58c95689f3827f7, 0x63cf7ee583d9954febf649ad1c40c97a6493b1be


## 6. Suggested Tech Stack (Optional)

- Frontend: React or Next.js
- Backend: Python
- Smart Contracts: Solidity + Foundry or Hardhat

## 7. Difficulty Level & Estimated Time
**Difficulty:** Intermediate   
**Estimated Time:** 10–20+

## 8. Stretch Goals (Optional Bonus Points)
None

## 9. Evaluation Criteria (How Judges Score)
Sponsors can leave this section unchanged - organizers apply the hackathon rubric.

**Judges score on:**
- Impact & Ecosystem Fit
- Execution & User Experience
- Technical Creativity & Design
- Completeness & Demo Quality