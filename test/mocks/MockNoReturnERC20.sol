// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @dev Mimics legacy USDT: `transfer` returns nothing. Plain IERC20 calls would revert on decoding;
///      SafeERC20 must handle it.
contract MockNoReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}
