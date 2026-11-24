// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "lib/forge-std/src/Test.sol";
import {FluxVaultPatched, IFlashBorrower} from "src/FluxVaultPatched.sol";

contract PatchedAttack is IFlashBorrower {
    FluxVaultPatched immutable vault;
    constructor(FluxVaultPatched _vault) { vault = _vault; }
    function attack() external { vault.flashLoan(99 ether); }
    function onFlashLoan(uint256, uint256) external payable {
        require(msg.sender == address(vault));
        vault.deposit{value: 1 ether}();
    }
    receive() external payable {}
}

contract FluxVaultPatchedTest is Test {
    FluxVaultPatched vault;
    PatchedAttack attacker;
    address alice = makeAddr("alice");

    function setUp() public {
        vault = new FluxVaultPatched();
        attacker = new PatchedAttack(vault);
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
        vm.deal(address(attacker), 2 ether);
    }

    function test_PatchBlocksInflatedShareMint() public {
        vm.expectRevert(bytes("Shares locked during loan"));
        attacker.attack();
        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 100 ether);
    }
}
