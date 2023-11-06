// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNEpochClock } from "../../src/PWNEpochClock.sol";
import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

import { BitMaskLib } from "../utils/BitMaskLib.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { BasePWNTest } from "../BasePWNTest.t.sol";


contract VoteEscrowedPWN_StakeExposed is VoteEscrowedPWN {

    function workaround_stakerPowerChangeEpochsLength(address staker) external view returns (uint256) {
        return powerChangeEpochs[staker].length;
    }

    function exposed_powerChangeFor(address staker, uint256 epoch) external pure returns (PowerChange memory pch) {
        return _powerChangeFor(staker, epoch);
    }

    function exposed_nextPowerChangeAndRemainingLockup(int104 amount, uint16 epoch, uint8 remainingLockup) external pure returns (int104, uint16, uint8) {
        return _nextPowerChangeAndRemainingLockup(amount, epoch, remainingLockup);
    }

    function exposed_updatePowerChangeEpoch(address staker, uint16 epoch, uint256 lowEpochIndex, int104 power) external returns (uint256 epochIndex) {
        return _unsafe_updatePowerChangeEpoch(staker, epoch, lowEpochIndex, power);
    }

    function exposed_initialEpochPower(int104 amount, uint8 epochs) external pure returns (int104) {
        return _initialEpochPower(amount, epochs);
    }

    function exposed_remainingEpochsDecreasePower(int104 amount, uint8 epoch) external pure returns (int104) {
        return _remainingEpochsDecreasePower(amount, epoch);
    }

}


