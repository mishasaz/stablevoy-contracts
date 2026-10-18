// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {ForwarderFactory} from "../../src/ForwarderFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ForwarderHandler} from "./ForwarderHandler.sol";

/// @dev Funds leave a deposit address only towards its merchant or the fee recipient, nothing is created
///      or lost, and the fee never exceeds the immutable cap.
contract ForwarderInvariantsTest is Test {
    ForwarderFactory internal factory;
    MockERC20 internal token;
    ForwarderHandler internal handler;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        factory = new ForwarderFactory(feeRecipient, 200);
        token = new MockERC20("USD Coin", "USDC", 6);
        handler = new ForwarderHandler(factory, token);
        targetContract(address(handler));
    }

    function _accountedBalance() internal view returns (uint256 sum) {
        sum = token.balanceOf(feeRecipient);
        for (uint256 i = 0; i < handler.INVOICES(); i++) {
            sum += token.balanceOf(handler.merchants(i));
            sum += token.balanceOf(handler.depositOf(i));
        }
    }

    /// Every token ever minted sits at a deposit address, a merchant or the fee recipient. Nothing leaks elsewhere.
    function invariant_conservation() public view {
        assertEq(_accountedBalance(), handler.totalMinted());
        assertEq(token.totalSupply(), handler.totalMinted());
    }

    /// Fees never exceed the cap applied to everything swept.
    function invariant_feeWithinCap() public view {
        assertLe(token.balanceOf(feeRecipient) * 10_000, handler.totalSwept() * factory.maxFeeBps());
    }

    /// Swept volume equals what merchants and the fee recipient received.
    function invariant_sweptEqualsReceived() public view {
        uint256 received = token.balanceOf(feeRecipient);
        for (uint256 i = 0; i < handler.INVOICES(); i++) {
            received += token.balanceOf(handler.merchants(i));
        }
        assertEq(received, handler.totalSwept());
    }
}
