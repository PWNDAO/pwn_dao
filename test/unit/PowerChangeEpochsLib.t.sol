// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { PowerChangeEpochsLib } from "src/lib/PowerChangeEpochsLib.sol";

import { Base_Test } from "../Base.t.sol";

abstract contract PowerChangeEpochsLib_Test is Base_Test {

    uint16[] public powerChangeEpochs;

    // helper function to make sorted increasing array with no duplicates
    function _setupPowerChangeEpochs(uint256 seed, uint256 minLength) internal {
        uint256 maxLength = 100;
        seed = bound(seed, 0, type(uint256).max - maxLength);
        uint256 length = bound(seed, minLength, maxLength);

        for (uint256 i; i < length; i++) {
            uint16 value = uint16(bound(uint256(keccak256(abi.encode(seed + i))), 1, 10));
            powerChangeEpochs.push(value);
            if (i > 0) {
                // cannot override because max length is 100 and max value is 10
                // => max epoch is 1000 < type(uint16).max (65535)
                powerChangeEpochs[i] += powerChangeEpochs[i - 1];
            }
        }
    }

    function _setupPowerChangeEpochs(uint256 seed) internal {
        _setupPowerChangeEpochs(seed, 1);
    }
}


/*----------------------------------------------------------*|
|*  # FIND INDEX                                            *|
|*----------------------------------------------------------*/

