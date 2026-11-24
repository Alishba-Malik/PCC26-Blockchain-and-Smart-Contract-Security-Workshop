# FluxVault — Smart Contract Audit Methodology

> Practical checklist for the FluxVault workshop. The objective is to **understand, hypothesize, reproduce, and report**; tool output alone is not a vulnerability proof.

## 1. Establish scope and intended behavior

Read the target source, compiler version, dependency tree, deployment parameters, and protocol description. For this workshop:

- **Assets:** ETH held by the vault, temporary flash-loan receivables, FLUX share claims.
- **Actors:** LPs, flash borrowers, contract-based callers, and arbitrary ETH senders.
- **Entry points:** `deposit`, `withdraw`, `transfer`, `flashLoan`, `receive`, and public view functions.
- **Trust boundaries:** External borrower callback; ETH transfers to arbitrary recipient contracts.
- **Out of scope:** Mainnet deployment and real-user funds; this is an educational local-only target.

**Deliverable:** A one-paragraph protocol summary and a list of assets and attacker capabilities.

## 2. Map value and execution flows

Trace each operation, recording its preconditions, balance changes, share changes, external calls, and final checks.

| Operation | Assets moving? | Shares moving? | External call? |
| --- | --- | --- | --- |
| `deposit()` | ETH enters | Mints shares | No borrower callback |
| `withdraw()` | ETH leaves | Burns shares | ETH transfer to caller |
| `transfer()` | No ETH movement | Moves shares | No |
| `flashLoan()` | ETH exits then must return with fee | Should not mint shares by itself | Yes, untrusted borrower callback |
| `receive()` | ETH enters | No shares issued | No |

**Instructor prompt:** Can another operation execute while the assumptions of the current operation are temporarily false?

## 3. Write security properties before attack code

These are **candidate properties**, not all enforced by the vulnerable implementation:

1. **Share fairness:** New shares should reflect the economic assets backing existing shares, not a temporarily depleted balance.
2. **LP protection:** A repaid flash loan should not enable a borrower to confiscate an unrelated LP's redeemable claim.
3. **Loan completion:** A successful flash loan restores principal and the required fee before completion.
4. **Share conservation:** Share balances and total supply should change consistently with minting, burning, and transfers.
5. **No unearned profit:** An adversarial sequence should not capture others' deposits solely through share-accounting distortion.

A property must specify its assumptions. For example, LP claims can legitimately change through losses, fees, deposits, withdrawals, donations, or protocol design. Avoid an unconditional claim that they can *never* decline under any imaginable operation.

## 4. Threat-model the untrusted caller

Assume an attacker can:

- Deploy a contract implementing the borrower callback.
- Call every public function they are authorized to call, in unusual sequences.
- Supply their own ETH and temporarily borrow pool ETH.
- Send ETH directly to the vault.
- Trigger external contract interactions and revert transactions.

Assume they **cannot** arbitrarily mutate another user's balances with Foundry cheatcodes in a valid on-chain exploit.

## 5. Reconnaissance tools

```bash
forge build
forge inspect FluxVault abi
forge inspect FluxVault storageLayout
forge inspect FluxVault deployedBytecode
forge test --match-test test_NormalDepositWithdrawal -vvv
```

With Anvil running, use `cast call` for reads, `cast send` for state-changing transactions, `cast storage` to inspect raw slots, `cast receipt` for events, and `cast run` for transaction traces.

**Evidence to save:** Target file/commit, relevant function locations, setup inputs, transaction traces, balances before/after, and test output.

## 6. Static analysis is a hypothesis generator

```bash
slither . --filter-paths 'lib/|test/|.solution/'
slither src/FluxVault.sol --print call-graph
slither src/FluxVault.sol --print vars-and-auth
```

Triage findings by asking:

- Does the reported pattern actually reach an attacker-controlled call?
- What protected state or economic value can change?
- Are there guards or invariants that prevent exploitation?
- Is the finding a duplicate, false positive, or reachable security defect?

A warning about an external call is **not** itself a confirmed exploit. Conversely, an economically broken invariant may not be recognized by an off-the-shelf detector.

