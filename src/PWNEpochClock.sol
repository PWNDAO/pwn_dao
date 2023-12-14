// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "./lib/Error.sol";

contract PWNEpochClock {

    // # INVARIANTS
    // - timestamps prior to `INITIAL_EPOCH_TIMESTAMP` are considered to be in epoch 0

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
    |*  # CLOCK                                                 *|
    |*----------------------------------------------------------*/

    // use timestamp to support chains with different block times
    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    /*----------------------------------------------------------*|
    |*  # EPOCH                                                 *|
    |*----------------------------------------------------------*/

    function currentEpoch() external view returns (uint256) {
        return _epochFor(block.timestamp);
    }

    function epochFor(uint256 timestamp) external view returns (uint256) {
        return _epochFor(timestamp);
    }

    function _epochFor(uint256 timestamp) internal view returns (uint256) {
        // timestamps prior to `INITIAL_EPOCH_TIMESTAMP` are considered to be in epoch 0
        if (timestamp < INITIAL_EPOCH_TIMESTAMP) {
            return 0;
        }
        // first epoch is 1
        return (timestamp - INITIAL_EPOCH_TIMESTAMP) / SECONDS_IN_EPOCH + 1;
    }

}
