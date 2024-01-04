// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "./lib/Error.sol";

/// @title PWN Epoch Clock contract.
/// @notice A contract that provides the current epoch number.
/// @dev One epoch is 4 weeks long and the first epoch is 1.
/// `INITIAL_EPOCH_TIMESTAMP` is set at deployment time and can be used to sync the clock between different chains.
contract PWNEpochClock {

    /// @notice The number of seconds in an epoch.
    /// @dev 2,419,200 seconds = 4 weeks
    uint256 public constant SECONDS_IN_EPOCH = 2_419_200; // 4 weeks
    /// @notice The timestamp of the first epoch.
    /// @dev This timestamp is set at deployment time and can be used to sync the clock between different chains.
    // solhint-disable-next-line immutable-vars-naming
    uint256 public immutable INITIAL_EPOCH_TIMESTAMP;

    /// @notice PWNEpochClock constructor.
    /// @param initialEpochTimestamp The timestamp of the beginning of the first epoch.
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

    /// @notice Returns the current epoch number.
    /// @return The current epoch number.
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
