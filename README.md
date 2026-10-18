# Stablevoy contracts

Smart contracts behind [Stablevoy](https://stablevoy.com), a non-custodial USDC and USDT payment gateway. Every invoice gets its own deposit address. Funds that reach it can only be swept to the merchant's payout address and the fixed platform fee recipient. Nobody, including the operator, can send them anywhere else.

## How it works

- `ForwarderFactory` computes a deterministic deposit address for each invoice with CREATE2. The address commits to `(invoiceSalt, merchant, feeBps)`, so the merchant and the fee are fixed the moment the address is shown to the buyer.
- `sweep(invoiceSalt, merchant, feeBps, token)` deploys the `Forwarder` clone (EIP-1167) on first use and moves the whole token balance: the merchant's share to the merchant, the fee to `feeRecipient`. `sweepNative` does the same for the native coin sent by mistake.
- `feeRecipient` and `maxFeeBps` are immutable. A fee above `maxFeeBps` is rejected.
- No owner, no upgrade path, no admin functions, no pause. Sweeping is permissionless: if the service disappears, a merchant can call `sweep` from a block explorer with the invoice parameters and get the funds.

See [SECURITY.md](SECURITY.md) for the guarantees, the static analysis triage and the known limits.

## Deployments

The same addresses on every network:

- `ForwarderFactory`: `0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e`
- `Forwarder` implementation: `0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd`
- `feeRecipient`: `0x2789ec50319F1cB0e53fbA1A198e25396cEDCFe7`
- `maxFeeBps`: `200` (2%)

Verified source on the block explorers:

- Base: [factory](https://basescan.org/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e#code), [implementation](https://basescan.org/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd#code)
- Arbitrum One: [factory](https://arbiscan.io/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e#code), [implementation](https://arbiscan.io/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd#code)
- OP Mainnet: [factory](https://optimistic.etherscan.io/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e#code), [implementation](https://optimistic.etherscan.io/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd#code)
- Polygon PoS: [factory](https://polygonscan.com/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e#code), [implementation](https://polygonscan.com/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd#code)
- BNB Smart Chain: [factory](https://bscscan.com/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e#code), [implementation](https://bscscan.com/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd#code)
- Avalanche C-Chain: [factory](https://snowtrace.io/address/0xF470C701B0338069Bc9E84352f7C44Ee9d207e0e/contract/43114/code), [implementation](https://snowtrace.io/address/0x8dCe63A0C1342f9ccaF8127164D78f2ace755FBd/contract/43114/code)

Do not send funds to the factory or the implementation address: there is no admin, so nobody can recover them.

## Build and test

Requires [Foundry](https://book.getfoundry.sh/).

```
./install-deps.sh
forge build
forge test
```

The fork tests run against a real stablecoin and are skipped unless both variables are set:

```
FORK_RPC_URL=https://... FORK_TOKEN=0x... forge test --match-path 'test/fork/*'
```

CI runs unit, fuzz and invariant tests, requires 100% coverage of `src/`, and runs `forge lint`, Slither and Aderyn.

## Reporting a vulnerability

Please write through the contact form at [stablevoy.com/contact](https://stablevoy.com/contact/) (topic "Something else", with "Security" at the start of the message). Do not open a public issue for a vulnerability.

## License

[MIT](LICENSE)
