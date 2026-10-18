// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Forwarder} from "../../src/Forwarder.sol";

/// @dev A merchant contract that re-enters flushNative when paid.
contract ReentrantReceiver {
    Forwarder public target;
    uint256 public reentries;

    function setTarget(Forwarder target_) external {
        target = target_;
    }

    receive() external payable {
        if (address(target) != address(0) && reentries == 0) {
            reentries++;
            target.flushNative();
        }
    }
}
