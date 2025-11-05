// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {TokenConversion} from "../src/TokenConversion.sol";

// OpenZeppelin Proxy Contracts
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TokenConversionScript is Script {
    //    uint256 constant START_TIME = 1_713_000_000;
    //    uint256 constant END_TIME = 1_723_000_000;

    function run() public {
        uint256 START_TIME = block.timestamp;
        uint256 END_TIME = START_TIME + 365 days;

        uint256 deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

        address admin = vm.envAddress("ADMIN_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        address oldQKC = vm.envAddress("OLD_QKC_ADDRESS");
        address optimismPortal2 = vm.envAddress("OPTIMISM_PORTAL2");

        vm.startBroadcast(deployerKey);
        // impl
        TokenConversion impl = new TokenConversion();
        // init data
        bytes memory initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            oldQKC,
            optimismPortal2,
            START_TIME,
            END_TIME,
            admin,
            pauser
        );
        // Transparent Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), admin, initData);

        address proxyAdmin = getAdmin(address(proxy));
        console.log("Implementation:", address(impl));
        console.log("ProxyAdmin:", proxyAdmin);
        console.log("Proxy:", address(proxy));

        TokenConversion tc = TokenConversion(address(proxy));
        console.log("erc20In:", tc.erc20In());
        console.log("optimismPortal2:", tc.optimismPortal2());
        vm.stopBroadcast();
    }

    function getAdmin(address proxy) internal view returns (address admin) {
        bytes32 ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        return address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
    }
}
