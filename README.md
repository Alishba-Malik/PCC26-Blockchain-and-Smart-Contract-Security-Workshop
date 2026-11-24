# FluxVault — Smart Contract Security Audit Workshop

**A hands-on DeFi security workshop | Solidity · Foundry · Anvil · Cast · Slither**

FluxVault is an intentionally vulnerable Ethereum liquidity vault built to demonstrate how smart contracts can behave correctly at the function level while violating critical economic security properties.

This repository is designed for students and aspiring smart contract security researchers to explore real-world auditing techniques, reproduce a flash-loan accounting exploit, investigate vulnerabilities, and validate security patches.

> **Disclaimer:** FluxVault is an educational project containing intentionally vulnerable smart contracts. Do not deploy these contracts with real funds or use them in production.

---

## 1. About the Protocol

FluxVault is a simplified ETH liquidity vault where users deposit ETH and receive **FLUX shares** representing their proportional ownership of the vault.

The protocol supports four primary operations:

| Function | Description |
|---|---|
| `deposit()` | Deposit ETH and receive FLUX shares |
| `withdraw(uint256 shares)` | Burn shares and withdraw the corresponding ETH |
| `flashLoan(uint256 amount)` | Borrow ETH within a single transaction and repay it with a fee |
| `transfer(address to, uint256 shares)` | Transfer FLUX shares between addresses |

The vault charges a **0.1% flash-loan fee**, which remains in the vault and benefits existing share holders.

### Share accounting

When an existing vault receives a deposit, shares are calculated using:


\text{Shares Minted} = \frac{\text{ETH Deposited} \times \text{Total Shares}}{\text{Vault Assets Before Deposit}}


For example, if the vault contains 100 ETH and has 100 shares outstanding, depositing 10 ETH normally mints 10 shares.

The security of this accounting model depends on whether the vault measures its assets correctly during every possible execution path.

---

## 2. Repository Structure

```text
fluxvault-audit-lab/
├── README.md
├── LICENSE
├── foundry.toml
├── foundry.lock
├── .gitignore
├── .gitmodules
│
├── src/
│   ├── FluxVault.sol
│   ├── FluxVaultPatched.sol
│   └── FlashBorrower.sol
│
├── test/
│   ├── FluxVault.t.sol
│   ├── FluxVaultPatched.t.sol
│   └── Challenge.t.sol
│
├── docs/
│   ├── FV01-WALKTHROUGH.md
│   └── AUDIT-METHODOLOGY.md
│
└── lib/
    └── forge-std/
```

The instructor's FV-02 solution is intentionally excluded from this public repository until the challenge concludes.

## 3. Prerequisites

Install the following tools:

