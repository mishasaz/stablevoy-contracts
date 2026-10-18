// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @notice Deploys the BSC testnet test stablecoin (no issuer deployment exists there). Testnet only.
///   TEST_TOKEN_HOLDER  address that receives the initial supply (the test payer)
///   TEST_TOKEN_SUPPLY  whole tokens to mint (18 decimals, like Binance-Peg on BSC mainnet)
/// Usage: forge script script/DeployTestToken.s.sol --rpc-url $RPC --account stablevoy-deployer --broadcast --verify
contract DeployTestToken is Script {
    uint256 private constant BSC_TESTNET = 97;

    function run() external returns (MockERC20 token) {
        require(block.chainid == BSC_TESTNET, "BSC testnet only");
        address holder = vm.envAddress("TEST_TOKEN_HOLDER");
        uint256 supply = vm.envUint("TEST_TOKEN_SUPPLY");
        require(supply > 0, "TEST_TOKEN_SUPPLY");

        vm.startBroadcast();
        token = new MockERC20("Stablevoy Test USDT", "USDT", 18);
        token.mint(holder, supply * 1e18);
        vm.stopBroadcast();

        console.log("test token", address(token));
        console.log("TOKENS_BSC_TESTNET=USDT:%s:18", address(token));
    }
}
