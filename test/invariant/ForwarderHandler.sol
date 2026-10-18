// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForwarderFactory} from "../../src/ForwarderFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @dev Drives random payments and sweeps over a fixed set of invoices and tracks every token holder.
contract ForwarderHandler is Test {
    ForwarderFactory public immutable factory;
    MockERC20 public immutable token;

    uint256 public constant INVOICES = 8;

    bytes32[INVOICES] public salts;
    address[INVOICES] public merchants;
    uint16[INVOICES] public fees;

    uint256 public totalMinted;
    uint256 public totalSwept;

    constructor(ForwarderFactory factory_, MockERC20 token_) {
        factory = factory_;
        token = token_;
        uint16 cap = factory_.maxFeeBps();
        for (uint256 i = 0; i < INVOICES; i++) {
            salts[i] = keccak256(abi.encode("invoice", i));
            merchants[i] = makeAddr(string(abi.encodePacked("merchant", vm.toString(i))));
            fees[i] = uint16((uint256(keccak256(abi.encode("fee", i))) % (uint256(cap) + 1)));
        }
    }

    function pay(uint256 invoiceIndex, uint96 amount) external {
        uint256 i = invoiceIndex % INVOICES;
        address deposit = factory.computeAddress(salts[i], merchants[i], fees[i]);
        token.mint(deposit, amount);
        totalMinted += amount;
    }

    /// @dev Callers come from a fixed actor set. Pranking as a not-yet-deployed deposit address would bump
    ///      its nonce in the test EVM, a state that cannot exist on a real network (nobody holds its key).
    function sweep(uint256 invoiceIndex, uint256 actorSeed) external {
        uint256 i = invoiceIndex % INVOICES;
        address deposit = factory.computeAddress(salts[i], merchants[i], fees[i]);
        totalSwept += token.balanceOf(deposit);
        vm.prank(makeAddr(string(abi.encodePacked("actor", vm.toString(actorSeed % 4)))));
        factory.sweep(salts[i], merchants[i], fees[i], IERC20(address(token)));
    }

    function depositOf(uint256 i) external view returns (address) {
        return factory.computeAddress(salts[i], merchants[i], fees[i]);
    }
}
