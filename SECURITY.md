# Contracts security notes

## Guarantees

- A deposit address commits to `(invoiceSalt, merchant, feeBps)` through the CREATE2 salt, and the factory's `feeRecipient` and `maxFeeBps` are immutable. Funds that reached an address can only ever go to that merchant and the fee recipient.
- No owner, no upgrade path, no admin functions, no pause.
- `sweep` / `sweepNative` and `Forwarder.flush` / `flushNative` are permissionless. If the service disappears, a merchant can recover funds by calling `sweep` from a block explorer with the invoice parameters.
- The fee rounds down; merchant amount plus fee always equals the swept balance (fuzz and invariant tested).
- A fee transfer that fails never blocks the merchant: if a stablecoin issuer blocks the fee recipient (or it rejects the native coin), the fee's share goes to the merchant in the same sweep (`trySafeTransfer`). Forcing that on purpose is not possible: only the issuer can block an address, and starving the fee transfer of gas leaves at most 1/64 of the gas for the merchant transfer, which then fails and reverts the whole sweep.

## Static analysis triage

Slither and `forge lint` run clean. Findings that are suppressed inline, with the reason:

- `arbitrary-send-eth`, `low-level-calls` (Forwarder `_sendNative`): destinations are only the bound merchant and the immutable fee recipient; a low-level call is required to send the native coin.
- `incorrect-equality` (`balance == 0`): an early-return no-op guard, not an access or accounting check.
- `events-maths` / `missing-events-arithmetic` (Forwarder `initialize`): `ForwarderDeployed` on the factory carries `feeBps` in the same transaction.
- `reentrancy-events` (factory): only an `extcodesize` read precedes the event; the event is emitted before the clone is created.
- `reentrancy-events` (Forwarder `flush` / `flushNative`): `Flushed` is emitted after the fee transfer on purpose, because it reports the amounts actually paid, which are known only then.

Aderyn 0.6.8 reports only low-severity notes, all accepted:

- L-1 large numeric literal: `10_000` is the basis-point denominator, written with a separator on purpose.
- L-2 state change without event: `Forwarder.initialize`, covered by the factory's `ForwarderDeployed` event (same as above).
- (fixed) L-3 public function not used internally: `computeAddress` is now `external`.

## Known limits

- No external review yet. Until there is one, the Stablevoy service caps the amount of each invoice.
- A merchant contract that rejects the native coin blocks `sweepNative` for its own forwarder only; ERC-20 sweeps are unaffected. A merchant address blocked by a stablecoin issuer blocks that merchant's own sweeps of that token only.
- Funds sent directly to the factory or the implementation address cannot be recovered by anyone (there is no admin by design). The security page warns about it next to the addresses.
