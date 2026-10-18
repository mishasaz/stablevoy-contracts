// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Forwarder} from "./Forwarder.sol";
import {IForwarderFactory} from "./IForwarderFactory.sol";

/// @title ForwarderFactory
/// @notice Computes and deploys per-invoice deposit forwarders at deterministic addresses and sweeps them.
///         The deposit address commits to (invoiceSalt, merchant, feeBps), and the fee recipient and fee cap
///         are immutable, so nobody, including the operator, can redirect funds that reached an address.
///         No owner, no upgrade path, no admin functions. Sweeping is permissionless.
contract ForwarderFactory is IForwarderFactory {
    uint16 public constant BPS_DENOMINATOR = 10_000;

    address public immutable implementation;
    address public immutable feeRecipient;
    uint16 public immutable maxFeeBps;

    error ZeroAddress();
    error FeeAboveCap(uint16 feeBps, uint16 maxFeeBps);
    error CapAboveDenominator(uint16 maxFeeBps);

    event ForwarderDeployed(
        bytes32 indexed invoiceSalt, address indexed forwarder, address indexed merchant, uint16 feeBps
    );

    constructor(address feeRecipient_, uint16 maxFeeBps_) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (maxFeeBps_ > BPS_DENOMINATOR) revert CapAboveDenominator(maxFeeBps_);
        feeRecipient = feeRecipient_;
        maxFeeBps = maxFeeBps_;
        implementation = address(new Forwarder());
    }

    /// @notice Deposit address for an invoice. Reverts for parameters that could never be swept.
    function computeAddress(bytes32 invoiceSalt, address merchant, uint16 feeBps) external view returns (address) {
        _validate(merchant, feeBps);
        return Clones.predictDeterministicAddress(implementation, _salt(invoiceSalt, merchant, feeBps));
    }

    function sweep(bytes32 invoiceSalt, address merchant, uint16 feeBps, IERC20 token)
        external
        returns (address forwarder)
    {
        forwarder = _deployIfNeeded(invoiceSalt, merchant, feeBps);
        Forwarder(payable(forwarder)).flush(token);
    }

    function sweepNative(bytes32 invoiceSalt, address merchant, uint16 feeBps) external returns (address forwarder) {
        forwarder = _deployIfNeeded(invoiceSalt, merchant, feeBps);
        Forwarder(payable(forwarder)).flushNative();
    }

    function _deployIfNeeded(bytes32 invoiceSalt, address merchant, uint16 feeBps) private returns (address forwarder) {
        _validate(merchant, feeBps);
        bytes32 salt = _salt(invoiceSalt, merchant, feeBps);
        forwarder = Clones.predictDeterministicAddress(implementation, salt);
        if (forwarder.code.length == 0) {
            // forge-lint: disable-next-line(reentrancy-events) - only a code-size read precedes it, no external call
            emit ForwarderDeployed(invoiceSalt, forwarder, merchant, feeBps);
            forwarder = Clones.cloneDeterministic(implementation, salt);
            Forwarder(payable(forwarder)).initialize(merchant, feeBps);
        }
    }

    function _validate(address merchant, uint16 feeBps) private view {
        if (merchant == address(0)) revert ZeroAddress();
        if (feeBps > maxFeeBps) revert FeeAboveCap(feeBps, maxFeeBps);
    }

    function _salt(bytes32 invoiceSalt, address merchant, uint16 feeBps) private pure returns (bytes32) {
        return keccak256(abi.encode(invoiceSalt, merchant, feeBps));
    }
}
