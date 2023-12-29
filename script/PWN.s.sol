// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import { PWN } from "../src/PWN.sol";
import { PWNEpochClock } from "../src/PWNEpochClock.sol";
import { StakedPWN } from "../src/StakedPWN.sol";
import { VoteEscrowedPWN } from "../src/VoteEscrowedPWN.sol";

contract Deploy is Script {

/*
forge script script/PWN.s.sol:Deploy \
--sig "deploy(address)" $DAO \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    function deploy(address dao) external {
        vm.startBroadcast();

        PWNEpochClock epochClock = new PWNEpochClock(block.timestamp);
        PWN pwnToken = new PWN(dao);
        VoteEscrowedPWN vePWN = new VoteEscrowedPWN();
        StakedPWN stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock), dao);

        console2.log("PWNEpochClock:", address(epochClock));
        console2.log("PWN:", address(pwnToken));
        console2.log("VoteEscrowedPWN:", address(vePWN));
        console2.log("StakedPWN:", address(stPWN));

        vm.stopBroadcast();
    }

}