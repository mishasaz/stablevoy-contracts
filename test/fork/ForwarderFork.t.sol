// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForwarderFactory} from "../../src/ForwarderFactory.sol";

/// @dev Runs the full sweep against a real stablecoin on a forked network.
///      Required env: FORK_RPC_URL, FORK_TOKEN. Without them the tests are reported as SKIPPED, never as passed.
///      Example: FORK_RPC_URL=https://base-rpc.example FORK_TOKEN=0x... forge test --match-path test/fork/*
contract ForwarderForkTest is Test {
    ForwarderFactory internal factory;
    IERC20 internal token;
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal merchant = makeAddr("merchant");

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        token = IERC20(vm.envAddress("FORK_TOKEN"));
        factory = new ForwarderFactory(feeRecipient, 200);
    }

    function test_fork_sweepRealStablecoin() public {
        bytes32 salt = keccak256("fork-invoice");
        address deposit = factory.computeAddress(salt, merchant, 50);
        uint256 amount = 1_000 * 10 ** _decimals();
        deal(address(token), deposit, amount);

        factory.sweep(salt, merchant, 50, token);

        assertEq(token.balanceOf(deposit), 0);
        assertEq(token.balanceOf(feeRecipient), amount * 50 / 10_000);
        assertEq(token.balanceOf(merchant), amount - amount * 50 / 10_000);
    }

    function _decimals() internal view returns (uint8) {
        (bool ok, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("decimals()"));
        require(ok && data.length == 32, "decimals");
        return abi.decode(data, (uint8));
    }
}
