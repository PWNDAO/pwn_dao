// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

contract PWNEpochClock {

    // # INVARIANTS
    // - first epoch is epoch 1
    // - timestamps prior to `INITIAL_EPOCH_TIMESTAMP` are considered to be in epoch 0


    uint256 public constant EPOCH_IN_SECONDS = 2_419_200; // 4 weeks
    uint256 public immutable INITIAL_EPOCH_TIMESTAMP;


    constructor(uint256 initialEpochTimestamp) {
        require(initialEpochTimestamp <= block.timestamp, "PWNEpochClock: initial epoch timestamp is in the future");
        INITIAL_EPOCH_TIMESTAMP = initialEpochTimestamp;
    }


    /*----------------------------------------------------------*|
    |*  # CLOCK                                                 *|
    |*----------------------------------------------------------*/

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

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
        if (timestamp < INITIAL_EPOCH_TIMESTAMP) return 0;
        return (timestamp - INITIAL_EPOCH_TIMESTAMP) / EPOCH_IN_SECONDS + 1;
    }

}
