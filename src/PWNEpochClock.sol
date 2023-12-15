// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "./lib/Error.sol";

contract PWNEpochClock {

    // # INVARIANTS
    // - timestamps prior to `INITIAL_EPOCH_TIMESTAMP` are in epoch 0

    uint256 public constant SECONDS_IN_EPOCH = 2_419_200; // 4 weeks
    // solhint-disable-next-line immutable-vars-naming
    uint256 public immutable INITIAL_EPOCH_TIMESTAMP;

    constructor(uint256 initialEpochTimestamp) {
        // provide `initialEpochTimestamp` to sync the clock between different chains
        if (initialEpochTimestamp > block.timestamp) {
            revert Error.InitialEpochTimestampInFuture(block.timestamp);
        }
        INITIAL_EPOCH_TIMESTAMP = initialEpochTimestamp;
    }


    /*----------------------------------------------------------*|
    |*  # CURRENT EPOCH                                         *|
    |*----------------------------------------------------------*/

    function currentEpoch() external view returns (uint16) {
        // timestamps prior to `INITIAL_EPOCH_TIMESTAMP` are considered to be in epoch 0
        if (block.timestamp < INITIAL_EPOCH_TIMESTAMP) {
            return 0;
        }
        // first epoch is 1
        uint256 epoch = (block.timestamp - INITIAL_EPOCH_TIMESTAMP) / SECONDS_IN_EPOCH + 1;
        return uint16(epoch); // safe cast for the next 5041 years after deployment
    }

}
