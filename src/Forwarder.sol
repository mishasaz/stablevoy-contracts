// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IForwarderFactory} from "./IForwarderFactory.sol";

/// @title Forwarder
/// @notice Per-invoice deposit address. Deployed as an EIP-1167 clone by the factory.
///         Anything it holds can only ever go to the bound merchant and the factory's fee recipient.
///         Flushing is permissionless: anyone may trigger it, the destinations are fixed.
///         The fee recipient is immutable, so a fee transfer that fails (for example a stablecoin issuer blocking
///         that address) must never block merchants: the fee's share then goes to the merchant instead.
contract Forwarder {
    using SafeERC20 for IERC20;

    uint16 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice The factory that deployed the implementation. Shared by every clone through the code.
    address public immutable factory;

    address public merchant;
    uint16 public feeBps;

    error NotFactory();
    error ZeroMerchant();
    error AlreadyInitialized();
    error NotInitialized();
    error NativeTransferFailed(address to);

    /// @notice `token` is address(0) for the native coin.
    event Flushed(
        address indexed token,
        address indexed merchant,
        address indexed feeRecipient,
        uint256 merchantAmount,
        uint256 feeAmount
    );

    constructor() {
        factory = msg.sender;
    }

    receive() external payable {}

    function initialize(address merchant_, uint16 feeBps_) external {
        if (msg.sender != factory) revert NotFactory();
        if (merchant != address(0)) revert AlreadyInitialized();
        if (merchant_ == address(0)) revert ZeroMerchant();
        merchant = merchant_;
        // slither-disable-start events-maths
        // forge-lint: disable-next-line(missing-events-arithmetic) - the factory emits ForwarderDeployed with feeBps
        feeBps = feeBps_;
        // slither-disable-end events-maths
    }

    function flush(IERC20 token) external {
        address merchant_ = _requireInitialized();
        uint256 balance = token.balanceOf(address(this));
        // slither-disable-next-line incorrect-equality - plain no-op guard, not an access or accounting check
        if (balance == 0) return;

        (uint256 merchantAmount, uint256 feeAmount) = _split(balance);
        address feeRecipient = IForwarderFactory(factory).feeRecipient();

        if (feeAmount > 0 && !token.trySafeTransfer(feeRecipient, feeAmount)) {
            (merchantAmount, feeAmount) = (balance, 0);
        }
        // slither-disable-start reentrancy-events
        // forge-lint: disable-next-line(reentrancy-events) - reports the amounts actually paid, known after the fee transfer
        emit Flushed(address(token), merchant_, feeRecipient, merchantAmount, feeAmount);
        // slither-disable-end reentrancy-events
        token.safeTransfer(merchant_, merchantAmount);
    }

    function flushNative() external {
        address merchant_ = _requireInitialized();
        uint256 balance = address(this).balance;
        // slither-disable-next-line incorrect-equality - plain no-op guard, not an access or accounting check
        if (balance == 0) return;

        (uint256 merchantAmount, uint256 feeAmount) = _split(balance);
        address feeRecipient = IForwarderFactory(factory).feeRecipient();

        if (feeAmount > 0 && !_trySendNative(feeRecipient, feeAmount)) {
            (merchantAmount, feeAmount) = (balance, 0);
        }
        // slither-disable-start reentrancy-events
        // forge-lint: disable-next-line(reentrancy-events) - reports the amounts actually paid, known after the fee transfer
        emit Flushed(address(0), merchant_, feeRecipient, merchantAmount, feeAmount);
        // slither-disable-end reentrancy-events
        if (!_trySendNative(merchant_, merchantAmount)) revert NativeTransferFailed(merchant_);
    }

    function _requireInitialized() private view returns (address merchant_) {
        merchant_ = merchant;
        if (merchant_ == address(0)) revert NotInitialized();
    }

    /// @dev Fee rounds down, so any remainder goes to the merchant. The two parts always sum to `amount`.
    function _split(uint256 amount) private view returns (uint256 merchantAmount, uint256 feeAmount) {
        feeAmount = (amount * feeBps) / BPS_DENOMINATOR;
        merchantAmount = amount - feeAmount;
    }

    /// @dev Destinations are only the bound merchant and the immutable fee recipient, never caller-controlled.
    function _trySendNative(address to, uint256 amount) private returns (bool ok) {
        // slither-disable-start arbitrary-send-eth,low-level-calls
        // forge-lint: disable-next-line(arbitrary-send-eth) - destination fixed at deployment, see above
        (ok,) = to.call{value: amount}("");
        // slither-disable-end arbitrary-send-eth,low-level-calls
    }
}