## 7. Construct a minimal reproducible proof

A useful proof-of-concept includes:

1. **Setup:** Deploy the target and fund legitimate LPs.
2. **Baseline:** Record LP shares, vault ETH, and redeemable assets.
3. **Attack:** Execute only permitted transactions or contract calls.
4. **Outcome:** Show the attacker's net profit and the LP's loss, **after accounting for attacker-funded capital and fees**.
5. **Assertion:** Check the violated property numerically.

For FV-01:

```bash
forge test --match-test test_ExploitMintsInflatedSharesAndExtractsFunds -vvvv
forge test --match-test test_ExpectedInvariantBreaksUnderFlashLoan -vvvv
```

The second test is **intentionally failing**. Keep it separate from the passing regression suite:

```bash
forge test --skip test_ExpectedInvariantBreaksUnderFlashLoan -vvv
```

## 8. Testing strategy

| Test type | Goal | Example |
| --- | --- | --- |
| Unit / baseline | Confirm legitimate behavior | Deposit then redeem |
| Negative | Reject unauthorized / invalid actions | Excess-share withdrawal reverts |
| Exploit regression | Reproduce concrete loss | FV-01 share inflation |
| Security property | Express an invariant and expose failure | LP claim protection |
| Fuzz | Try varied amounts within reasonable bounds | Flash-loan sizes |
| Stateful fuzz / Echidna | Explore transaction sequences and invariant violations | Deposits, direct ETH transfers, redemptions |
| Patch regression | Original exploit fails while normal flow survives | `FluxVaultPatched` test |

For a 2-hour workshop, prioritize baseline, exploit, and patch tests. Treat Echidna as optional follow-up if time is limited.

## 9. Fix the cause, not the visible symptom

For FV-01, the demonstrated mitigation rejects deposits and withdrawals while a flash loan is active. Evaluate whether any other share-changing route remains reachable and test both adversarial and legitimate behaviors.

Checklist:

- [ ] The exact original exploit no longer succeeds.
- [ ] No economically equivalent exploit path remains unchecked.
- [ ] Normal deposits and redemptions still work.
- [ ] Honest flash loans still work.
- [ ] Share and asset accounting are consistent throughout execution.
- [ ] Tests preserve the contract's intended invariants across sequences.

**Scope warning:** A patch against FV-01 does not automatically resolve every independent vulnerability in the same vault.

## 10. Report findings professionally

Use a repeatable structure:

```text
ID / Title
Severity and assumptions
Summary
Affected contract/function
Technical root cause
Attack preconditions
Reproduction steps
Expected vs observed behavior
User/protocol impact
Recommendation
Patch verification and residual risks
```

Report a single exploit chain as a single finding where the same root cause explains the consequences. Separate findings when the defects have distinct causes, attack preconditions, and remediations.

### Example: FV-01

**Title:** Flash-loan-induced share inflation via incomplete asset accounting

**Root cause:** Minting shares using the ETH temporarily left on hand during an untrusted flash-loan callback.

**Impact:** Disproportionate share issuance lets a borrower extract existing LP value even though principal plus fee is repaid.

**Mitigation tested:** Blocking share changes during the loan.

## 11. Student challenge rules

For the independent exercise, participants may use documentation, Google, AI, and local development tools. The submitted proof should:

- Operate against the provided, unmodified target.
- Avoid `flashLoan()` if the challenge requires a non-flash-loan exploit.
- Demonstrate meaningful victim impact and attacker benefit.
- Use cheatcodes only for **test setup** or legitimate simulated callers, not to manufacture arbitrary vault state as the exploit.
- Provide reproducible test output and a short root-cause explanation.

The submission verifier should evaluate postconditions independently. **Do not trust a student's `forge test` success exit code alone**, and never run untrusted submissions with privileged GitHub/Supabase credentials or unrestricted access to the private verifier.

## Further practice

- [Foundry Book](https://getfoundry.sh/)
- [Slither](https://github.com/crytic/slither)
- [Echidna](https://github.com/crytic/echidna)
- [Ethernaut](https://ethernaut.openzeppelin.com/)
- [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/)