contract PowerChangeEpochsLib_FindIndex_Test is PowerChangeEpochsLib_Test {
    using PowerChangeEpochsLib for uint16[];

    function test_shouldReturnZero_whenEmpty() external {
        uint256 index = powerChangeEpochs.findIndex({ epoch: 1, low: 0 });

        assertEq(index, 0);
    }

    function testFuzz_shouldFindIndex_whenValueIsPresent(uint256 seed, uint256 indexToFind) external {
        _setupPowerChangeEpochs(seed);
        indexToFind = bound(indexToFind, 0, powerChangeEpochs.length - 1);
        uint16 epochToFind = powerChangeEpochs[indexToFind];

        uint256 index = powerChangeEpochs.findIndex({ epoch: epochToFind, low: 0 });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindIndex_whenValueIsBetween(
        uint256 seed, uint256 indexToFind, uint256 epochToFind
    ) external {
        _setupPowerChangeEpochs(seed, 2);
        indexToFind = bound(indexToFind, 1, powerChangeEpochs.length - 1);
        epochToFind = bound( // (i-1;i>
            epochToFind,
            powerChangeEpochs[indexToFind - 1] + 1,
            powerChangeEpochs[indexToFind]
        );

        uint256 index = powerChangeEpochs.findIndex({ epoch: uint16(epochToFind), low: 0 });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindIndex_whenValueIsSmallerThanFirstElement(uint256 seed) external {
        _setupPowerChangeEpochs(seed);
        uint256 indexToFind = 0;
        uint16 epochToFind = powerChangeEpochs[indexToFind];
        vm.assume(epochToFind > 0);
        --epochToFind;

        uint256 index = powerChangeEpochs.findIndex({ epoch: epochToFind, low: 0 });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindIndex_whenValueIsBiggerThanLastElement(uint256 seed) external {
        _setupPowerChangeEpochs(seed);
        uint256 indexToFind = powerChangeEpochs.length;
        uint16 epochToFind = powerChangeEpochs[indexToFind - 1] + 1;

        uint256 index = powerChangeEpochs.findIndex({ epoch: epochToFind, low: 0 });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldNotFindIndex_whenValueUnderProvidedLow(
        uint256 seed, uint256 indexToFind, uint256 low
    ) external {
        _setupPowerChangeEpochs(seed);
        low = bound(low, 1, powerChangeEpochs.length);
        indexToFind = bound(indexToFind, 0, low - 1);
        uint16 epochToFind = powerChangeEpochs[indexToFind];

        uint256 index = powerChangeEpochs.findIndex({ epoch: epochToFind, low: low });

        assertEq(index, low);
    }

}


/*----------------------------------------------------------*|
|*  # FIND NEAREST INDEX                                    *|
|*----------------------------------------------------------*/

contract PowerChangeEpochsLib_FindNearestIndex_Test is PowerChangeEpochsLib_Test {
    using PowerChangeEpochsLib for uint16[];

    function test_shouldReturnZero_whenEmpty() external {
        uint256 index = powerChangeEpochs.findNearestIndex({ epoch: 1, low: 0, high: 0 });

        assertEq(index, 0);
    }

    function testFuzz_shouldFindNearestIndex_whenValueIsPresent(uint256 seed, uint256 indexToFind) external {
        _setupPowerChangeEpochs(seed);
        indexToFind = bound(indexToFind, 0, powerChangeEpochs.length - 1);
        uint16 epochToFind = powerChangeEpochs[indexToFind];

        uint256 index = powerChangeEpochs.findNearestIndex({
            epoch: epochToFind, low: 0, high: powerChangeEpochs.length
        });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindNearestIndex_whenValueIsBetween(
        uint256 seed, uint256 indexToFind, uint256 epochToFind
    ) external {
        _setupPowerChangeEpochs(seed, 2);
        indexToFind = bound(indexToFind, 0, powerChangeEpochs.length - 2);
        epochToFind = bound( // <i;i+1)
            epochToFind,
            powerChangeEpochs[indexToFind],
            powerChangeEpochs[indexToFind + 1] - 1
        );

        uint256 index = powerChangeEpochs.findNearestIndex({
            epoch: uint16(epochToFind), low: 0, high: powerChangeEpochs.length
        });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindNearestIndex_whenValueIsSmallerThanFirstElement(uint256 seed) external {
        _setupPowerChangeEpochs(seed);
        uint256 indexToFind = 0;
        uint16 epochToFind = powerChangeEpochs[indexToFind];
        vm.assume(epochToFind > 0);
        --epochToFind;

        uint256 index = powerChangeEpochs.findNearestIndex({
            epoch: epochToFind, low: 0, high: powerChangeEpochs.length
        });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldFindNearestIndex_whenValueIsBiggerThanLastElement(uint256 seed) external {
        _setupPowerChangeEpochs(seed);
        uint256 indexToFind = powerChangeEpochs.length - 1;
        uint16 epochToFind = powerChangeEpochs[indexToFind] + 1;

        uint256 index = powerChangeEpochs.findNearestIndex({
            epoch: epochToFind, low: 0, high: powerChangeEpochs.length
        });

        assertEq(index, indexToFind);
    }

    function testFuzz_shouldNotFindNearestIndex_whenValueUnderProvidedLow(
        uint256 seed, uint256 indexToFind, uint256 low
    ) external {
        _setupPowerChangeEpochs(seed, 2);
        low = bound(low, 1, powerChangeEpochs.length - 1);
        indexToFind = bound(indexToFind, 0, low - 1);
        uint16 epochToFind = powerChangeEpochs[indexToFind];

        uint256 index = powerChangeEpochs.findNearestIndex({
            epoch: epochToFind, low: low, high: powerChangeEpochs.length
        });

        assertEq(index, low);
    }

    function testFuzz_shouldNotFindNearestIndex_whenValueAboveProvidedHigh(
        uint256 seed, uint256 indexToFind, uint256 high
    ) external {
        _setupPowerChangeEpochs(seed, 2);
        high = bound(high, 1, powerChangeEpochs.length - 1);
        indexToFind = bound(indexToFind, high, powerChangeEpochs.length - 1);
        uint16 epochToFind = powerChangeEpochs[indexToFind];

        uint256 index = powerChangeEpochs.findNearestIndex({ epoch: epochToFind, low: 0, high: high });

        assertEq(index, high - 1);
    }

}


/*----------------------------------------------------------*|
|*  # INSERT EPOCH                                          *|
|*----------------------------------------------------------*/

contract PowerChangeEpochsLib_InsertEpoch_Test is PowerChangeEpochsLib_Test {
    using PowerChangeEpochsLib for uint16[];

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

}


/*----------------------------------------------------------*|
|*  # REMOVE EPOCH                                          *|
|*----------------------------------------------------------*/

contract PowerChangeEpochsLib_RemoveEpoch_Test is PowerChangeEpochsLib_Test {
    using PowerChangeEpochsLib for uint16[];

    function testFuzz_shouldRemoveEpochFromIndex(uint16[] memory originalArray, uint256 index) external {
        vm.assume(originalArray.length > 0);
        index = bound(index, 0, originalArray.length - 1);
        powerChangeEpochs = originalArray;

        powerChangeEpochs.removeEpoch(index);

        assertEq(powerChangeEpochs.length, originalArray.length - 1);
        for (uint256 i; i < powerChangeEpochs.length; ++i)
            assertEq(powerChangeEpochs[i], originalArray[i + (i >= index ? 1 : 0)]);
    }

}
