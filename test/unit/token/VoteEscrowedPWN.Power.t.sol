// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { Error } from "src/lib/Error.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";
import { VoteEscrowedPWN, StakesInEpoch } from "src/token/VoteEscrowedPWN.sol";

import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

abstract contract VoteEscrowedPWN_Power_Test is VoteEscrowedPWN_Test {
    using SlotComputingLib for bytes32;

    function setUp() override virtual public {
        super.setUp();

        vePWN.workaround_setMockStakerPowerAt(false);
        vePWN.workaround_setMockTotalPowerAt(false);
    }

    // solhint-disable-next-line var-name-mixedcase
    int104[] public helper_totalPowerChanges;
    function _createTotalPowerChangeEpochs(uint256 seed, uint256 minLength) internal returns (int104[] memory epochs) {
        uint256 maxLength = 100;
        seed = bound(seed, 1, type(uint256).max / 2);
        uint256 length = bound(seed, minLength, maxLength);
        int256 totalPower;

        for (uint256 i; i < length; ++i) {
            int256 iSeed = int256(uint256(keccak256(abi.encode(seed + i))));
            int256 power = bound(iSeed, -totalPower, int256(type(int104).max) / int256(maxLength));
            power = power == 0 ? int256(1) : power;
            totalPower += power;
            helper_totalPowerChanges.push(int104(power));
        }

        epochs = helper_totalPowerChanges;
        delete helper_totalPowerChanges;
    }

    function _calculateTotalPowerChangeEpochs(
        int104[] memory epochs, uint256 lcIndex
    ) internal pure returns (int104[] memory) {
        require(lcIndex < epochs.length, "lcIndex >= epochs.length");
        for (uint256 i = 1; i <= lcIndex; ++i) {
            epochs[i] += epochs[i - 1];
            require(epochs[i] > 0, "powerChange <= 0");
        }
        return epochs;
    }

    function _mockLastCalculatedTotalPowerEpoch(uint256 epoch) internal {
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));
    }

}


