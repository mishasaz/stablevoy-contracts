// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IForwarderFactory {
    function feeRecipient() external view returns (address);
}
