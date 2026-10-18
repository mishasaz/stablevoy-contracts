// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @dev A merchant contract that refuses native coin.
contract RejectingReceiver {
    receive() external payable {
        revert("no native");
    }
}
