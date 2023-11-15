// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { BitMaskLib } from "../utils/BitMaskLib.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

abstract contract VoteEscrowedPWN_Power_Test is VoteEscrowedPWN_Test {
    using SlotComputingLib for bytes32;

    function setUp() override virtual public {
        super.setUp();

        vePWN.workaround_setMockStakerPower(false);
        vePWN.workaround_setMockTotalPowerAt(false);
    }

    // solhint-disable-next-line var-name-mixedcase
    TestPowerChangeEpoch[] public helper_powerChanges;
    // helper function to make sorted increasing array with no duplicates
    function _createPowerChangeEpochs(
        uint256 seed, uint256 minLength
    ) internal returns (TestPowerChangeEpoch[] memory epochs) {
        uint256 maxLength = 100;
        seed = bound(seed, 1, type(uint256).max / 2);
        uint256 length = bound(seed, minLength, maxLength);

        for (uint256 i; i < length; ++i) {
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            uint256 epoch = bound(iSeed, 1, 10);
            uint256 power = bound(iSeed, 1, uint104(type(int104).max) / maxLength);
            helper_powerChanges.push(TestPowerChangeEpoch(uint16(epoch), int104(int256(power))));
            if (i > 0) {
                // cannot override because max length is 100 and max value is 10
                // => max epoch is 1000 < type(uint16).max (65535)
                helper_powerChanges[i].epoch += helper_powerChanges[i - 1].epoch;
            }
        }

        epochs = helper_powerChanges;
        delete helper_powerChanges;
    }

    function _createPowerChangeEpochs(uint256 seed) internal returns (TestPowerChangeEpoch[] memory epochs) {
        return _createPowerChangeEpochs(seed, 1);
    }

    int104[] public totalPowerChanges;
    function _createTotalPowerChangeEpochs(uint256 seed, uint256 minLength) internal returns (int104[] memory epochs) {
        uint256 maxLength = 100;
        seed = bound(seed, 1, type(uint256).max / 2);
        uint256 length = bound(seed, minLength, maxLength);

        for (uint256 i; i < length; ++i) {
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            uint256 power = bound(iSeed, 1, uint104(type(int104).max) / maxLength);
            totalPowerChanges.push(int104(int256(power)));
        }

        epochs = totalPowerChanges;
        delete totalPowerChanges;
    }

    function _mockLastCalculatedStakerEpoch(address _staker, uint256 epoch, uint256 index) internal {
        bytes memory rawLastCalculatedEpochData = abi.encodePacked(uint224(0), uint16(index), uint16(epoch));
        vm.store(
            address(vePWN),
            LAST_CALCULATED_STAKER_POWER_EPOCH_SLOT.withMappingKey(_staker),
            abi.decode(rawLastCalculatedEpochData, (bytes32))
        );
    }

    function _mockLastCalculatedTotalPowerEpoch(uint256 epoch) internal {
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));
    }

}