abstract contract VoteEscrowedPWN_Stake_Test is BasePWNTest {
    using SlotComputingLib for bytes32;

    uint8 public constant EPOCHS_IN_PERIOD = 13;
    bytes32 public constant STAKERS_NAMESPACE = bytes32(uint256(keccak256("vePWN.stakers_namespace")) - 1);
    bytes32 public constant STAKES_SLOT = bytes32(uint256(7));
    bytes32 public constant POWER_CHANGES_EPOCHS_SLOT = bytes32(uint256(9));

    VoteEscrowedPWN_StakeExposed public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public feeCollector = makeAddr("feeCollector");
    address public owner = makeAddr("owner");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
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

        vePWN = new VoteEscrowedPWN_StakeExposed();
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock,
            _feeCollector: feeCollector,
            _owner: owner
        });
    }


    struct TestPowerChangeEpoch {
        uint16 epoch;
        int104 powerChange;
    }

    function _createPowerChangesArray(uint256 _amount, uint256 _lockUpEpochs) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(uint16(currentEpoch + 1), _amount, _lockUpEpochs);
    }

    function _createPowerChangesArray(uint16 _initialEpoch, uint256 _amount, uint256 _lockUpEpochs) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(_initialEpoch, type(uint16).max, _amount, _lockUpEpochs);
    }

    TestPowerChangeEpoch[] private helper_powerChanges;
    function _createPowerChangesArray(
        uint16 _initialEpoch, uint16 _finalEpoch, uint256 _amount, uint256 _lockUpEpochs
    ) internal returns (TestPowerChangeEpoch[] memory) {
        if (_initialEpoch >= _finalEpoch)
            return new TestPowerChangeEpoch[](0);

        uint16 epoch = _initialEpoch;
        uint8 remainingLockup = uint8(_lockUpEpochs);
        int104 int104amount = int104(int256(_amount));
        int104 powerChange = vePWN.exposed_initialEpochPower(int104amount, remainingLockup);

        helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        while (remainingLockup > 0) {
            (powerChange, epoch, remainingLockup) = vePWN.exposed_nextPowerChangeAndRemainingLockup(int104amount, epoch, remainingLockup);
            if (epoch >= _finalEpoch) break;
            helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        }
        TestPowerChangeEpoch[] memory array = helper_powerChanges;
        delete helper_powerChanges;
        return array;
    }

    function _mergePowerChanges(TestPowerChangeEpoch[] memory pchs1, TestPowerChangeEpoch[] memory pchs2) internal returns (TestPowerChangeEpoch[] memory) {
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

    function _storeStake(uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup) internal {
        bytes memory rawStakeData = abi.encodePacked(uint128(0), _remainingLockup, _amount, _initialEpoch);
        vm.store(
            address(vePWN), STAKES_SLOT.withMappingKey(_stakeId), abi.decode(rawStakeData, (bytes32))
        );
    }

    // expects storage to be empty
    function _storePowerChanges(address staker, TestPowerChangeEpoch[] memory powerChanges) internal {
        bytes32 powerChangesSlot = bytes32(uint256(9)).withMappingKey(staker);
        vm.store(
            address(vePWN), powerChangesSlot, bytes32(powerChanges.length)
        );

        uint256 necessarySlots = powerChanges.length / 16;
        necessarySlots = powerChanges.length % 16 == 0 ? necessarySlots : necessarySlots + 1;
        for (uint256 i; i < necessarySlots; ++i) {
            bool lastLoop = i + 1 == necessarySlots;
            uint256 upperBound = lastLoop ? powerChanges.length % 16 : 16;
            bytes32 encodedPowerChanges;
            for (uint256 j; j < upperBound; ++j) {
                TestPowerChangeEpoch memory powerChange = powerChanges[i * 16 + j];
                encodedPowerChanges = encodedPowerChanges | bytes32(uint256(powerChange.epoch)) << (16 * j);

                vm.store(
                    address(vePWN),
                    STAKERS_NAMESPACE.withMappingKey(staker).withArrayIndex(powerChange.epoch),
                    bytes32(uint256(uint104(powerChange.powerChange)))
                );
            }

            vm.store(
                address(vePWN),
                keccak256(abi.encode(powerChangesSlot)).withArrayIndex(i),
                encodedPowerChanges
            );
        }
    }

    function _mockStake(
        address _staker, uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup
    ) internal returns (TestPowerChangeEpoch[] memory) {
        vm.mockCall(
            address(stakedPWN),
            abi.encodeWithSignature("ownerOf(uint256)", _stakeId),
            abi.encode(_staker)
        );
        _storeStake(_stakeId, _initialEpoch, _amount, _remainingLockup);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_initialEpoch, _amount, _remainingLockup);
        _storePowerChanges(_staker, powerChanges);
        return powerChanges;
    }

    // bound

    function _boundAmount(uint256 seed) internal view returns (uint256) {
        return bound(seed, 100, 1e26) / 100 * 100;
    }

    function _boundLockUpEpochs(uint256 seed) internal view returns (uint8) {
        uint8 lockUpEpochs = uint8(bound(seed, EPOCHS_IN_PERIOD, 10 * EPOCHS_IN_PERIOD));
        return lockUpEpochs > 5 * EPOCHS_IN_PERIOD ? 10 * EPOCHS_IN_PERIOD : lockUpEpochs;
    }

    function _boundRemainingLockups(uint256 seed) internal view returns (uint8) {
        return uint8(bound(seed, 1, 10 * EPOCHS_IN_PERIOD));
    }

    // assert

    function _assertPowerChangesSumToZero(address _staker) internal {
        uint256 length = vePWN.workaround_stakerPowerChangeEpochsLength(_staker);
        int104 sum;
        for (uint256 i; i < length; ++i) {
            uint16 epoch = vePWN.powerChangeEpochs(_staker, i);
            sum += vePWN.exposed_powerChangeFor(_staker, epoch).power;
        }
        assertEq(sum, 0);
    }

    function _assertEpochPowerAndPosition(address _staker, uint256 _index, uint16 _epoch, int104 _power) internal {
        assertEq(vePWN.powerChangeEpochs(_staker, _index), _epoch, "epoch mismatch");
        bytes32 powerChangeValue = vm.load(
            address(vePWN), STAKERS_NAMESPACE.withMappingKey(_staker).withArrayIndex(_epoch)
        );
        assertEq(int104(uint104(uint256(powerChangeValue))), _power, "power mismatch");
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_Helpers_Test is VoteEscrowedPWN_Stake_Test {

    function testFuzzHelper_storeStake(uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup) external {
        _storeStake(_stakeId, _initialEpoch, _amount, _remainingLockup);

        (uint16 initialEpoch, uint104 amount, uint8 remainingLockup) = vePWN.stakes(_stakeId);
        assertEq(_initialEpoch, initialEpoch);
        assertEq(_amount, amount);
        assertEq(_remainingLockup, remainingLockup);
    }

    function testFuzzHelper_storePowerChanges(address _staker, uint88 _amount, uint8 _lockUpEpochs) external {
        _amount = uint88(bound(_amount, 1, type(uint88).max));
        _lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_amount, _lockUpEpochs);
        _storePowerChanges(_staker, powerChanges);

        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(_staker, i));
            assertEq(powerChanges[i].powerChange, vePWN.exposed_powerChangeFor(_staker, powerChanges[i].epoch).power);
        }
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED FUNCTIONS                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_Exposed_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;


    function testFuzz_nextPowerChangeAndRemainingLockup_whenLessThanFivePeriods_whenDivisibleByPeriod(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, 1, 5) * EPOCHS_IN_PERIOD);

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextPowerChangeAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        assertEq(epoch, originalEpoch + EPOCHS_IN_PERIOD);
        assertEq(remainingLockup, originalRemainingLockup - EPOCHS_IN_PERIOD);
    }

    function testFuzz_nextPowerChangeAndRemainingLockup_whenLessThanFivePeriods_whenNotDivisibleByPeriod(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, EPOCHS_IN_PERIOD + 1, 5 * EPOCHS_IN_PERIOD - 1));
        vm.assume(originalRemainingLockup % EPOCHS_IN_PERIOD > 0);

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextPowerChangeAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        uint16 diff = uint16(originalRemainingLockup % EPOCHS_IN_PERIOD);
        assertEq(epoch, originalEpoch + diff);
        assertEq(remainingLockup, originalRemainingLockup - diff);
    }

    function testFuzz_nextPowerChangeAndRemainingLockup_whenMoreThanFivePeriods(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, 5 * EPOCHS_IN_PERIOD + 1, 10 * EPOCHS_IN_PERIOD));

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextPowerChangeAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        uint16 diff = uint16(originalRemainingLockup - 5 * EPOCHS_IN_PERIOD);
        assertEq(epoch, originalEpoch + diff);
        assertEq(remainingLockup, originalRemainingLockup - diff);
    }

    function testFuzz_updatePowerChangeEpoch_shouldUpdatePowerChangeValue(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 2, type(int104).max));
        int104 powerFraction = int104(bound(power, 1, power - 1));

        vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, powerFraction);
        assertEq(vePWN.exposed_powerChangeFor(staker, epoch).power, powerFraction);

        vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, power - powerFraction);
        assertEq(vePWN.exposed_powerChangeFor(staker, epoch).power, power);

        vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, -power);
        assertEq(vePWN.exposed_powerChangeFor(staker, epoch).power, 0);
    }

    function testFuzz_updatePowerChangeEpoch_shouldAddEpochToArray_whenPowerChangedFromZeroToNonZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);
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
            assertEq(vePWN.exposed_updatePowerChangeEpoch(staker, epochs[i], 0, 100e10), indices[i]);

        assertEq(vePWN.powerChangeEpochs(staker, 0), 0);
        assertEq(vePWN.powerChangeEpochs(staker, 1), 2);
        assertEq(vePWN.powerChangeEpochs(staker, 2), 3);
        assertEq(vePWN.powerChangeEpochs(staker, 3), 5);

        vm.expectRevert();
        vePWN.powerChangeEpochs(staker, 4);
    }

    function testFuzz_updatePowerChangeEpoch_shouldKeepEpochInArray_whenPowerChangedFromNonZeroToNonZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max - 1));

        uint256 index = vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);
        assertEq(vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, 1), index);
    }

    function testFuzz_updatePowerChangeEpoch_shouldRemoveEpochFromArray_whenPowerChangedFromNonZeroToZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);

        index = vePWN.exposed_updatePowerChangeEpoch(staker, epoch, 0, -power);

        vm.expectRevert();
        vePWN.powerChangeEpochs(staker, index);
    }

    function testFuzz_powerChangeMultipliers_initialEpochPower(uint256 amount, uint8 remainingLockup) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory periodMultiplier = new int104[](6);
        periodMultiplier[0] = 100;
        periodMultiplier[1] = 115;
        periodMultiplier[2] = 130;
        periodMultiplier[3] = 150;
        periodMultiplier[4] = 175;
        periodMultiplier[5] = 350;

        int104 power = vePWN.exposed_initialEpochPower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_PERIOD * 5)
            multiplier = periodMultiplier[5];
        else
            multiplier = periodMultiplier[remainingLockup / EPOCHS_IN_PERIOD - (remainingLockup % EPOCHS_IN_PERIOD == 0 ? 1 : 0)];
        assertEq(power, int104(uint104(amount)) * multiplier / 100);
    }

    function testFuzz_powerChangeMultipliers_remainingEpochsDecreasePower(uint256 amount, uint8 remainingLockup) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory periodMultiplier = new int104[](6);
        periodMultiplier[0] = 15;
        periodMultiplier[1] = 15;
        periodMultiplier[2] = 20;
        periodMultiplier[3] = 25;
        periodMultiplier[4] = 175;
        periodMultiplier[5] = 0;

        int104 power = vePWN.exposed_remainingEpochsDecreasePower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_PERIOD * 5)
            multiplier = periodMultiplier[5];
        else if (remainingLockup == 0)
            multiplier = 100;
        else
            multiplier = periodMultiplier[remainingLockup / EPOCHS_IN_PERIOD - (remainingLockup % EPOCHS_IN_PERIOD == 0 ? 1 : 0)];
        assertEq(power, -int104(uint104(amount)) * multiplier / 100);
    }

    function test_powerChangeMultipliers_powerChangesShouldSumToZero(uint8 remainingLockup) external {
        vm.assume(remainingLockup > 0);

        int104 powerChange;
        int104 amount = 100;
        int104 sum = vePWN.exposed_initialEpochPower(amount, remainingLockup);
        while (remainingLockup > 0) {
            (powerChange, , remainingLockup) = vePWN.exposed_nextPowerChangeAndRemainingLockup(amount, 0, remainingLockup);
            sum += powerChange;
        }

        assertEq(sum, 0);
    }

}


