// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script, console} from "forge-std/Script.sol";
import {ForwarderFactory} from "../src/ForwarderFactory.sol";

/// @notice Deploys the factory. All parameters are required, no defaults.
///   FEE_RECIPIENT  address that receives the platform fee (immutable)
///   MAX_FEE_BPS    immutable fee cap (200 = 2%)
/// Usage: forge script script/Deploy.s.sol --rpc-url $RPC --account <keystore> --broadcast --verify
contract Deploy is Script {
    function run() external returns (ForwarderFactory factory) {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 maxFeeBps = vm.envUint("MAX_FEE_BPS");
        require(maxFeeBps <= 10_000, "MAX_FEE_BPS");

        vm.startBroadcast();
        factory = new ForwarderFactory(feeRecipient, uint16(maxFeeBps));
        vm.stopBroadcast();

        console.log("ForwarderFactory", address(factory));
        console.log("implementation", factory.implementation());
    }
}
