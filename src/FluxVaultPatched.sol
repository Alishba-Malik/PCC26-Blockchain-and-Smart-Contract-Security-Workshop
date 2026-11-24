// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFlashBorrower {
    function onFlashLoan(uint256 amount, uint256 fee) external payable;
}

contract FluxVaultPatched {
    uint256 public constant FEE_BPS = 10;
    uint256 private constant BPS = 10_000;
    string public constant name = "Flux Vault Share";
    string public constant symbol = "FLUX";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    bool private entered;
    bool private loanActive;
    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);
    event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);
    event Transfer(address indexed from, address indexed to, uint256 value);

    modifier nonReentrant() {
        require(!entered, "Reentrant call");
        entered = true;
        _;
        entered = false;
    }

    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 managed = totalAssets();
        if (supply == 0) return assets;
        require(managed != 0, "Empty vault");
        return assets * supply / managed;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return shares;
        return shares * totalAssets() / supply;
    }

    function deposit() external payable nonReentrant returns (uint256 shares) {
        require(!loanActive, "Shares locked during loan");
        require(msg.value > 0, "Zero deposit");
        uint256 assetsBefore = totalAssets() - msg.value;
        uint256 supply = totalSupply;
        shares = supply == 0 ? msg.value : msg.value * supply / assetsBefore;
        require(shares > 0, "Zero shares");
        balanceOf[msg.sender] += shares;
        totalSupply += shares;
        emit Deposit(msg.sender, msg.value, shares);
        emit Transfer(address(0), msg.sender, shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        require(!loanActive, "Shares locked during loan");
        require(shares > 0, "Zero shares");
        require(balanceOf[msg.sender] >= shares, "Insufficient shares");
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        (bool ok, ) = payable(msg.sender).call{value: assets}("");
        require(ok, "ETH transfer failed");
        emit Withdraw(msg.sender, assets, shares);
        emit Transfer(msg.sender, address(0), shares);
    }

    function transfer(address to, uint256 shares) external returns (bool) {
        require(to != address(0), "Zero recipient");
        require(balanceOf[msg.sender] >= shares, "Insufficient shares");
        balanceOf[msg.sender] -= shares;
        balanceOf[to] += shares;
        emit Transfer(msg.sender, to, shares);
        return true;
    }

    function flashLoan(uint256 amount) external {
        require(!loanActive, "Loan already active");
        require(amount > 0, "Zero loan");
        uint256 balanceBefore = address(this).balance;
        require(amount < balanceBefore, "Insufficient liquidity");
        uint256 fee = amount * FEE_BPS / BPS;
        require(fee > 0, "Loan too small");
        loanActive = true;
        IFlashBorrower(msg.sender).onFlashLoan{value: amount}(amount, fee);
        require(address(this).balance >= balanceBefore + fee, "Flash loan not repaid");
        loanActive = false;
        emit FlashLoan(msg.sender, amount, fee);
    }

    receive() external payable {}
}
