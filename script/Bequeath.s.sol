// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Bequeath} from "../src/Bequeath.sol";

contract BequeathScript is Script {
    Bequeath public bequeath;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // deploy
        // bequeath = new Bequeath();
        // console.log("Bequeath deployed at:", address(bequeath));

        vm.stopBroadcast();
    }
}
