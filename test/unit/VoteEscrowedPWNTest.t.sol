// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { VoteEscrowedPWNHarness } from "../harness/VoteEscrowedPWNHarness.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { Base_Test } from "../Base.t.sol";

abstract contract VoteEscrowedPWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    uint8 public constant EPOCHS_IN_YEAR = 13;
    bytes32 public constant STAKES_SLOT = bytes32(uint256(6));
    bytes32 public constant POWER_CHANGES_EPOCHS_SLOT = bytes32(uint256(7));
    bytes32 public constant LAST_CALCULATED_STAKER_POWER_EPOCH_INDEX_SLOT = bytes32(uint256(8));
    bytes32 public constant LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT = bytes32(uint256(9));

    VoteEscrowedPWNHarness public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public owner = makeAddr("owner");
    address public staker = makeAddr("staker");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch)
        );
        vm.mockCall(
            pwnToken, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true)
        );
        vm.mockCall(
            pwnToken, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true)
        );
        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)"), abi.encode(0)
        );
        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)"), abi.encode(0)
        );

        vePWN = new VoteEscrowedPWNHarness();
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock,
            _owner: owner
        });
    }


    struct TestPowerChangeEpoch {
        uint16 epoch;
        int104 powerChange;
    }

    function _createPowerChangesArray(
        uint256 _lockUpEpochs, uint256 _amount
    ) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(uint16(currentEpoch + 1), _lockUpEpochs, _amount);
    }

    function _createPowerChangesArray(
        uint16 _initialEpoch, uint256 _lockUpEpochs, uint256 _amount
    ) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(_initialEpoch, type(uint16).max, _lockUpEpochs, _amount);
    }

    // solhint-disable-next-line var-name-mixedcase
    TestPowerChangeEpoch[] private helper_powerChanges;
    function _createPowerChangesArray(
        uint16 _initialEpoch, uint16 _finalEpoch, uint256 _lockUpEpochs, uint256 _amount
    ) internal returns (TestPowerChangeEpoch[] memory) {
        if (_initialEpoch >= _finalEpoch)
            return new TestPowerChangeEpoch[](0);

        uint16 epoch = _initialEpoch;
        uint8 remainingLockup = uint8(_lockUpEpochs);
        int104 int104amount = int104(int256(_amount));
        int104 powerChange = vePWN.exposed_initialPower(int104amount, remainingLockup);

        helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        while (remainingLockup > 0) {
            uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(remainingLockup);
            remainingLockup -= epochsToNextPowerChange;
            epoch += epochsToNextPowerChange;
            if (epoch >= _finalEpoch) break;
            helper_powerChanges.push(
                TestPowerChangeEpoch({
                    epoch: epoch,
                    powerChange: vePWN.exposed_decreasePower(int104amount, remainingLockup)
                })
            );
        }
        TestPowerChangeEpoch[] memory array = helper_powerChanges;
        delete helper_powerChanges;
        return array;
    }

    function _mergePowerChanges(
        TestPowerChangeEpoch[] memory pchs1, TestPowerChangeEpoch[] memory pchs2
    ) internal returns (TestPowerChangeEpoch[] memory) {
        if (pchs1.length == 0)
            return pchs2;
        else if (pchs2.length == 0)
            return pchs1;

        uint256 i1;
        uint256 i2;
        bool stop1;
        bool stop2;
        while (true) {
            if (!stop1 && (pchs1[i1].epoch < pchs2[i2].epoch || stop2)) {
                helper_powerChanges.push(pchs1[i1]);
                if (i1 + 1 < pchs1.length) ++i1; else stop1 = true;
            } else if (!stop2 && (pchs1[i1].epoch > pchs2[i2].epoch || stop1)) {
                helper_powerChanges.push(pchs2[i2]);
                if (i2 + 1 < pchs2.length) ++i2; else stop2 = true;
            } else if (pchs1[i1].epoch == pchs2[i2].epoch && !stop1 && !stop2) {
                int104 powerSum = pchs1[i1].powerChange + pchs2[i2].powerChange;
                if (powerSum != 0) {
                    helper_powerChanges.push(TestPowerChangeEpoch({ epoch: pchs1[i1].epoch, powerChange: powerSum }));
                }
                if (i1 + 1 < pchs1.length) ++i1; else stop1 = true;
                if (i2 + 1 < pchs2.length) ++i2; else stop2 = true;
            }
            if (stop1 && stop2)
                break;
        }

        TestPowerChangeEpoch[] memory array = helper_powerChanges;
        delete helper_powerChanges;
        return array;
    }

    function _storeStake(uint256 _stakeId, uint16 _initialEpoch, uint8 _remainingLockup, uint104 _amount) internal {
        bytes memory rawStakeData = abi.encodePacked(uint128(0), _amount, _remainingLockup, _initialEpoch);
        vm.store(
            address(vePWN), STAKES_SLOT.withMappingKey(_stakeId), abi.decode(rawStakeData, (bytes32))
        );
    }

    // expects storage to be empty
    function _storePowerChanges(address _staker, TestPowerChangeEpoch[] memory powerChanges) internal {
        bytes32 powerChangesSlot = POWER_CHANGES_EPOCHS_SLOT.withMappingKey(_staker);
        vm.store(
            address(vePWN), powerChangesSlot, bytes32(powerChanges.length)
        );

        uint256 necessarySlots = powerChanges.length / 16;
        necessarySlots += powerChanges.length % 16 == 0 ? 0 : 1;
        for (uint256 i; i < necessarySlots; ++i) {
            bool lastLoop = i + 1 == necessarySlots;
            uint256 upperBound = lastLoop ? powerChanges.length % 16 : 16;
            upperBound = upperBound == 0 ? 16 : upperBound;
            bytes32 encodedPowerChanges;
            for (uint256 j; j < upperBound; ++j) {
                TestPowerChangeEpoch memory powerChange = powerChanges[i * 16 + j];
                encodedPowerChanges = encodedPowerChanges | bytes32(uint256(powerChange.epoch)) << (16 * j);

                vePWN.workaround_storeStakerEpochPower(_staker, powerChange.epoch, powerChange.powerChange);
                vePWN.workaround_storeTotalEpochPower(powerChange.epoch, powerChange.powerChange);
            }

            vm.store(
                address(vePWN), keccak256(abi.encode(powerChangesSlot)).withArrayIndex(i), encodedPowerChanges
            );
        }
    }

    function _mockStake(
        address _staker, uint256 _stakeId, uint16 _initialEpoch, uint8 _remainingLockup, uint104 _amount
    ) internal returns (TestPowerChangeEpoch[] memory) {
        vm.mockCall(
            address(stakedPWN),
            abi.encodeWithSignature("ownerOf(uint256)", _stakeId),
            abi.encode(_staker)
        );
        _storeStake(_stakeId, _initialEpoch, _remainingLockup, _amount);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_initialEpoch, _remainingLockup, _amount);
        _storePowerChanges(_staker, powerChanges);
        return powerChanges;
    }

    // bound

    function _boundAmount(uint256 seed) internal pure returns (uint256) {
        return bound(seed, 100, 1e26) / 100 * 100;
    }

    function _boundLockUpEpochs(uint256 seed) internal pure returns (uint8) {
        uint8 lockUpEpochs = uint8(bound(seed, EPOCHS_IN_YEAR, 10 * EPOCHS_IN_YEAR));
        return lockUpEpochs > 5 * EPOCHS_IN_YEAR ? 10 * EPOCHS_IN_YEAR : lockUpEpochs;
    }

    function _boundRemainingLockups(uint256 seed) internal pure returns (uint8) {
        return uint8(bound(seed, 1, 10 * EPOCHS_IN_YEAR));
    }

    // assert

    function _assertPowerChangesSumToZero(address _staker) internal {
        uint256 length = vePWN.workaround_stakerPowerChangeEpochsLength(_staker);
        int104 sum;
        for (uint256 i; i < length; ++i) {
            uint16 epoch = vePWN.powerChangeEpochs(_staker)[i];
            sum += vePWN.workaround_getStakerEpochPower(_staker, epoch);
        }
        assertEq(sum, 0);
    }

    function _assertTotalPowerChangesSumToZero(uint256 lastEpoch) internal {
        int104 sum;
        for (uint256 i; i <= lastEpoch; ++i) {
            sum += vePWN.workaround_getTotalEpochPower(i);
        }
        assertEq(sum, 0);
    }

    function _assertEpochPowerAndPosition(address _staker, uint256 _index, uint16 _epoch, int104 _power) internal {
        assertEq(vePWN.powerChangeEpochs(_staker)[_index], _epoch, "epoch mismatch");
        assertEq(vePWN.workaround_getStakerEpochPower(_staker, _epoch), _power, "power mismatch");
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Helpers_Test is VoteEscrowedPWN_Test {

    function testFuzzHelper_storeStake(
        uint256 _stakeId, uint16 _initialEpoch, uint8 _remainingLockup, uint104 _amount
    ) external {
        _storeStake(_stakeId, _initialEpoch, _remainingLockup, _amount);

        (uint16 initialEpoch, uint8 remainingLockup, uint104 amount) = vePWN.stakes(_stakeId);
        assertEq(_initialEpoch, initialEpoch);
        assertEq(_remainingLockup, remainingLockup);
        assertEq(_amount, amount);
    }

    function testFuzzHelper_storePowerChanges(address _staker, uint88 _amount, uint8 _lockUpEpochs) external {
        _amount = uint88(bound(_amount, 1, type(uint88).max));
        _lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_lockUpEpochs, _amount);
        _storePowerChanges(_staker, powerChanges);

        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(_staker)[i]);
            assertEq(powerChanges[i].powerChange, vePWN.workaround_getStakerEpochPower(_staker, powerChanges[i].epoch));
        }
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED FUNCTIONS                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Exposed_Test is VoteEscrowedPWN_Test {
    using SlotComputingLib for bytes32;

    // epochsToNextPowerChange

    function testFuzz_epochsToNextPowerChange_whenLessThanFiveYears_whenDivisibleByYear(
        uint8 originalRemainingLockup
    ) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, 1, 5) * EPOCHS_IN_YEAR);

        uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(originalRemainingLockup);

        assertEq(epochsToNextPowerChange, EPOCHS_IN_YEAR);
    }

    function testFuzz_epochsToNextPowerChange_whenLessThanFiveYears_whenNotDivisibleByYear(
        uint8 originalRemainingLockup
    ) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, EPOCHS_IN_YEAR + 1, 5 * EPOCHS_IN_YEAR - 1));
        vm.assume(originalRemainingLockup % EPOCHS_IN_YEAR > 0);

        uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(originalRemainingLockup);

        assertEq(epochsToNextPowerChange, uint16(originalRemainingLockup % EPOCHS_IN_YEAR));
    }

    function testFuzz_epochsToNextPowerChange_whenMoreThanFiveYears(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(
            originalRemainingLockup, 5 * EPOCHS_IN_YEAR + 1, 10 * EPOCHS_IN_YEAR
        ));

        uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(originalRemainingLockup);

        assertEq(epochsToNextPowerChange, uint16(originalRemainingLockup - 5 * EPOCHS_IN_YEAR));
    }

    // updateEpochPowerChange

    function testFuzz_updateEpochPowerChange_shouldUpdatePowerChangeValue(
        address staker, uint16 epoch, int104 power
    ) external {
        power = int104(bound(power, 2, type(int104).max));
        int104 powerFraction = int104(bound(power, 1, power - 1));

        vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, powerFraction);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), powerFraction);

        vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, power - powerFraction);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), power);

        vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, -power);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), 0);
    }

    function testFuzz_updatePowerChangeEpoch_shouldAddEpochToArray_whenPowerChangedFromZeroToNonZero(
        address staker, uint16 epoch, int104 power
    ) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker)[index], epoch);
    }

    function test_updatePowerChangeEpoch_shouldKeepArraySorted() external {
        address staker = makeAddr("staker");
        uint16[] memory epochs = new uint16[](5);
        epochs[0] = 3;
        epochs[1] = 2;
        epochs[2] = 3;
        epochs[3] = 5;
        epochs[4] = 0;

        uint256[] memory indices = new uint256[](5);
        indices[0] = 0;
        indices[1] = 0;
        indices[2] = 1;
        indices[3] = 2;
        indices[4] = 0;

        for (uint256 i; i < epochs.length; ++i)
            assertEq(vePWN.exposed_updateEpochPowerChange(staker, epochs[i], 0, 100e10), indices[i]);

        uint16[] memory stakerPowerChangeEpochs = vePWN.powerChangeEpochs(staker);
        assertEq(stakerPowerChangeEpochs.length, 4);
        assertEq(stakerPowerChangeEpochs[0], 0);
        assertEq(stakerPowerChangeEpochs[1], 2);
        assertEq(stakerPowerChangeEpochs[2], 3);
        assertEq(stakerPowerChangeEpochs[3], 5);
    }

    function testFuzz_updatePowerChangeEpoch_shouldKeepEpochInArray_whenPowerChangedFromNonZeroToNonZero(
        address staker, uint16 epoch, int104 power
    ) external {
        power = int104(bound(power, 1, type(int104).max - 1));

        uint256 index = vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker)[index], epoch);
        assertEq(vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, 1), index);
    }

    function testFuzz_updatePowerChangeEpoch_shouldRemoveEpochFromArray_whenPowerChangedFromNonZeroToZero(
        address staker, uint16 epoch, int104 power
    ) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, power);

        uint16[] memory stakerPowerChangeEpochs = vePWN.powerChangeEpochs(staker);
        assertEq(stakerPowerChangeEpochs.length, 1);
        assertEq(stakerPowerChangeEpochs[index], epoch);

        index = vePWN.exposed_updateEpochPowerChange(staker, epoch, 0, -power);

        stakerPowerChangeEpochs = vePWN.powerChangeEpochs(staker);
        assertEq(stakerPowerChangeEpochs.length, 0);
    }

    // powerChangeMultipliers

    function testFuzz_powerChangeMultipliers_initialPower(
        uint256 amount, uint8 remainingLockup
    ) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory yearMultiplier = new int104[](6);
        yearMultiplier[0] = 100;
        yearMultiplier[1] = 115;
        yearMultiplier[2] = 130;
        yearMultiplier[3] = 150;
        yearMultiplier[4] = 175;
        yearMultiplier[5] = 350;

        int104 power = vePWN.exposed_initialPower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_YEAR * 5)
            multiplier = yearMultiplier[5];
        else
            multiplier = yearMultiplier[
                remainingLockup / EPOCHS_IN_YEAR - (remainingLockup % EPOCHS_IN_YEAR == 0 ? 1 : 0)
            ];
        assertEq(power, int104(uint104(amount)) * multiplier / 100);
    }

    function testFuzz_powerChangeMultipliers_decreasePower(uint256 amount, uint8 remainingLockup) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory yearMultiplier = new int104[](6);
        yearMultiplier[0] = 15;
        yearMultiplier[1] = 15;
        yearMultiplier[2] = 20;
        yearMultiplier[3] = 25;
        yearMultiplier[4] = 175;
        yearMultiplier[5] = 0;

        int104 power = vePWN.exposed_decreasePower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_YEAR * 5)
            multiplier = yearMultiplier[5];
        else if (remainingLockup == 0)
            multiplier = 100;
        else
            multiplier = yearMultiplier[
                remainingLockup / EPOCHS_IN_YEAR - (remainingLockup % EPOCHS_IN_YEAR == 0 ? 1 : 0)
            ];
        assertEq(power, -int104(uint104(amount)) * multiplier / 100);
    }

    function test_powerChangeMultipliers_powerChangesShouldSumToZero(uint8 remainingLockup) external {
        vm.assume(remainingLockup > 0);

        int104 amount = 100;
        int104 sum = vePWN.exposed_initialPower(amount, remainingLockup);
        while (remainingLockup > 0) {
            uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(remainingLockup);
            remainingLockup -= epochsToNextPowerChange;
            sum += vePWN.exposed_decreasePower(amount, remainingLockup);
        }

        assertEq(sum, 0);
    }

}
