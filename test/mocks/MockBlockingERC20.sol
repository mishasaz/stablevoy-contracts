// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {MockERC20} from "./MockERC20.sol";

/// @dev A stablecoin whose issuer can block addresses, as Circle (USDC) and Tether (USDT) can: transfers to or from
///      a blocked address revert.
contract MockBlockingERC20 is MockERC20 {
    mapping(address account => bool blocked) public isBlocked;

    error Blocked(address account);

    constructor() MockERC20("Blockable USD", "BUSD", 6) {}

    function block_(address account) external {
        isBlocked[account] = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (isBlocked[from]) revert Blocked(from);
        if (isBlocked[to]) revert Blocked(to);
        super._update(from, to, value);
    }
}
