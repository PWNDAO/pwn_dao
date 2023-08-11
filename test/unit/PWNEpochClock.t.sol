// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {PWNEpochClock} from "../../src/PWNEpochClock.sol";


abstract contract PWNEpochClockTest is Test {

    PWNEpochClock public clock;
    uint256 public initialTimestamp;

    function setUp() external {
        initialTimestamp = block.timestamp;
        clock = new PWNEpochClock(initialTimestamp);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Constructor_Test is PWNEpochClockTest {

    function testFuzz_shouldSetInitialEpoch(uint256 initialEpochTimestamp) external {
        clock = new PWNEpochClock(initialEpochTimestamp);

        assertEq(clock.INITIAL_EPOCH_TIMESTAMP(), initialEpochTimestamp);
    }

}


/*----------------------------------------------------------*|
|*  # CLOCK                                                 *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Clock_Test is PWNEpochClockTest {

    function testFuzz_clock_shouldReturnBlockTimestamp(uint256 timestamp) external {
        timestamp = bound(timestamp, 0, type(uint48).max);

        vm.warp(timestamp);
        assertEq(clock.clock(), timestamp);
    }

    function test_clockMode_shouldReturnModeTimestamp() external {
        assertEq(clock.CLOCK_MODE(), "mode=timestamp");
    }

}


/*----------------------------------------------------------*|
|*  # EPOCH                                                 *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Epoch_Test is PWNEpochClockTest {

    function testFuzz_currentEpoch_shouldReturnCorrectEpoch(uint256 timestamp) external {
        timestamp = bound(timestamp, initialTimestamp, type(uint256).max);

        vm.warp(timestamp);

        uint256 epoch = (timestamp - initialTimestamp) / clock.SECONDS_IN_EPOCH();
        assertEq(clock.currentEpoch(), epoch);
    }

    function testFuzz_epochFor_shouldReturnCorrectEpoch_whenTimestampAfterInitialTimestamp(uint256 timestamp) external {
        timestamp = bound(timestamp, initialTimestamp, type(uint256).max);
        uint256 epoch = (timestamp - initialTimestamp) / clock.SECONDS_IN_EPOCH();
        assertEq(clock.epochFor(timestamp), epoch);
    }

    function testFuzz_epochFor_shouldReturnEpochZero_whenTimestampBeforeInitialTimestamp(uint256 timestamp) external {
        timestamp = bound(timestamp, 0, initialTimestamp);
        assertEq(clock.epochFor(timestamp), 0);
    }

}
