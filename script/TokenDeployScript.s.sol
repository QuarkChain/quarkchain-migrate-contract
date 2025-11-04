// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {TokenConversion} from "../src/TokenConversion.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract TokenDeployScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");
        vm.startBroadcast(deployerKey);

        // impl
        MockToken oldQKC = new MockToken("QuarkChain Old", "oQKC", false);
        oldQKC.mint();

        console.log("oldQKC:", address(oldQKC));
        vm.stopBroadcast();
    }
}
