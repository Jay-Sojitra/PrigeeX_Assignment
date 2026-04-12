// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PrigeeX.sol";
import "../src/PrigeeXStaking.sol";

contract DeployScript is Script {
    uint256 constant INITIAL_SUPPLY = 1_000_000 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PrigeeX token = new PrigeeX(INITIAL_SUPPLY);
        console.log("PrigeeX Token deployed at:", address(token));

        // Use PGX as both staking and reward token
        PrigeeXStaking staking = new PrigeeXStaking(address(token), address(token));
        console.log("PrigeeXStaking deployed at:", address(staking));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Network: Sepolia");
        console.log("Token Name: PrigeeX (PGX)");
        console.log("Initial Supply:", INITIAL_SUPPLY / 1 ether, "PGX");
        console.log("");
        console.log("PrigeeX Token:", address(token));
        console.log("PrigeeXStaking:", address(staking));
    }
}