/*----------------------------------------------------------*|
|*  # STAKER POWER                                          *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_StakerPower_Test is VoteEscrowedPWN_Power_Test {
    using SlotComputingLib for bytes32;

    function test_shouldReturnZero_whenEpochIsZero() external {
        uint256 power = vePWN.stakerPower(staker, 0);

        assertEq(power, 0);
    }

    function test_shouldReturnZero_whenNoPowerChanges() external {
        uint256 power = vePWN.stakerPower(staker, currentEpoch);

        assertEq(power, 0);
    }

    function testFuzz_shouldReturnZero_whenEpochIsBeforeFirstPowerChange(uint256 seed, uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed);
        vm.assume(powerChanges[0].epoch > 0);
        _storePowerChanges(staker, powerChanges);
        uint256 epochToFind = bound(epoch, 0, powerChanges[0].epoch - 1);

        uint256 power = vePWN.stakerPower(staker, epochToFind);

        assertEq(power, 0);
    }

    function testFuzz_shouldFail_whenEpochTooBig(uint256 seed, uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed);
        _storePowerChanges(staker, powerChanges);
        uint256 epochToFind = bound(epoch, uint256(type(uint16).max) + 1, type(uint256).max);

        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        vePWN.stakerPower(staker, epochToFind);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnStoredPower_whenEpochIsCalculated_whenEpochIsEqulLastCalculatedEpoch(
        uint256 seed, uint256 lcIndex
    ) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed);
        _storePowerChanges(staker, powerChanges);
        uint256 lastCalculatedEpochIndex = bound(lcIndex, 0, powerChanges.length - 1);
        uint256 lastCalculatedEpoch = powerChanges[lastCalculatedEpochIndex].epoch;
        _mockLastCalculatedStakerEpoch(staker, lastCalculatedEpoch, lastCalculatedEpochIndex);

        uint256 power = vePWN.stakerPower(staker, lastCalculatedEpoch);

        assertEq(power, uint256(uint104(powerChanges[lastCalculatedEpochIndex].powerChange)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnStoredPower_whenEpochIsCalculated_whenEpochIsLessThanLastCalculatedEpoch(
        uint256 seed, uint256 lcIndex, uint256 index, uint256 epoch
    ) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        uint256 lastCalculatedEpochIndex = bound(lcIndex, 1, powerChanges.length - 1);
        uint256 lastCalculatedEpoch = powerChanges[lastCalculatedEpochIndex].epoch;
        _mockLastCalculatedStakerEpoch(staker, lastCalculatedEpoch, lastCalculatedEpochIndex);
        uint256 indexToFind = bound(index, 0, lastCalculatedEpochIndex - 1);
        uint256 epochToFind = bound(
            epoch,
            powerChanges[indexToFind].epoch,
            indexToFind == powerChanges.length - 1 ? type(uint16).max : powerChanges[indexToFind + 1].epoch - 1
        );
        assertLt(indexToFind, lastCalculatedEpochIndex);
        assertLt(epochToFind, lastCalculatedEpoch);

        uint256 power = vePWN.stakerPower(staker, epochToFind);

        assertEq(power, uint256(uint104(powerChanges[indexToFind].powerChange)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnComputedPower_whenEpochIsNotCalculated(
        uint256 seed, uint256 lcIndex, uint256 index, uint256 epoch
    ) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        uint256 lastCalculatedEpochIndex = bound(lcIndex, 0, powerChanges.length - 2);
        uint256 lastCalculatedEpoch = powerChanges[lastCalculatedEpochIndex].epoch;
        _mockLastCalculatedStakerEpoch(staker, lastCalculatedEpoch, lastCalculatedEpochIndex);
        uint256 indexToFind = bound(index, lastCalculatedEpochIndex + 1, powerChanges.length - 1);
        uint256 epochToFind = bound(
            epoch,
            powerChanges[indexToFind].epoch,
            indexToFind == powerChanges.length - 1 ? type(uint16).max : powerChanges[indexToFind + 1].epoch - 1
        );
        assertGt(indexToFind, lastCalculatedEpochIndex);
        assertGt(epochToFind, lastCalculatedEpoch);

        uint256 power = vePWN.stakerPower(staker, epochToFind);

        int104 expectedPower;
        for (uint256 i = lastCalculatedEpochIndex; i <= indexToFind; ++i)
            expectedPower += powerChanges[i].powerChange;
        assertEq(power, uint256(uint104(expectedPower)));
    }

}


/*----------------------------------------------------------*|
|*  # CALCULATE POWER                                       *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_CalculatePower_Test is VoteEscrowedPWN_Power_Test {
    using BitMaskLib for bytes32;
    using SlotComputingLib for bytes32;

    event StakerPowerCalculated(address indexed staker, uint256 indexed epoch);

    function test_shouldFail_whenNoPowerChanges() external {
        vm.expectRevert("vePWN: staker has no power changes");
        vePWN.calculateStakerPowerUpTo(staker, 1);
    }

    function testFuzz_shouldFail_whenEpochDoesNotEnded(uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(1);
        _storePowerChanges(staker, powerChanges);
        epoch = bound(epoch, currentEpoch, type(uint256).max);

        vm.expectRevert("vePWN: epoch hasn't ended yet");
        vePWN.calculateStakerPowerUpTo(staker, epoch);
    }

    function testFuzz_shouldFail_whenStakerPowerAlreadyCalculated(
        uint256 seed, uint256 lcIndex, uint256 epoch
    ) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        uint256 lastCalculatedEpochIndex = bound(lcIndex, 1, powerChanges.length - 1);
        uint256 lastCalculatedEpoch = powerChanges[lastCalculatedEpochIndex].epoch;
        _mockLastCalculatedStakerEpoch(staker, lastCalculatedEpoch, lastCalculatedEpochIndex);
        epoch = bound(epoch, 1, lastCalculatedEpoch);
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(lastCalculatedEpoch + 1)
        );

        vm.expectRevert("vePWN: staker power already calculated");
        vePWN.calculateStakerPowerUpTo(staker, epoch);
    }

    function testFuzz_shouldCalculateStakingPowers_whenFirstTime(uint256 seed, uint256 index, uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        index = bound(index, 1, powerChanges.length - 1);
        epoch = bound(
            epoch,
            powerChanges[index].epoch,
            index == powerChanges.length - 1 ? powerChanges[index].epoch : powerChanges[index + 1].epoch - 1
        );
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(epoch + 1)
        );

        vePWN.calculateStakerPowerUpTo(staker, epoch);

        int104 power;
        for (uint256 i; i <= index; ++i) {
            power += powerChanges[i].powerChange;
            assertEq(power, vePWN.workaround_getStakerEpochPower(staker, powerChanges[i].epoch));
        }
    }

    function testFuzz_shouldCalculateStakingPowers_whenHasBeenCalculatedBefore(
        uint256 seed, uint256 index, uint256 epoch, uint256 lcIndex
    ) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        index = bound(index, 1, powerChanges.length - 1);
        epoch = bound(
            epoch,
            powerChanges[index].epoch,
            index == powerChanges.length - 1 ? powerChanges[index].epoch : powerChanges[index + 1].epoch - 1
        );
        uint256 lastCalculatedEpochIndex = bound(lcIndex, 0, index - 1);
        uint256 lastCalculatedEpoch = powerChanges[lastCalculatedEpochIndex].epoch;
        _mockLastCalculatedStakerEpoch(staker, lastCalculatedEpoch, lastCalculatedEpochIndex);
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(epoch + 1)
        );

        vePWN.calculateStakerPowerUpTo(staker, epoch);

        int104 power;
        for (uint256 i = lastCalculatedEpochIndex; i <= index; ++i) {
            power += powerChanges[i].powerChange;
            assertEq(power, vePWN.workaround_getStakerEpochPower(staker, powerChanges[i].epoch));
        }
    }

    function testFuzz_shouldStoreNewLastCalculatedStakingPower(uint256 seed, uint256 index, uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        index = bound(index, 1, powerChanges.length - 1);
        epoch = bound(
            epoch,
            powerChanges[index].epoch,
            index == powerChanges.length - 1 ? powerChanges[index].epoch : powerChanges[index + 1].epoch - 1
        );
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(epoch + 1)
        );

        vePWN.calculateStakerPowerUpTo(staker, epoch);

        bytes32 lastCalculatedEpochValue = vm.load(
            address(vePWN), LAST_CALCULATED_STAKER_POWER_EPOCH_SLOT.withMappingKey(staker)
        );
        assertEq(lastCalculatedEpochValue.maskUint16(0), powerChanges[index].epoch);
        assertEq(lastCalculatedEpochValue.maskUint16(16), uint16(index));
        assertEq(vePWN.lastCalculatedStakerEpoch(staker), uint256(powerChanges[index].epoch));
    }

    function testFuzz_shouldEmit_StakerPowerCalculated(uint256 seed, uint256 index, uint256 epoch) external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangeEpochs(seed, 2);
        _storePowerChanges(staker, powerChanges);
        index = bound(index, 1, powerChanges.length - 1);
        epoch = bound(
            epoch,
            powerChanges[index].epoch,
            index == powerChanges.length - 1 ? powerChanges[index].epoch : powerChanges[index + 1].epoch - 1
        );
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(epoch + 1)
        );

        vm.expectEmit();
        emit StakerPowerCalculated(staker, powerChanges[index].epoch);

        vePWN.calculateStakerPowerUpTo(staker, epoch);
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL POWER                                           *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_TotalPowerAt_Test is VoteEscrowedPWN_Power_Test {

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnStoredPower_whenEpochIsCalculated(
        uint256 seed, uint256 lcEpoch, uint256 epoch
    ) external {
        // mock total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        for (uint256 i; i < totalPowerChanges.length; ++i)
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        // mock last calculated epoch
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 1);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        // pick epoch
        epoch = bound(epoch, 0, lastCalculatedEpoch);
        assertLe(epoch, lastCalculatedEpoch);

        uint256 totalPower = vePWN.totalPowerAt(epoch);

        assertEq(totalPower, uint256(uint104(totalPowerChanges[epoch])));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnComputedPower_whenEpochIsNotYetCalculated(
        uint256 seed, uint256 lcEpoch, uint256 epoch
    ) external {
        // mock total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        for (uint256 i; i < totalPowerChanges.length; ++i)
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        // mock last calculated epoch
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 2);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        // pick epoch
        epoch = bound(epoch, lastCalculatedEpoch + 1, totalPowerChanges.length - 1);
        assertGt(epoch, lastCalculatedEpoch);

        uint256 totalPower = vePWN.totalPowerAt(epoch);

        int104 expectedPower;
        for (uint256 i = lastCalculatedEpoch; i <= epoch; ++i)
            expectedPower += totalPowerChanges[i];
        assertEq(totalPower, uint256(uint104(expectedPower)));
    }

}


/*----------------------------------------------------------*|
|*  # CALCULATE TOTAL POWER                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_CalculateTotalPower_Test is VoteEscrowedPWN_Power_Test {

    event TotalPowerCalculated(uint256 indexed epoch);

    function testFuzz_shouldFail_whenEpochDoesNotEnded(uint256 epoch) external {
        epoch = bound(epoch, currentEpoch, type(uint256).max);

        vm.expectRevert("vePWN: epoch hasn't ended yet");
        vePWN.calculateTotalPowerUpTo(epoch);
    }

    function testFuzz_shouldFail_whenTotalPowerAlreadyCalculated(uint256 epoch, uint256 lcEpoch) external {
        lcEpoch = bound(lcEpoch, 0, currentEpoch - 1);
        epoch = bound(epoch, 0, lcEpoch);
        _mockLastCalculatedTotalPowerEpoch(lcEpoch);

        vm.expectRevert("vePWN: total power already calculated");
        vePWN.calculateTotalPowerUpTo(epoch);
    }

    function testFuzz_shouldCalculateTotalPowers(uint256 seed, uint256 epoch, uint256 lcEpoch) external {
        // mock total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        for (uint256 i; i < totalPowerChanges.length; ++i)
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        // mock last calculated epoch
        lcEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 2);
        _mockLastCalculatedTotalPowerEpoch(lcEpoch);
        // pick epoch
        epoch = bound(epoch, lcEpoch + 1, totalPowerChanges.length - 1);

        vePWN.calculateTotalPowerUpTo(epoch);

        int104 totalPower;
        for (uint256 i = lcEpoch; i <= epoch; ++i) {
            totalPower += totalPowerChanges[i];
            assertEq(totalPower, vePWN.workaround_getTotalEpochPower(i));
        }
    }

    function testFuzz_shouldStoreNewLastCalculatedTotalPower(uint256 epoch, uint256 lcEpoch) external {
        lcEpoch = bound(lcEpoch, 0, currentEpoch - 2);
        epoch = bound(epoch, lcEpoch + 1, currentEpoch - 1);
        _mockLastCalculatedTotalPowerEpoch(lcEpoch);

        vePWN.calculateTotalPowerUpTo(epoch);

        bytes32 lastCalculatedEpochValue = vm.load(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT);
        assertEq(uint256(lastCalculatedEpochValue), epoch);
        assertEq(vePWN.lastCalculatedTotalPowerEpoch(), epoch);
    }

    function testFuzz_shouldEmit_TotalPowerCalculated(uint256 epoch, uint256 lcEpoch) external {
        lcEpoch = bound(lcEpoch, 0, currentEpoch - 2);
        epoch = bound(epoch, lcEpoch + 1, currentEpoch - 1);
        _mockLastCalculatedTotalPowerEpoch(lcEpoch);

        vm.expectEmit();
        emit TotalPowerCalculated(epoch);

        vePWN.calculateTotalPowerUpTo(epoch);
    }

}
