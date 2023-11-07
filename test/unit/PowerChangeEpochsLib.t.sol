// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { PowerChangeEpochsLib } from "../../src/libs/PowerChangeEpochsLib.sol";


/*----------------------------------------------------------*|
|*  # POWER CHANGE EPOCHS LIB                               *|
|*----------------------------------------------------------*/

contract PowerChangeEpochsLib_Test is Test {
    using PowerChangeEpochsLib for uint16[];

    uint16[] public powerChangeEpochs;

    // helper function to make sorted increasing array with no duplicates
    function _setupPowerChangeEpochs(uint256 seed) internal {
        uint256 maxLength = 1000;
        seed = bound(seed, 0, type(uint256).max - maxLength);
        uint256 length = bound(seed, 1, maxLength);

        for (uint256 i; i < length; i++) {
            uint16 value = uint16(bound(uint256(keccak256(abi.encode(seed + i))), 1, 10));
            powerChangeEpochs.push(value);
            if (i > 0) {
                // cannot override because max length is 1000 and max value is 10 => max epoch is 10000 < type(uint16).max
                powerChangeEpochs[i] += powerChangeEpochs[i - 1];
            }
        }
    }


    function testFuzz_shouldInsertEpochAtIndex(uint16[] memory originalArray, uint16 item, uint256 index) external {
        index = bound(index, 0, originalArray.length);
        powerChangeEpochs = originalArray;

        powerChangeEpochs.insertEpoch(item, index);

        assertEq(powerChangeEpochs.length, originalArray.length + 1);
        for (uint256 i; i < powerChangeEpochs.length; ++i) {
            if (i == index)
                assertEq(powerChangeEpochs[i], item);
            else
                assertEq(powerChangeEpochs[i], originalArray[i - (i > index ? 1 : 0)]);
        }
    }

    function testFuzz_shouldRemoveEpochAtIndex(uint16[] memory originalArray, uint256 index) external {
        vm.assume(originalArray.length > 0);
        index = bound(index, 0, originalArray.length - 1);
        powerChangeEpochs = originalArray;

        powerChangeEpochs.removeEpoch(index);

        assertEq(powerChangeEpochs.length, originalArray.length - 1);
        for (uint256 i; i < powerChangeEpochs.length; ++i)
            assertEq(powerChangeEpochs[i], originalArray[i + (i >= index ? 1 : 0)]);
    }

    function test_shouldFindPowerChangeEpochIndex_whenEmpty() external {
        uint256 index = powerChangeEpochs.findIndex(1, 0);

        assertEq(index, 0);
    }

    function testFuzz_shouldFindPowerChangeEpochIndex_whenNonEmpty(uint256 seed) external {
        // need to make sorted increasing array with no duplicates
        _setupPowerChangeEpochs(seed);
        uint256 indexToFind = bound(seed, 0, powerChangeEpochs.length - 1);

        uint256 index = powerChangeEpochs.findIndex(powerChangeEpochs[indexToFind], 0);

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldNotFindPowerChangeEpochIndex_whenValueUnderLow(uint256 seed) external {
        // need to make sorted increasing array with no duplicates
        _setupPowerChangeEpochs(seed);
        vm.assume(powerChangeEpochs.length > 10);
        uint256 indexToFind = 5;
        uint256 low = indexToFind + 1;

        uint256 index = powerChangeEpochs.findIndex(powerChangeEpochs[indexToFind], low);

        assertEq(index, low);
    }

}
