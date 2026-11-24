// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "lib/forge-std/src/Test.sol";
import {FluxVault} from "../src/FluxVault.sol";
import {FlashBorrower} from "../src/FlashBorrower.sol";

contract FluxVaultTest is Test {
    FluxVault vault;
    FlashBorrower attacker;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vault = new FluxVault();
        attacker = new FlashBorrower(vault);
        vm.deal(alice, 200 ether);
        vm.deal(bob, 200 ether);
        vm.deal(address(attacker), 2 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    function test_NormalDepositWithdrawal() public {
        vm.prank(bob);
        vault.deposit{value: 10 ether}();
        assertEq(vault.balanceOf(bob), 10 ether);
        vm.prank(bob);
        vault.withdraw(10 ether);
        assertEq(bob.balance, 200 ether);
    }

    function test_RevertWhenWithdrawMoreThanOwned() public {
        vm.prank(bob);
        vm.expectRevert(bytes("Insufficient shares"));
        vault.withdraw(1 ether);
    }

    function test_ExploitMintsInflatedSharesAndExtractsFunds() public {
        uint256 beforeAttack = address(attacker).balance;
        attacker.attack(99 ether, 1 ether);
        uint256 afterAttack = address(attacker).balance;
        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.balanceOf(address(attacker)), 0);
        assertGt(afterAttack, beforeAttack + 49 ether);
        assertLt(address(vault).balance, 51 ether);
    }

    function test_ExpectedInvariantBreaksUnderFlashLoan() public {
        // Intentionally fails: useful for teaching a property violation.
        // In a sound vault, existing depositors must not lose half of their
        // claim due to somebody else's repaid flash loan.
        attacker.attack(99 ether, 1 ether);
        assertGe(vault.convertToAssets(vault.balanceOf(alice)), 100 ether);
    }

    function testFuzz_AttackerProfitsWithLargeLoans(uint256 loan) public {
        loan = bound(loan, 50 ether, 99 ether);
        uint256 beforeAttack = address(attacker).balance;
        attacker.attack(loan, 1 ether);
        assertGt(address(attacker).balance, beforeAttack);
    }
}