- [Foundry](https://getfoundry.sh/) — Forge, Cast and Anvil
- [Git](https://git-scm.com/)
- [Slither](https://github.com/crytic/slither) — Optional static analysis
- Solidity 0.8.24 — Managed automatically by Foundry

Verify:

```bash
forge --version
cast --version
anvil --version
git --version
```

## 4. Installation

Clone the repository with its Foundry dependency:

```bash
git clone --recursive https://github.com/YOUR_USERNAME/fluxvault-audit-lab.git
cd fluxvault-audit-lab
```

If you cloned the repository without `--recursive`, initialize the dependencies using:

```bash
git submodule update --init --recursive
```

Compile:

```bash
forge build
```

Run the normal, exploit, patch and fuzz tests:

```bash
forge test --skip test_ExpectedInvariantBreaksUnderFlashLoan -vvv
```

**Note:** One security-property test is deliberately designed to fail against the vulnerable implementation. See the guided audit for an explanation.

## 5. Workshop Exercises

### FV-01 — Flash-Loan Share Inflation

**Instructor-guided vulnerability demonstration**

FluxVault issues ownership shares using its current ETH balance. During a flash loan, that balance temporarily decreases.

The exercise investigates whether an attacker-controlled borrower can manipulate share issuance during the flash-loan callback and obtain an unfair portion of the vault's assets.

**Learning objectives:**

- Understand flash loans and callback execution.
- Analyze vault share accounting.
- Identify cross-function state inconsistencies.
- Develop an exploit proof of concept.
- Validate economic impact using Foundry.
- Review and test a targeted remediation.

Run the exploit demonstration:

```bash
forge test \
  --match-test test_ExploitMintsInflatedSharesAndExtractsFunds \
  -vvvv
```

Run the patched-contract regression:

```bash
forge test \
  --match-test test_PatchBlocksInflatedShareMint \
  -vvvv
```

For the complete audit process, see [FV-01 Audit Walkthrough](docs/FV01-WALKTHROUGH.md).

### FV-02 — Independent Security Challenge

**Student-led audit**

The protocol team has addressed the known flash-loan vulnerability in `FluxVaultPatched.sol`.

Your task is to investigate whether the patched implementation still contains an independent security weakness.

**Objectives:**

1. Review the vault's business logic and assumptions.
2. Identify a vulnerability unrelated to flash loans.
3. Develop a reproducible Foundry proof of concept.
4. Demonstrate measurable economic or security impact.
5. Explain the root cause and recommend a remediation.

**Rules:**

- Do not modify the provided protocol contracts.
- Do not use `flashLoan()` in your exploit.
- Do not use Foundry cheatcodes to manipulate the vault's balance as part of the attack.
- Use Foundry assertions to establish the impact.
- Document the assumptions and steps required for reproduction.

Start with:

```bash
forge test --match-contract ChallengeTest -vvvv
```

This command assumes `test/Challenge.t.sol` contains the supplied `ChallengeTest` starter contract.

Solutions will be published after the workshop.

## 6. Security Testing

### Forge

Run all tests, including the intentionally failing property:

```bash
forge test -vvv
```

Inspect the specific security-property failure:

```bash
forge test \
  --match-test test_ExpectedInvariantBreaksUnderFlashLoan \
  -vvvv
```

Fuzz different flash-loan amounts:

```bash
forge test \
  --match-test testFuzz_AttackerProfitsWithLargeLoans \
  --fuzz-runs 1000 \
  -vvv
```

### Slither

Analyze the vault:

```bash
slither src/FluxVault.sol
```

Inspect its call graph:

```bash
slither src/FluxVault.sol --print call-graph
```

Static analysis findings should be investigated and validated manually. A warning alone is not proof of an exploitable vulnerability.

## 7. Local Blockchain

Start Anvil:

```bash
anvil
```

Anvil creates a local Ethereum blockchain with funded development accounts.

Set an RPC endpoint in another terminal:

```bash
export RPC_URL=http://127.0.0.1:8545
```

Verify connectivity:

```bash
cast chain-id --rpc-url "$RPC_URL"
cast block-number --rpc-url "$RPC_URL"
```

The complete vault deployment, borrower deployment, funding, exploit transaction and verification commands are available in the [FV-01 Audit Walkthrough](docs/FV01-WALKTHROUGH.md).

Only use Anvil's disposable development accounts for these exercises.

---

## 8. Audit Methodology

The lab follows a structured security assessment process:

**Understand the protocol → Identify security assumptions → Inspect implementation → Form an exploit hypothesis → Build a proof of concept → Validate impact → Test remediation → Document findings**

For a detailed methodology, see [Audit Methodology](docs/AUDIT-METHODOLOGY.md).

## 9. Further Learning

Continue practicing with:

- [Ethernaut](https://ethernaut.openzeppelin.com/) — Smart contract security challenges
- [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) — DeFi exploitation exercises
- [Foundry Book](https://getfoundry.sh/) — Ethereum development and testing
- [Slither](https://github.com/crytic/slither) — Solidity static analysis
- [Solidity Security Considerations](https://docs.soliditylang.org/en/latest/security-considerations.html)

## 10. Workshop Information

**Workshop:** Blockchain & Smart Contract Security  
**Organizer:** National Cyber Security Academy (NCSA), Air University  
**Trainer:** Alishba Malik  
**Venue:** Lab 02  
**Date:** 24 November 2026


---

**The goal of this lab is not just to find a vulnerable line of Solidity. It is to understand how protocol assumptions fail, demonstrate the consequences through executable evidence, and learn how to verify that a security fix actually works.**