/*----------------------------------------------------------*|
|*  # SIMULATE STAKE POWERS                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_SimulateStakePowers_Test is VoteEscrowedPWN_Power_Test {

    function test_shouldFail_whenInvalidAmount() external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.simulateStakePowers({ currentEpoch: currentEpoch, amount: 0, remainingLockup: EPOCHS_IN_YEAR });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.simulateStakePowers({ currentEpoch: currentEpoch, amount: 99, remainingLockup: EPOCHS_IN_YEAR });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.simulateStakePowers({
            currentEpoch: currentEpoch, amount: uint256(type(uint88).max) + 1, remainingLockup: EPOCHS_IN_YEAR
        });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.simulateStakePowers({ currentEpoch: currentEpoch, amount: 101, remainingLockup: EPOCHS_IN_YEAR });
    }

    function test_shouldFail_whenInvalidLockUpEpochs() external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vePWN.simulateStakePowers({ currentEpoch: currentEpoch, amount: 100, remainingLockup: 0 });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vePWN.simulateStakePowers({ currentEpoch: currentEpoch, amount: 100, remainingLockup: 10 * EPOCHS_IN_YEAR + 1 });
    }

    function testFuzz_shouldReturnCorrectEpochPowers(uint256 epoch, uint256 amount, uint256 remainingLockup)
        external
    {
        uint16 _epoch = uint16(bound(epoch, 1, uint256(type(uint16).max - 10 * EPOCHS_IN_YEAR - 1)));
        uint104 _amount = uint104(_boundAmount(amount));
        uint8 _remainingLockup = _boundRemainingLockups(remainingLockup);
        // create power changes
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_epoch, _remainingLockup, _amount);
        // make power values from changes
        VoteEscrowedPWN.EpochPower[] memory expectedPowers = new VoteEscrowedPWN.EpochPower[](powerChanges.length);
        for (uint256 i; i < powerChanges.length; ++i) {
            expectedPowers[i].epoch = powerChanges[i].epoch;
            expectedPowers[i].power = i == 0
                ? powerChanges[i].powerChange
                : expectedPowers[i - 1].power + powerChanges[i].powerChange;
        }

        // call simulateStakePowers
        VoteEscrowedPWN.EpochPower[] memory powers = vePWN.simulateStakePowers({
            currentEpoch: _epoch, amount: _amount, remainingLockup: _remainingLockup
        });

        // assert epoch powers
        assertEq(powers.length, expectedPowers.length);
        for (uint256 i; i < powers.length; ++i) {
            assertEq(powers[i].epoch, expectedPowers[i].epoch);
            assertEq(powers[i].power, expectedPowers[i].power);
        }
        assertEq(powers[powers.length - 1].power, 0);
    }

}


/*----------------------------------------------------------*|
|*  # STAKER POWER AT                                       *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_StakerPowerAt_Test is VoteEscrowedPWN_Power_Test {
    using SlotComputingLib for bytes32;

    function testFuzz_shouldFail_whenEpochTooBig(uint256 epoch) external {
        epoch = bound(epoch, uint256(type(uint16).max) + 1, type(uint256).max);

        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        vePWN.stakerPowerAt(staker, epoch);
    }

    function test_shouldReturnZero_whenEpochIsZero() external {
        uint256 power = vePWN.stakerPowerAt(staker, 0);

        assertEq(power, 0);
    }

    function testFuzz_shouldReturnZero_whenEpochBeforeInitialEpoch(uint256 epoch) external {
        uint16 initialEpoch = 100;
        _mockStake(staker, 42, initialEpoch, 13, 100 ether);
        epoch = bound(epoch, 0, initialEpoch - 1);

        uint256 power = vePWN.stakerPowerAt(staker, epoch);

        assertEq(power, 0);
    }

    function testFuzz_shouldReturnZero_whenEpochAfterExpiration(uint256 epoch) external {
        uint16 initialEpoch = 100;
        uint8 lockup = 13;
        _mockStake(staker, 42, initialEpoch, lockup, 100 ether);
        epoch = bound(epoch, initialEpoch + lockup, type(uint16).max);

        uint256 power = vePWN.stakerPowerAt(staker, epoch);

        assertEq(power, 0);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnCurrentStakePower(uint256 lockupSeed, uint256 amountSeed) external {
        // mock one stake in current epoch
        uint104 amount = uint104(_boundAmount(amountSeed));
        uint8 lockup = _boundRemainingLockups(lockupSeed);
        _mockStake(staker, 42, uint16(currentEpoch), lockup, amount);

        uint256 power = vePWN.stakerPowerAt(staker, currentEpoch);

        assertEq(int256(power), vePWN.exposed_power(int104(amount), lockup));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnSumOfAllStakesPower(uint256 stakes, uint256 amountSeed) external {
        // mock several 1 year stakes in current epoch
        stakes = bound(stakes, 1, 100);
        amountSeed = bound(amountSeed, 1, type(uint256).max - stakes);
        uint104 totalAmount;
        StakesInEpoch[] memory stakesInEpochs = new StakesInEpoch[](1);
        stakesInEpochs[0].epoch = uint16(currentEpoch);
        stakesInEpochs[0].ids = new uint48[](stakes);
        for (uint256 i; i < stakes; ++i) {
            uint256 iSeed = uint256(keccak256(abi.encode(amountSeed + i)));
            uint104 amount = uint104(_boundAmount(iSeed) / stakes);
            totalAmount += amount;
            _mockStake(staker, i + 1, uint16(currentEpoch), 13, amount);
            stakesInEpochs[0].ids[i] = uint48(i + 1);
        }
        vePWN.workaround_addStakeToBeneficiary(staker, stakesInEpochs);

        uint256 power = vePWN.stakerPowerAt(staker, currentEpoch);

        assertEq(power, totalAmount);
    }

}


/*----------------------------------------------------------*|
|*  # STAKER POWERS                                         *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_StakerPowers_Test is VoteEscrowedPWN_Power_Test {

    function testFuzz_shouldReturnStakerPowersForEpochs(uint256 epochCount, uint256 amountSeed) external {
        // mock one stake per epoch
        epochCount = bound(epochCount, 1, 100);
        amountSeed = bound(amountSeed, 1, type(uint256).max - epochCount);
        uint256[] memory expectedPowers = new uint256[](epochCount);
        uint256[] memory epochs = new uint256[](epochCount);
        for (uint256 i = 1; i <= epochCount; ++i) {
            uint256 iSeed = uint256(keccak256(abi.encode(amountSeed + i)));
            uint104 amount = uint104(_boundAmount(iSeed) / epochCount);
            _mockStake(staker, i, uint16(i), 13, amount);
            expectedPowers[i - 1] = uint256(amount);
            epochs[i - 1] = i;
        }

        uint256[] memory powers = vePWN.stakerPowers(staker, epochs);

        for (uint256 i; i < powers.length; ++i) {
            assertEq(powers[i], expectedPowers[i]);
        }
    }

}


/*----------------------------------------------------------*|
|*  # BENEFICIARY OF STAKES AT                              *|
|*----------------------------------------------------------*/

