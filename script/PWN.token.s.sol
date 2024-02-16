// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import { TransparentUpgradeableProxy }
    from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { PWN } from "src/token/PWN.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";
import { VoteEscrowedPWN } from "src/token/VoteEscrowedPWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

contract Deploy is Script {

/*
forge script script/PWN.token.s.sol:Deploy \
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
        VoteEscrowedPWN vePWNImpl = new VoteEscrowedPWN();
        VoteEscrowedPWN vePWN = VoteEscrowedPWN(address(
            new TransparentUpgradeableProxy({
                _logic: address(vePWNImpl),
                admin_: dao,
                _data: ""
            })
        ));
        StakedPWN stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock));

        console2.log("PWNEpochClock:", address(epochClock));
        console2.log("PWN:", address(pwnToken));
        console2.log("VoteEscrowedPWN:", address(vePWN));
        console2.log("StakedPWN:", address(stPWN));

        vm.stopBroadcast();
    }

}
