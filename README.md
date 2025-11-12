# ResFundDAO

**ResFundDAO** — *Decentralized Research Funding Pool*  

Version: 1.0  
Author: (Your Name)  

---

## Overview

**ResFundDAO** is a blockchain-based research funding platform built on the **Stacks blockchain** using **Clarity smart contracts**.  

This project allows researchers to submit proposals, and community members to fund them in a **transparent, secure, and decentralized** way. Funds are released milestone-by-milestone after verification by trusted verifiers, ensuring **accountability and trust** in research funding.

---

## Features

- **Proposal Submission**  
  Researchers can submit a proposal including title, description, funding goal, number of milestones, and funding deadline.  

- **Funding Contributions**  
  Community members can fund proposals with STX tokens. Contributions are recorded on-chain.  

- **Milestone Verification & Payouts**  
  Authorized verifiers (set by owner) approve milestones. Each approved milestone releases an equal tranche of funds to the researcher.  

- **Refund Mechanism**  
  If a proposal is cancelled, contributors can claim refunds securely.  

- **Verifiers Management**  
  Owner can add or remove verifiers responsible for milestone approvals.  

- **Emergency Withdrawals**  
  Owner can withdraw leftover funds if all contributions are refunded or the proposal is closed.  

---

## Smart Contract Structure

The smart contract is written in **Clarity** and includes:

- **Data Variables**  
  - `owner`: Contract deployer (principal)  
  - `proposal-counter`: Tracks incremental proposal IDs  

- **Maps**  
  - `proposals`: Stores proposals with details like researcher, title, funding goal, milestones, completed milestones, deadline, status, and refund flag.  
  - `contributions`: Tracks each funder's contribution to a proposal.  
  - `verifiers`: Stores authorized verifiers for milestone approval.  

- **Public Functions**  
  - `submit-proposal`: Create a new research proposal.  
  - `fund-proposal`: Contribute STX to a proposal.  
  - `cancel-proposal`: Cancel a proposal and enable refunds.  
  - `add-verifier` / `remove-verifier`: Manage verifiers (owner only).  
  - `approve-milestone`: Verifier approves milestone and triggers payout.  
  - `claim-refund`: Contributors claim refunds for cancelled proposals.  
  - `emergency-withdraw`: Owner withdraws leftover funds if needed.  

- **Read-only Functions**  
  - `get-proposal`: Retrieve proposal details.  
  - `get-contribution`: Retrieve a funder's contribution.  
  - `get-proposal-count`: Retrieve total number of proposals.  
  - `get-is-verifier`: Check if an account is an authorized verifier.  

---

## Events

The contract emits the following events for transparency:

- `proposal-created`  
- `proposal-funded`  
- `milestone-approved`  
- `proposal-cancelled`  
- `refund-claimed`  

---

## Installation & Deployment

1. **Clone the repository**  

```bash
git clone <repository-url>
cd ResFundDAO