contract StakedPWN_BeneficiaryOfStakesAt_Test is VoteEscrowedPWN_Power_Test {

    function testFuzz_shouldReturnEmpty_whenNoStakes(uint16 epoch) external {
        // don't mock tokens

        uint256[] memory ids = vePWN.beneficiaryOfStakesAt(staker, epoch);

        assertEq(ids.length, 0);
    }

    function testFuzz_shouldReturnEmpty_whenEpochBeforeFirstStake(uint256 epoch) external {
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        _mockStakeBeneficiary(staker, 1, _epoch);

        uint256[] memory ids = vePWN.beneficiaryOfStakesAt(staker, _epoch - 1);

        assertEq(ids.length, 0);
    }

    function test_shouldReturnListOfStakesForBeneficiary() external {
        uint16[] memory epochs = new uint16[](3);
        epochs[0] = 1;
        epochs[1] = 10;
        epochs[2] = 20;

        StakesInEpoch[] memory stakesInEpochs = new StakesInEpoch[](3);
        uint48[] memory _ids = new uint48[](1);
        _ids[0] = 1;
        stakesInEpochs[0] = StakesInEpoch(epochs[0], _ids);
        _ids = new uint48[](2);
        _ids[0] = 1;
        _ids[1] = 2;
        stakesInEpochs[1] = StakesInEpoch(epochs[1], _ids);
        _ids = new uint48[](3);
        _ids[0] = 1;
        _ids[1] = 2;
        _ids[2] = 3;
        stakesInEpochs[2] = StakesInEpoch(epochs[2], _ids);
        vePWN.workaround_addStakeToBeneficiary(staker, stakesInEpochs);

        uint256[] memory ids = vePWN.beneficiaryOfStakesAt(staker, 1);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        ids = vePWN.beneficiaryOfStakesAt(staker, 9);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        ids = vePWN.beneficiaryOfStakesAt(staker, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);

        ids = vePWN.beneficiaryOfStakesAt(staker, 14);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);

        ids = vePWN.beneficiaryOfStakesAt(staker, 21);
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL POWER AT                                        *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_TotalPowerAt_Test is VoteEscrowedPWN_Power_Test {

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldReturnStoredPower_whenEpochIsCalculated(
        uint256 seed, uint256 lcEpoch, uint256 epoch
    ) external {
        // create total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        // mock last calculated epoch
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 1);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        // mock total power changes
        totalPowerChanges = _calculateTotalPowerChangeEpochs(totalPowerChanges, lastCalculatedEpoch);
        for (uint256 i; i < totalPowerChanges.length; ++i) {
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        }
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
        // create total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        // mock last calculated epoch
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 2);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        // mock total power changes
        totalPowerChanges = _calculateTotalPowerChangeEpochs(totalPowerChanges, lastCalculatedEpoch);
        for (uint256 i; i < totalPowerChanges.length; ++i) {
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        }
        // pick epoch
        epoch = bound(epoch, lastCalculatedEpoch + 1, totalPowerChanges.length - 1);
        assertGt(epoch, lastCalculatedEpoch);

        uint256 totalPower = vePWN.totalPowerAt(epoch);

        int104 expectedPower;
        for (uint256 i = lastCalculatedEpoch; i <= epoch; ++i) {
            expectedPower += totalPowerChanges[i];
        }
        assertEq(totalPower, uint256(uint104(expectedPower)));
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL POWERS                                          *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_TotalPowers_Test is VoteEscrowedPWN_Power_Test {

    function testFuzz_shouldReturnTotalPowersForEpochs(uint256 seed) external {
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        uint256 lastCalculatedEpoch = totalPowerChanges.length - 1;
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        totalPowerChanges = _calculateTotalPowerChangeEpochs(totalPowerChanges, lastCalculatedEpoch);
        for (uint256 i; i < totalPowerChanges.length; ++i) {
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        }

        uint256[] memory epochs = new uint256[](totalPowerChanges.length);
        for (uint256 i; i < epochs.length; ++i) {
            epochs[i] = i;
        }

        uint256[] memory powers = vePWN.totalPowers(epochs);

        for (uint256 i; i < powers.length; ++i) {
            assertEq(powers[i], uint256(uint104(totalPowerChanges[i])));
        }
    }

}


/*----------------------------------------------------------*|
|*  # CALCULATE TOTAL POWER                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Power_CalculateTotalPower_Test is VoteEscrowedPWN_Power_Test {

    event TotalPowerCalculated(uint256 indexed epoch);

    function testFuzz_shouldFail_whenEpochDoesNotEnded(uint256 epoch) external {
        // no need to mock epochs, it's ok to compute with zero epochs
        epoch = bound(epoch, currentEpoch + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Error.EpochStillRunning.selector));
        vePWN.calculateTotalPowerUpTo(epoch);
    }

    function testFuzz_shouldFail_whenTotalPowerAlreadyCalculated(uint256 epoch, uint256 lcEpoch) external {
        // no need to mock epochs, it's ok to compute with zero epochs
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, currentEpoch);
        epoch = bound(epoch, 0, lastCalculatedEpoch);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);

        vm.expectRevert(abi.encodeWithSelector(Error.PowerAlreadyCalculated.selector, lastCalculatedEpoch));
        vePWN.calculateTotalPowerUpTo(epoch);
    }

    function testFuzz_shouldCalculateTotalPowers(uint256 seed, uint256 epoch, uint256 lcEpoch) external {
        // create total power changes
        int104[] memory totalPowerChanges = _createTotalPowerChangeEpochs(seed, 2);
        // mock last calculated epoch
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, totalPowerChanges.length - 2);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);
        // mock total power changes
        _calculateTotalPowerChangeEpochs(totalPowerChanges, lastCalculatedEpoch);
        for (uint256 i; i < totalPowerChanges.length; ++i) {
            vePWN.workaround_storeTotalEpochPower(i, totalPowerChanges[i]);
        }
        // pick epoch
        epoch = bound(epoch, lastCalculatedEpoch + 1, totalPowerChanges.length - 1);

        vePWN.calculateTotalPowerUpTo(epoch);

        int104 totalPower;
        for (uint256 i = lastCalculatedEpoch; i <= epoch; ++i) {
            totalPower += totalPowerChanges[i];
            assertEq(totalPower, vePWN.workaround_getTotalEpochPower(i));
        }
    }

    function testFuzz_shouldStoreNewLastCalculatedTotalPower(uint256 epoch, uint256 lcEpoch) external {
        // no need to mock epochs, it's ok to compute with zero epochs
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, currentEpoch - 1);
        epoch = bound(epoch, lastCalculatedEpoch + 1, currentEpoch);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);

        vePWN.calculateTotalPowerUpTo(epoch);

        bytes32 lastCalculatedEpochValue = vm.load(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT);
        assertEq(uint256(lastCalculatedEpochValue), epoch);
        assertEq(vePWN.lastCalculatedTotalPowerEpoch(), epoch);
    }

    function testFuzz_shouldEmit_TotalPowerCalculated(uint256 epoch, uint256 lcEpoch) external {
        // no need to mock epochs, it's ok to compute with zero epochs
        uint256 lastCalculatedEpoch = bound(lcEpoch, 0, currentEpoch - 1);
        epoch = bound(epoch, lastCalculatedEpoch + 1, currentEpoch);
        _mockLastCalculatedTotalPowerEpoch(lastCalculatedEpoch);

        vm.expectEmit();
        emit TotalPowerCalculated(epoch);

        vePWN.calculateTotalPowerUpTo(epoch);
    }

    function test_calculateTotalPower_shouldUseCurrentEpoch() external {
        // no need to mock epochs, it's ok to compute with zero epochs

        vePWN.calculateTotalPower();

        bytes32 lastCalculatedEpochValue = vm.load(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT);
        assertEq(uint256(lastCalculatedEpochValue), currentEpoch);
        assertEq(vePWN.lastCalculatedTotalPowerEpoch(), currentEpoch);
    }

}
