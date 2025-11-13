# Task Title

LoopDrops and Loyalty Rewards Distribution Bot Using Multisig

## 1. Problem Statement

Looping Collective runs recurring LoopDrops and ongoing Loyalty Rewards across multiple tokens (LOOP, LEND, ...). Today, calculating entitlements and executing payouts involves ad-hoc scripts, spreadsheets, and manual multisig transactions. This is slow, error-prone, and hard to audit, creating operational risk and community mistrust when discrepancies occur.

## 2. Goal / What to Build

Build an automated distribution system that programmatically accepts or uploads distribution lists for LoopDrops and Loyalty Rewards, generates multisig transaction proposals, and provides a transparent audit trail. The system should integrate with multisig wallets (e.g., Safe, Onchainden) to execute token distributions securely and programmatically.

## 3. Core Requirements (Acceptance Criteria)

List **exactly what must be working** for the task to be considered complete.

- [ ] Programmatic acceptance or upload of distribution lists (CSV, JSON, or API format) containing recipient addresses and token amounts for LoopDrops and Loyalty Rewards.
- [ ] Integration with multisig wallet (Safe/Onchainden or similar) to create and propose distribution transactions.
- [ ] Support for multiple token types (LOOP, LEND, and other tokens as specified).
- [ ] Audit trail/logging system that records all distribution lists, proposed transactions, and execution status.
- [ ] Ability to handle both LoopDrops (scheduled distributions) and recurring Loyalty Rewards (continuous accrual).
- [ ] User interface or API to view entitlements, pending distributions, and historical payouts.

## 4. Deliverables

What teams need to submit.

- PR with functional code
- README with setup instructions
- Short demo video (≤ 3 minutes) - optional

## 5. Technical Notes / Helpful Links

- LOOP token address: 0x00fdbc53719604d924226215bc871d55e40a1009
- Note: Current HyperEVM multisig solution is not great with Onchainden. Teams should consider alternative approaches or improvements to the multisig integration.

## 6. Suggested Tech Stack (Optional)

- Frontend: Next.js, Vercel (for viewing entitlements and distributions)
- Backend: Node.js, Golang (for distribution list processing and multisig integration)
- Smart Contracts: Solidity
- Multisig Integration: Safe SDK or Safe API

## 7. Difficulty Level & Estimated Time

**Difficulty:** Intermediate  
**Estimated Time:** 10–20h+

## 8. Stretch Goals (Optional Bonus Points)

- Onchainden alternative
- Gas optimization for batch token transfers

## 9. Evaluation Criteria (How Judges Score)

**Judges score on:**

- **Security and Robustness** (Primary Focus): Secure handling of distribution lists, validation of inputs, protection against errors or malicious data, failover mechanisms, and safe multisig transaction handling.
- Execution & User Experience
- Completeness & Demo Quality
