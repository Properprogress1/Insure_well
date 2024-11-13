// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {InsureWell} from "../src/InsureWell.sol";

contract MyInsurance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        InsureWell INT = new InsureWell();  

        vm.stopBroadcast();
   }
}