/*----------------------------------------------------------*|
|*  # CREATE STAKE                                          *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_CreateStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public staker = makeAddr("staker");
    uint256 public amount = 1e18;
    uint8 public lockUpEpochs = 13;

    event StakeCreated(uint256 indexed stakeId, address indexed staker, uint256 amount, uint256 lockUpEpochs);


    function test_shouldFail_whenInvalidAmount() external {
        vm.expectRevert("vePWN: staked amount out of bounds");
        vePWN.createStake({ amount: 0, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert("vePWN: staked amount out of bounds");
        vePWN.createStake({ amount: 99, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert("vePWN: staked amount out of bounds");
        vePWN.createStake({ amount: uint256(type(uint88).max) + 1, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert("vePWN: staked amount must be a multiple of 100");
        vePWN.createStake({ amount: 101, lockUpEpochs: EPOCHS_IN_PERIOD });
    }

    function test_shouldFail_whenInvalidLockUpEpochs() external {
        vm.expectRevert("vePWN: invalid lock up period range");
        vePWN.createStake({ amount: 100, lockUpEpochs: EPOCHS_IN_PERIOD - 1 });

        vm.expectRevert("vePWN: invalid lock up period range");
        vePWN.createStake({ amount: 100, lockUpEpochs: 10 * EPOCHS_IN_PERIOD + 1 });
    }

    function test_shouldIncreaseStakeId() external {
        uint256 lastStakeId = vePWN.lastStakeId();

        uint256 stakeId = vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        assertEq(stakeId, lastStakeId + 1);
    }

    function test_shouldStoreStakeData() external {
        uint256 stakeId = vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1); // initialEpoch
        assertEq(stakeValue.maskUint104(16), amount); // amount
        assertEq(stakeValue.maskUint8(16 + 104), lockUpEpochs); // remainingLockup
    }

    function testFuzz_shouldStorePowerChanges(uint256 _amount, uint256 _lockUpEpochs) external {
        amount = _boundAmount(_amount);
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(amount, lockUpEpochs);
        bytes32 stakersPowerChanges = STAKERS_NAMESPACE.withMappingKey(staker);
        for (uint256 i; i < powerChanges.length; ++i) {
            bytes32 powerChangeValue = vm.load(address(vePWN), stakersPowerChanges.withArrayIndex(powerChanges[i].epoch));
            int104 powerChange = int104(int256(uint256(powerChangeValue)));
            assertEq(powerChange, powerChanges[i].powerChange);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function testFuzz_shouldUpdatePowerChanges(uint256 _amount, uint256 _lockUpEpochs) external {
        amount = _boundAmount(_amount);
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(amount, lockUpEpochs);
        bytes32 stakersPowerChanges = STAKERS_NAMESPACE.withMappingKey(staker);
        for (uint256 i; i < powerChanges.length; ++i) {
            bytes32 powerChangeValue = vm.load(address(vePWN), stakersPowerChanges.withArrayIndex(powerChanges[i].epoch));
            int104 powerChange = int104(int256(uint256(powerChangeValue)));
            assertEq(powerChange, powerChanges[i].powerChange * 2);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function testFuzz_shouldStorePowerChangeEpochs(uint256 _lockUpEpochs) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(amount, lockUpEpochs);
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(staker, i));
        }

        _assertPowerChangesSumToZero(staker);
    }

    function testFuzz_shouldNotUpdatePowerChangeEpochs_whenSameEpochs(uint256 _lockUpEpochs) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(amount, lockUpEpochs);
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(staker, i));
        }

        _assertPowerChangesSumToZero(staker);
    }

    function test_shouldKeepPowerChangeEpochsSorted() external {
        lockUpEpochs = 130;

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        TestPowerChangeEpoch[] memory powerChanges1 = _createPowerChangesArray(amount, lockUpEpochs);

        currentEpoch += 3;
        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        TestPowerChangeEpoch[] memory powerChanges2 = _createPowerChangesArray(amount, lockUpEpochs);

        assertEq(powerChanges1.length, powerChanges2.length);
        for (uint256 i; i < powerChanges1.length; ++i) {
            assertEq(powerChanges1[i].epoch, vePWN.powerChangeEpochs(staker, 2 * i));
            assertEq(powerChanges2[i].epoch, vePWN.powerChangeEpochs(staker, 2 * i + 1));
        }

        _assertPowerChangesSumToZero(staker);
    }

    function test_shouldEmit_StakeCreated() external {
        vm.expectEmit();
        emit StakeCreated(vePWN.lastStakeId() + 1, staker, amount, lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldTransferPwnTokens() external {
        vm.expectCall(
            pwnToken,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", staker, address(vePWN), amount)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldMintStakedPwnToken() external {
        vm.expectCall(
            stakedPWN,
            abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

}


/*----------------------------------------------------------*|
|*  # SPLIT STAKE                                           *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_SplitStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public staker = makeAddr("staker");
    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 543;
    uint8 public lockUpEpochs = 13;

    event StakeSplit(uint256 indexed stakeId, address indexed staker, uint256 amount, uint256 newStakeId1, uint256 newStakeId2);

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, uint104(amount), lockUpEpochs);

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker)
        );
    }


    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert("vePWN: caller is not the stake owner");
        vm.prank(caller);
        vePWN.splitStake(stakeId, amount / 2);
    }

    function testFuzz_shouldFail_whenSplitAmountNotLessThanStakedAmount(uint256 splitAmount) external {
        splitAmount = bound(splitAmount, amount, type(uint256).max);

        vm.expectRevert("vePWN: split amount must be greater than stake amount");
        vm.prank(staker);
        vePWN.splitStake(stakeId, splitAmount);
    }

    function test_shouldStoreNewStakes(uint256 splitAmount) external {
        splitAmount = bound(splitAmount, 1, amount - 1);

        vm.prank(staker);
        (uint256 newStakeId1, uint256 newStakeId2) = vePWN.splitStake(stakeId, splitAmount);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId1));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint104(16), amount - splitAmount); // amount
        assertEq(stakeValue.maskUint8(16 + 104), lockUpEpochs); // remainingLockup

        stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId2));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint104(16), splitAmount); // amount
        assertEq(stakeValue.maskUint8(16 + 104), lockUpEpochs); // remainingLockup
    }

    function test_shouldDeleteOriginalStake() external {
        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 3);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), 0); // initialEpoch
        assertEq(stakeValue.maskUint104(16), 0); // amount
        assertEq(stakeValue.maskUint8(16 + 104), 0); // remainingLockup
    }

    function test_shouldNotUpdatePowerChanges() external {
        TestPowerChangeEpoch[] memory powerChanges = _mockStake(staker, stakeId, initialEpoch, uint104(amount), lockUpEpochs);

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 3);

        uint256 length = vePWN.workaround_stakerPowerChangeEpochsLength(staker);
        assertEq(powerChanges.length, length);
        _assertPowerChangesSumToZero(staker);
        for (uint256 i; i < length; ++i)
            _assertEpochPowerAndPosition(staker, i, powerChanges[i].epoch, powerChanges[i].powerChange);
    }

    function test_shouldEmit_StakeSplit() external {
        vm.expectEmit();
        emit StakeSplit(stakeId, staker, amount / 3, vePWN.lastStakeId() + 1, vePWN.lastStakeId() + 2);

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 3);
    }

    function test_shouldBurnOriginalStakedPWNToken() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId)
        );

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 3);
    }

    function test_shouldMintNewStakedPWNTokens() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1)
        );
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 2)
        );

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 3);
    }

    function test_shouldReturnNewStakedPWNTokenIds() external {
        uint256 expectedNewStakeId1 = vePWN.lastStakeId() + 1;
        uint256 expectedNewStakeId2 = vePWN.lastStakeId() + 2;

        vm.prank(staker);
        (uint256 newStakeId1, uint256 newStakeId2) = vePWN.splitStake(stakeId, amount / 3);

        assertEq(newStakeId1, expectedNewStakeId1);
        assertEq(newStakeId2, expectedNewStakeId2);
    }

}


/*----------------------------------------------------------*|
|*  # MERGE STAKES                                          *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_MergeStakes_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public staker = makeAddr("staker");
    uint256 public stakeId1 = 421;
    uint256 public stakeId2 = 422;
    uint16 public initialEpoch = uint16(currentEpoch) - 20;
    uint104 public amount = 1 ether;
    uint8 public remainingLockup = 30;

    event StakeMerged(uint256 indexed stakeId1, uint256 indexed stakeId2, address indexed staker, uint256 amount, uint256 remainingLockup, uint256 newStakeId);


    function test_shouldFail_whenCallerNotFirstStakeOwner() external {
        _mockStake(makeAddr("notOwner"), stakeId1, initialEpoch, amount, remainingLockup);

        vm.expectRevert("vePWN: caller is not the first stake owner");
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function test_shouldFail_whenCallerNotSecondStakeOwner() external {
        _mockStake(staker, stakeId1, initialEpoch, amount, remainingLockup);
        _mockStake(makeAddr("notOwner"), stakeId2, initialEpoch, amount, remainingLockup);

        vm.expectRevert("vePWN: caller is not the second stake owner");
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenFirstRemainingLockupSmallerThanSecond(uint256 seed) external {
        uint8 remainingLockup1 = uint8(bound(seed, 1, 10 * EPOCHS_IN_PERIOD - 1));
        uint8 remainingLockup2 = uint8(bound(seed, remainingLockup1 + 1, 10 * EPOCHS_IN_PERIOD));
        _mockStake(staker, stakeId1, initialEpoch, amount, remainingLockup1);
        _mockStake(staker, stakeId2, initialEpoch, amount, remainingLockup2);

        vm.expectRevert("vePWN: the second stakes lockup is longer than the fist stakes lockup");
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenBothStakesLockupEnded(uint8 _remainingLockup) external {
        remainingLockup = uint8(bound(_remainingLockup, 1, 21));
        _mockStake(staker, stakeId1, initialEpoch, amount, remainingLockup);
        _mockStake(staker, stakeId2, initialEpoch, amount, remainingLockup);

        vm.expectRevert("vePWN: both stakes lockups ended");
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldUpdatePowerChanges(
        uint256 _initialEpoch1, uint256 _initialEpoch2,
        uint256 _remainingLockup1, uint256 _remainingLockup2,
        uint256 _amount1, uint256 _amount2
    ) external {
        uint8 maxLockup = 10 * EPOCHS_IN_PERIOD;
        uint16 initialEpoch1 = uint16(bound(_initialEpoch1, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)));
        uint16 initialEpoch2 = uint16(bound(_initialEpoch2, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)));
        uint8 remainingLockup1 = uint8(bound(_remainingLockup1, uint16(currentEpoch) + 2 - initialEpoch1, maxLockup));
        uint8 remainingLockup2 = uint8(bound(_remainingLockup2, 1, initialEpoch1 + remainingLockup1 - initialEpoch2));
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        remainingLockup2 = remainingLockup2 > maxLockup ? maxLockup : remainingLockup2;
        vm.assume(remainingLockup2 > 0); // sometimes bound returns 0 for some reason

        vm.mockCall(
            address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId1), abi.encode(staker)
        );
        vm.mockCall(
            address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId2), abi.encode(staker)
        );
        _storeStake(stakeId1, initialEpoch1, amount1, remainingLockup1);
        _storeStake(stakeId2, initialEpoch2, amount2, remainingLockup2);
        TestPowerChangeEpoch[] memory powerChanges1 = _createPowerChangesArray(initialEpoch1, amount1, remainingLockup1);
        TestPowerChangeEpoch[] memory powerChanges2 = _createPowerChangesArray(initialEpoch2, amount2, remainingLockup2);
        TestPowerChangeEpoch[] memory originalPowerChanges = _mergePowerChanges(powerChanges1, powerChanges2);
        _storePowerChanges(staker, originalPowerChanges);

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint16 newInitialEpoch = uint16(currentEpoch) + 1;
        uint8 newRemainingLockup = remainingLockup1 - uint8(newInitialEpoch - initialEpoch1);
        // merge unchanged power changes 1 with immutable power changes 2
        TestPowerChangeEpoch[] memory mergedPowerChanges = _mergePowerChanges(
            powerChanges1, _createPowerChangesArray(initialEpoch2, newInitialEpoch, amount2, remainingLockup2)
        );
        // merge with new power changes 2
        mergedPowerChanges = _mergePowerChanges(
            mergedPowerChanges, _createPowerChangesArray(newInitialEpoch, amount2, newRemainingLockup)
        );
        // remove existing power from stake 2
        // if (newInitialEpoch > initialEpoch2 && remainingLockup2 >= uint8(newInitialEpoch - initialEpoch2)) {
        if (newInitialEpoch > initialEpoch2 && initialEpoch2 + remainingLockup2 > currentEpoch) {
            TestPowerChangeEpoch[] memory adjustingPowerChange = new TestPowerChangeEpoch[](1);
            adjustingPowerChange[0].epoch = newInitialEpoch;
            adjustingPowerChange[0].powerChange = -vePWN.exposed_initialEpochPower(
                int104(amount2), remainingLockup2 - uint8(newInitialEpoch - initialEpoch2) + 1
            );
            mergedPowerChanges = _mergePowerChanges(mergedPowerChanges, adjustingPowerChange);
        }

        for (uint256 i; i < mergedPowerChanges.length; ++i)
            _assertEpochPowerAndPosition(staker, i, mergedPowerChanges[i].epoch, mergedPowerChanges[i].powerChange);
        _assertPowerChangesSumToZero(staker);
    }

    function test_shouldDeleteOriginalStakes() external {
        _mockStake(staker, stakeId1, initialEpoch, amount, remainingLockup);
        _mockStake(staker, stakeId2, initialEpoch, amount, remainingLockup);

        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId1));
        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId2));

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        bytes32 stakeValue1 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId1));
        assertEq(stakeValue1, bytes32(0));
        bytes32 stakeValue2 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId2));
        assertEq(stakeValue2, bytes32(0));
    }

    function testFuzz_shouldCreateNewStake(uint256 _amount1, uint256 _amount2, uint256 _remainingLockup) external {
        remainingLockup = uint8(bound(_remainingLockup, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_PERIOD));
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockStake(staker, stakeId1, initialEpoch, amount1, remainingLockup);
        _mockStake(staker, stakeId2, initialEpoch, amount2, remainingLockup);

        uint256 newStakeId = vePWN.lastStakeId() + 1;
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, newStakeId)
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint8 newRemainingLockup = remainingLockup - uint8(currentEpoch + 1 - initialEpoch);
        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId));
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1, "initialEpoch mismatch"); // initialEpoch
        assertEq(stakeValue.maskUint104(16), amount1 + amount2, "amount mismatch"); // amount
        assertEq(stakeValue.maskUint8(16 + 104), newRemainingLockup, "remainingLockup mismatch"); // remainingLockup
    }

    function testFuzz_shouldEmit_StakeMerged(uint256 _amount1, uint256 _amount2, uint256 _remainingLockup) external {
        remainingLockup = uint8(bound(_remainingLockup, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_PERIOD));
        uint8 newRemainingLockup = remainingLockup - uint8(currentEpoch + 1 - initialEpoch);
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockStake(staker, stakeId1, initialEpoch, amount1, remainingLockup);
        _mockStake(staker, stakeId2, initialEpoch, amount2, remainingLockup);

        vm.expectEmit();
        emit StakeMerged(stakeId1, stakeId2, staker, amount1 + amount2, newRemainingLockup, vePWN.lastStakeId() + 1);

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

}


/*----------------------------------------------------------*|
|*  # INCREASE STAKE                                        *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_IncreaseStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public staker = makeAddr("staker");
    uint256 public amount = 100;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = uint16(currentEpoch) - 20;
    uint16 public newInitialEpoch = uint16(currentEpoch) + 1;
    uint8 public lockUpEpochs = 23;
    uint256 public additionalAmount = 100;
    uint256 public additionalEpochs = 20;

    event StakeIncreased(uint256 indexed stakeId, address indexed staker, uint256 additionalAmount, uint256 additionalEpochs, uint256 newStakeId);

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, uint104(amount), lockUpEpochs);

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker)
        );
    }

    function _boundInputs(uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs) private view returns (uint8, uint256, uint256, uint8) {
        uint8 lockUpEpochs_ = uint8(bound(_lockUpEpochs, 1, 130));
        uint8 remainingLockup = initialEpoch + lockUpEpochs_ <= currentEpoch
            ? 0
            : uint8(initialEpoch + lockUpEpochs_ - currentEpoch) - 1;
        uint256 additionalAmount_ = bound(_additionalAmount, 0, type(uint88).max / 100) * 100;
        uint256 additionalEpochs_ = bound(
            _additionalEpochs,
            Math.max(1 * EPOCHS_IN_PERIOD, remainingLockup) - remainingLockup,
            Math.max(5 * EPOCHS_IN_PERIOD, remainingLockup) - remainingLockup
        );
        additionalEpochs_ = additionalEpochs_ + remainingLockup > 5 * EPOCHS_IN_PERIOD
            ? 10 * EPOCHS_IN_PERIOD - remainingLockup
            : additionalEpochs_;

        return (lockUpEpochs_, additionalAmount_, additionalEpochs_, remainingLockup);
    }


    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert("vePWN: caller is not the stake owner");
        vm.prank(caller);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldFail_whenNothingToIncrease() external {
        vm.expectRevert("vePWN: nothing to increase");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, 0);
    }

    function testFuzz_shouldFail_whenIncorrectAdditionalAmount(uint256 _additionalAmount) external {
        // over max
        additionalAmount = bound(_additionalAmount, uint256(type(uint88).max) + 1, type(uint256).max / 100);
        vm.expectRevert("vePWN: staked amount out of bounds");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount * 100, additionalEpochs);

        // not a multiple of 100
        additionalAmount = bound(_additionalAmount, 1, uint256(type(uint88).max) - 1);
        additionalAmount += additionalAmount % 100 == 0 ? 1 : 0;
        vm.expectRevert("vePWN: staked amount must be a multiple of 100");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function testFuzz_shouldFail_whenIncorrectdAdditionalEpochs(uint256 _additionalEpochs) external {
        uint8 remainingLockup = uint8(initialEpoch + lockUpEpochs - currentEpoch) - 1;
        // out of bounds
        additionalEpochs = bound(_additionalEpochs, 10 * EPOCHS_IN_PERIOD + 1, type(uint256).max);
        vm.expectRevert("vePWN: additional epochs out of bounds");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // under a period
        additionalEpochs = bound(_additionalEpochs, 1, EPOCHS_IN_PERIOD - remainingLockup - 1);
        vm.expectRevert("vePWN: invalid lock up period range");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 5 & under 10 periods
        additionalEpochs = bound(_additionalEpochs, 5 * EPOCHS_IN_PERIOD - remainingLockup + 1, 10 * EPOCHS_IN_PERIOD - remainingLockup - 1);
        vm.expectRevert("vePWN: invalid lock up period range");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 10 periods
        additionalEpochs = bound(_additionalEpochs, 10 * EPOCHS_IN_PERIOD - remainingLockup + 1, 10 * EPOCHS_IN_PERIOD);
        vm.expectRevert("vePWN: invalid lock up period range");
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldUpdatePowerChanges(
        uint16 _initialEpoch, uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        address emptyStaker = makeAddr("emptyStaker"); // to not have stake mocked from `setUp()` function
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - 130, currentEpoch + 1));
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundInputs(_lockUpEpochs, _additionalAmount, _additionalEpochs);
        vm.assume(additionalEpochs + additionalAmount > 0);

        _mockStake(emptyStaker, stakeId + 1, initialEpoch, uint104(amount), lockUpEpochs);

        vm.prank(emptyStaker);
        vePWN.increaseStake(stakeId + 1, additionalAmount, additionalEpochs);

        // create immutable part of power changes
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(initialEpoch, newInitialEpoch, amount, lockUpEpochs);
        powerChanges = _mergePowerChanges( // merge with increased power changes
            powerChanges, _createPowerChangesArray(newInitialEpoch, amount + additionalAmount, remainingLockup + uint8(additionalEpochs))
        );
        // remove existing power from original stake
        if (initialEpoch <= uint16(currentEpoch) && initialEpoch + lockUpEpochs > uint16(currentEpoch)) {
            TestPowerChangeEpoch[] memory adjustingPowerChange = new TestPowerChangeEpoch[](1);
            adjustingPowerChange[0].epoch = newInitialEpoch;
            adjustingPowerChange[0].powerChange = -vePWN.exposed_initialEpochPower(
                int104(int256(amount)), remainingLockup + 1
            );
            powerChanges = _mergePowerChanges(powerChanges, adjustingPowerChange);
        }

        for (uint256 i; i < powerChanges.length; ++i)
            _assertEpochPowerAndPosition(emptyStaker, i, powerChanges[i].epoch, powerChanges[i].powerChange);
        _assertPowerChangesSumToZero(emptyStaker);
    }

    function testFuzz_shouldStoreNewStakeData(uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs) external {
        address emptyStaker = makeAddr("emptyStaker"); // to not have stake mocked from `setUp()` function
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundInputs(_lockUpEpochs, _additionalAmount, _additionalEpochs);
        vm.assume(additionalEpochs + additionalAmount > 0);

        _mockStake(emptyStaker, stakeId + 1, initialEpoch, uint104(amount), lockUpEpochs);

        vm.prank(emptyStaker);
        vePWN.increaseStake(stakeId + 1, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(vePWN.lastStakeId()));
        assertEq(stakeValue.maskUint16(0), newInitialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint104(16), amount + additionalAmount); // amount
        assertEq(stakeValue.maskUint8(16 + 104), remainingLockup + uint8(additionalEpochs)); // remainingLockup
    }

    function test_shouldDeleteOldStakeData() external {
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue, bytes32(0));
    }

    function test_shouldEmit_StakeIncreased() external {
        vm.expectEmit();
        emit StakeIncreased(stakeId, staker, additionalAmount, additionalEpochs, vePWN.lastStakeId() + 1);

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldBurnOldStakedPWNToken() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId)
        );

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldMintNewStakedPWNToken() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1)
        );

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function testFuzz_shouldTransferAdditionalPWNTokens(uint256 _additionalAmount) external {
        additionalAmount = bound(_additionalAmount, 0, type(uint88).max / 100) * 100;
        vm.expectCall(
            pwnToken,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", staker, address(vePWN), additionalAmount),
            additionalAmount > 0 ? 1 : 0
        );

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldReturnNewStakedPWNTokenIds() external {
        uint256 expectedStakeId = vePWN.lastStakeId() + 1;

        vm.prank(staker);
        uint256 newStakeId = vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        assertEq(newStakeId, expectedStakeId);
    }

}


/*----------------------------------------------------------*|
|*  # WITHDRAW STAKE                                        *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_WithdrawStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public staker = makeAddr("staker");
    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 400;
    uint8 public lockUpEpochs = 13;

    event StakeWithdrawn(address indexed staker, uint256 amount);

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, uint104(amount), lockUpEpochs);

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker)
        );
        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)"), abi.encode("")
        );
        vm.mockCall(
            pwnToken, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true)
        );
    }


    function test_shouldFail_whenStakeDoesNotExist() external {
        vm.expectRevert();
        vm.prank(staker);
        vePWN.withdrawStake(stakeId + 1);
    }

    function testFuzz_shouldFail_whenCallerIsNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert("vePWN: caller is not the stake owner");
        vm.prank(caller);
        vePWN.withdrawStake(stakeId);
    }

    function testFuzz_shouldFail_whenLockUpStillRunning(uint256 _lockUpEpochs, uint8 _remainingLockup) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        uint8 remainingLockup = uint8(bound(_remainingLockup, 1, uint256(lockUpEpochs)));
        uint256 runningStakeId = stakeId + 132;

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", runningStakeId), abi.encode(staker)
        );
        _mockStake(
            staker, runningStakeId, uint16(currentEpoch) - lockUpEpochs + remainingLockup, uint104(amount), lockUpEpochs
        );

        vm.expectRevert("vePWN: staker cannot withdraw before lockup period");
        vm.prank(staker);
        vePWN.withdrawStake(runningStakeId);
    }

    function test_shouldDeleteStakeData() external {
        vm.prank(staker);
        vePWN.withdrawStake(stakeId);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), 0); // initialEpoch
        assertEq(stakeValue.maskUint104(16), 0); // amount
        assertEq(stakeValue.maskUint8(16 + 104), 0); // remainingLockup
    }

    function test_shouldEmit_StakeWithdrawn() external {
        vm.expectEmit();
        emit StakeWithdrawn(staker, amount);

        vm.prank(staker);
        vePWN.withdrawStake(stakeId);
    }

    function test_shouldBurnStakedPWNToken() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId)
        );

        vm.prank(staker);
        vePWN.withdrawStake(stakeId);
    }

    function test_shouldTransferPWNTokenToStaker() external {
        vm.expectCall(
            pwnToken, abi.encodeWithSignature("transfer(address,uint256)", staker, amount)
        );

        vm.prank(staker);
        vePWN.withdrawStake(stakeId);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER STAKE                                        *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_TransferStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public from = makeAddr("from");
    address public to = makeAddr("to");
    uint256 public stakeId = 42;
    uint16 public initialEpoch = uint16(currentEpoch) - 20;
    uint104 public amount = 100e18;
    uint8 public remainingLockup = 130;

    event StakeTransferred(uint256 indexed stakeId, address indexed fromStaker, address indexed toStaker, uint256 amount);


    function test_shouldFail_whenCallerIsNotStakedPwnContract() external {
        vm.expectRevert("vePWN: caller is not stakedPWN");
        vePWN.transferStake(from, to, stakeId);
    }

    function test_shouldSkip_whenSenderZeroAddress() external {
        vm.expectCall({
            callee: epochClock,
            data: abi.encodeWithSignature("currentEpoch()"),
            count: 0
        });

        vm.prank(stakedPWN);
        vePWN.transferStake(address(0), to, stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), 0);
    }

    function test_shouldSkip_whenReceiverZeroAddress() external {
        vm.expectCall({
            callee: epochClock,
            data: abi.encodeWithSignature("currentEpoch()"),
            count: 0
        });

        vm.prank(stakedPWN);
        vePWN.transferStake(from, address(0), stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), 0);
    }

    function test_shouldFail_whenCallerNotStakeOwner() external {
        vm.mockCall(
            address(stakedPWN),
            abi.encodeWithSignature("ownerOf(uint256)", stakeId),
            abi.encode(makeAddr("notOwner"))
        );

        vm.expectRevert("vePWN: sender is not the stake owner");
        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);
    }

    function testFuzz_shouldSkip_whenLockupPeriodEnded(uint16 _initialEpoch) external {
        initialEpoch = uint16(bound(_initialEpoch, 1, currentEpoch - remainingLockup + 1));
        _mockStake(from, stakeId, initialEpoch, amount, remainingLockup);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), initialEpoch);
        assertEq(stakeValue.maskUint8(16 + 104), remainingLockup);
    }

    function testFuzz_shouldUpdateStakeData(uint16 _initialEpoch) external {
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - remainingLockup + 2, currentEpoch));
        _mockStake(from, stakeId, initialEpoch, amount, remainingLockup);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1);
        assertEq(stakeValue.maskUint8(16 + 104), remainingLockup - (currentEpoch - initialEpoch + 1));
    }

    function testFuzz_shouldUpdatePowerChange_whenTransferredBeforeInitialEpoch(uint256 _amount, uint8 _remainingLockup) external {
        amount = uint104(_boundAmount(_amount));
        remainingLockup = _boundLockUpEpochs(_remainingLockup);

        initialEpoch = uint16(currentEpoch) + 1;
        TestPowerChangeEpoch[] memory powerChanges = _mockStake(from, stakeId, initialEpoch, amount, remainingLockup);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        // check cliff transfer
        for (uint256 i; i < powerChanges.length; ++i)
            _assertEpochPowerAndPosition(to, i, powerChanges[i].epoch, powerChanges[i].powerChange);

        // check correct number of cliffs
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(from), 0);
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(to), powerChanges.length);

        // check power changes sum to zero
        _assertPowerChangesSumToZero(from);
        _assertPowerChangesSumToZero(to);
    }

    function testFuzz_shouldUpdatePowerChanges_whenTransferredAfterInitialEpoch(uint256 _amount, uint8 _lockUpEpochs, uint8 _remainingLockup) external {
        amount = uint104(_boundAmount(_amount));
        uint8 lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        uint256 numberOfCliffs = uint256(lockUpEpochs) / uint256(EPOCHS_IN_PERIOD) + 1;
        numberOfCliffs += lockUpEpochs % EPOCHS_IN_PERIOD == 0 ? 0 : 1;
        remainingLockup = uint8(bound(_remainingLockup, 2, lockUpEpochs));

        initialEpoch = uint16(currentEpoch) - lockUpEpochs + remainingLockup;
        TestPowerChangeEpoch[] memory powerChanges = _mockStake(from, stakeId, initialEpoch, amount, lockUpEpochs);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        // check cliff transfer
        uint256 sendersNumberOfCliffs;
        uint256 receiversNumberOfCliffs;
        uint16 adjustingEpoch = uint16(currentEpoch) + 1;
        uint256 adjustingReceiverIndex;
        for (uint256 i; i < powerChanges.length; ++i) {
            if (powerChanges[i].epoch == adjustingEpoch) {
                adjustingReceiverIndex = 1;
                continue;
            }

            bool onSenderPart = powerChanges[i].epoch < adjustingEpoch;
            if (onSenderPart)
                ++sendersNumberOfCliffs;
            else
                ++receiversNumberOfCliffs;

            _assertEpochPowerAndPosition(
                onSenderPart ? from : to,
                onSenderPart ? i : i - sendersNumberOfCliffs + 1 - adjustingReceiverIndex, // skipping adjusting epochs (first)
                powerChanges[i].epoch,
                powerChanges[i].powerChange
            );
        }

        // add adjusting epoch to the number of cliffs
        ++sendersNumberOfCliffs;
        ++receiversNumberOfCliffs;

        // check adjusting epoch power
        int104 power = vePWN.exposed_initialEpochPower(int104(amount), remainingLockup - 1);
        _assertEpochPowerAndPosition(to, 0, adjustingEpoch, power);
        if (adjustingReceiverIndex > 0) {
            // in case the last cliff has to be updated instead of created
            power -= vePWN.exposed_remainingEpochsDecreasePower(int104(amount), remainingLockup - 1);
        }
        _assertEpochPowerAndPosition(from, sendersNumberOfCliffs - 1, adjustingEpoch, -power);

        // check correct number of cliffs
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(from), sendersNumberOfCliffs);
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(to), receiversNumberOfCliffs);

        // check power changes sum to zero
        _assertPowerChangesSumToZero(from);
        _assertPowerChangesSumToZero(to);
    }

    function test_shouldEmit_StakeTransferred() external {
        _mockStake(from, stakeId, initialEpoch, amount, remainingLockup);

        vm.expectEmit();
        emit StakeTransferred(stakeId, from, to, amount);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);
    }

}
