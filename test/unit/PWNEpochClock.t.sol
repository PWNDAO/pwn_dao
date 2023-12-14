// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "src/lib/Error.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

import { Base_Test } from "../Base.t.sol";

abstract contract PWNEpochClock_Test is Base_Test {

    PWNEpochClock public clock;
    uint256 public initialTimestamp;

    function setUp() external {
        initialTimestamp = 123456;
        vm.warp(initialTimestamp);
        clock = new PWNEpochClock(initialTimestamp);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTANTS                                             *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Constants_Test is PWNEpochClock_Test {

    function test_constants() external {
        assertEq(clock.SECONDS_IN_EPOCH(), 2_419_200);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Constructor_Test is PWNEpochClock_Test {

    function testFuzz_shouldFail_whenInitialEpochTimestampIsInTheFuture(
        uint256 initialEpochTimestamp, uint256 currentTimestamp
    ) external {
        currentTimestamp = bound(currentTimestamp, 0, type(uint256).max - 1);
        initialEpochTimestamp = bound(initialEpochTimestamp, currentTimestamp + 1, type(uint256).max);
        vm.warp(currentTimestamp);

        vm.expectRevert(abi.encodeWithSelector(Error.InitialEpochTimestampInFuture.selector, currentTimestamp));
        new PWNEpochClock(initialEpochTimestamp);
    }

    function testFuzz_shouldSetInitialEpoch(uint256 initialEpochTimestamp) external {
        vm.warp(initialEpochTimestamp);

        clock = new PWNEpochClock(initialEpochTimestamp);

        assertEq(clock.INITIAL_EPOCH_TIMESTAMP(), initialEpochTimestamp);
    }

}


/*----------------------------------------------------------*|
|*  # CLOCK                                                 *|
|*----------------------------------------------------------*/

contract PWNEpochClock_Clock_Test is PWNEpochClock_Test {

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

contract PWNEpochClock_Epoch_Test is PWNEpochClock_Test {

    function testFuzz_currentEpoch_shouldReturnCorrectEpoch(uint256 timestamp) external {
        timestamp = bound(timestamp, initialTimestamp, type(uint256).max);

        vm.warp(timestamp);

        uint256 epoch = (timestamp - initialTimestamp) / clock.SECONDS_IN_EPOCH() + 1;
        assertEq(clock.currentEpoch(), epoch);
    }

    function testFuzz_epochFor_shouldReturnCorrectEpoch_whenTimestampAfterInitialTimestamp(uint256 timestamp) external {
        timestamp = bound(timestamp, initialTimestamp, type(uint256).max);
        uint256 epoch = (timestamp - initialTimestamp) / clock.SECONDS_IN_EPOCH() + 1;
        assertTrue(epoch > 0);
        assertEq(clock.epochFor(timestamp), epoch);
    }

    function testFuzz_epochFor_shouldReturnEpochZero_whenTimestampBeforeInitialTimestamp(uint256 timestamp) external {
        timestamp = bound(timestamp, 0, initialTimestamp - 1);
        assertEq(clock.epochFor(timestamp), 0);
    }

}
