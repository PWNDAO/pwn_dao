// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { BitMaskLib } from "src/lib/BitMaskLib.sol";
import { Error } from "src/lib/Error.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";

import { VoteEscrowedPWN_Test, StakesInEpoch } from "./VoteEscrowedPWNTest.t.sol";

// solhint-disable-next-line no-empty-blocks
abstract contract VoteEscrowedPWN_Stake_Test is VoteEscrowedPWN_Test {}


/*----------------------------------------------------------*|
|*  # CREATE STAKE                                          *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_CreateStake_Test is VoteEscrowedPWN_Stake_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    uint256 public amount = 1e18;
    uint8 public lockUpEpochs = 13;

    event StakeCreated(uint256 indexed stakeId, address indexed staker, uint256 amount, uint256 lockUpEpochs);


    function test_shouldFail_whenInvalidAmount() external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: 0, lockUpEpochs: EPOCHS_IN_YEAR });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: 99, lockUpEpochs: EPOCHS_IN_YEAR });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: uint256(type(uint88).max) + 1, lockUpEpochs: EPOCHS_IN_YEAR });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: 101, lockUpEpochs: EPOCHS_IN_YEAR });
    }

    function test_shouldFail_whenInvalidLockUpEpochs() external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vePWN.createStake({ amount: 100, lockUpEpochs: EPOCHS_IN_YEAR - 1 });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vePWN.createStake({ amount: 100, lockUpEpochs: 10 * EPOCHS_IN_YEAR + 1 });
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
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount); // amount
    }

    function testFuzz_shouldStoreTotalPowerChanges(uint256 _lockUpEpochs, uint256 _amount) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        amount = _boundAmount(_amount);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }

        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function testFuzz_shouldUpdateTotalPowerChanges(
        uint256 _lockUpEpochs1, uint256 _lockUpEpochs2, uint256 _amount1, uint256 _amount2
    ) external {
        _lockUpEpochs1 = _boundLockUpEpochs(_lockUpEpochs1);
        _lockUpEpochs2 = _boundLockUpEpochs(_lockUpEpochs2);
        _amount1 = _boundAmount(_amount1);
        _amount2 = _boundAmount(_amount2);

        vm.prank(makeAddr("staker1"));
        vePWN.createStake({ amount: _amount1, lockUpEpochs: _lockUpEpochs1 });

        vm.prank(makeAddr("staker2"));
        vePWN.createStake({ amount: _amount2, lockUpEpochs: _lockUpEpochs2 });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_lockUpEpochs1, _amount1);
        powerChanges = _mergePowerChanges(powerChanges, _createPowerChangesArray(_lockUpEpochs2, _amount2));
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }

        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function test_shouldEmit_StakeCreated() external {
        vm.expectEmit();
        emit StakeCreated(vePWN.lastStakeId() + 1, staker, amount, lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldTransferPWNTokens() external {
        vm.expectCall(
            pwnToken, abi.encodeWithSignature("transferFrom(address,address,uint256)", staker, address(vePWN), amount)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldMintStakedPWNToken() external {
        vm.expectCall(stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1));

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

    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 543;
    uint8 public lockUpEpochs = 13;

    event StakeSplit(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 amount1,
        uint256 amount2,
        uint256 newStakeId1,
        uint256 newStakeId2
    );

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));
    }


    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
        vePWN.splitStake(stakeId, amount / 2);
    }

    function test_shouldFail_whenCallerNotStakeBeneficiary() external {
        address otherStaker = makeAddr("otherStaker");
        _mockStake(otherStaker, stakeId, initialEpoch, lockUpEpochs, uint104(amount), false);

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(otherStaker));

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(otherStaker);
        vePWN.splitStake(stakeId, amount / 2);
    }

    function testFuzz_shouldFail_whenInvalidSplitAmount(uint256 splitAmount) external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vm.prank(staker);
        vePWN.splitStake(stakeId, 0);

        splitAmount = bound(splitAmount, amount, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vm.prank(staker);
        vePWN.splitStake(stakeId, splitAmount);

        splitAmount = bound(splitAmount, 1, amount / 100 - 1) * 100;
        splitAmount += bound(splitAmount, 1, 99);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vm.prank(staker);
        vePWN.splitStake(stakeId, splitAmount);
    }

    function test_shouldStoreNewStakes(uint256 splitAmount) external {
        splitAmount = bound(splitAmount, 1, amount / 100 - 1) * 100;

        vm.prank(staker);
        (uint256 newStakeId1, uint256 newStakeId2) = vePWN.splitStake(stakeId, splitAmount);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId1));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount - splitAmount); // amount

        stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId2));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), splitAmount); // amount
    }

    function test_shouldNotDeleteOriginalStake() external {
        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount); // amount
    }

    function test_shouldEmit_StakeSplit() external {
        vm.expectEmit();
        emit StakeSplit(stakeId, staker, amount * 3 / 4, amount / 4, vePWN.lastStakeId() + 1, vePWN.lastStakeId() + 2);

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);
    }

    function test_shouldBurnOriginalStakedPWNToken() external {
        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId));

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);
    }

    function test_shouldMintNewStakedPWNTokens() external {
        vm.expectCall(stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1));
        vm.expectCall(stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 2));

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);
    }

    function test_shouldReturnNewStakedPWNTokenIds() external {
        uint256 expectedNewStakeId1 = vePWN.lastStakeId() + 1;
        uint256 expectedNewStakeId2 = vePWN.lastStakeId() + 2;

        vm.prank(staker);
        (uint256 newStakeId1, uint256 newStakeId2) = vePWN.splitStake(stakeId, amount / 4);

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

    uint256 public stakeId1 = 421;
    uint256 public stakeId2 = 422;
    uint16 public initialEpoch = uint16(currentEpoch) - 20;
    uint104 public amount = 1 ether;
    uint8 public lockUpEpochs = 30;

    event StakeMerged(
        uint256 indexed stakeId1,
        uint256 indexed stakeId2,
        address indexed staker,
        uint256 amount,
        uint256 lockUpEpochs,
        uint256 newStakeId
    );

    function _boundMergeInputs(
        uint256 _initialEpoch1, uint256 _initialEpoch2,
        uint256 _lockUpEpochs1, uint256 _lockUpEpochs2,
        uint256 _amount1, uint256 _amount2
    ) private view returns (
        uint16 initialEpoch1,
        uint16 initialEpoch2,
        uint8 lockUpEpochs1,
        uint8 lockUpEpochs2,
        uint104 amount1,
        uint104 amount2
    ) {
        uint8 maxLockup = 10 * EPOCHS_IN_YEAR;
        initialEpoch1 = uint16(bound(
            _initialEpoch1, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)
        ));
        initialEpoch2 = uint16(bound(
            _initialEpoch2, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)
        ));
        lockUpEpochs1 = uint8(bound(_lockUpEpochs1, uint16(currentEpoch) + 2 - initialEpoch1, maxLockup));
        lockUpEpochs2 = uint8(bound(_lockUpEpochs2, 1, initialEpoch1 + lockUpEpochs1 - initialEpoch2));
        amount1 = uint104(_boundAmount(_amount1));
        amount2 = uint104(_boundAmount(_amount2));
        lockUpEpochs2 = lockUpEpochs2 > maxLockup ? maxLockup : lockUpEpochs2;
        vm.assume(lockUpEpochs2 > 0); // sometimes bound returns 0 for some reason
    }


    function test_shouldFail_whenCallerNotFirstStakeOwner() external {
        _mockStake(makeAddr("notOwner"), stakeId1, initialEpoch, lockUpEpochs, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function test_shouldFail_whenCallerNotSecondStakeOwner() external {
        _mockStake(staker, stakeId1, initialEpoch, lockUpEpochs, amount);
        _mockStake(makeAddr("notOwner"), stakeId2, initialEpoch, lockUpEpochs, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function test_shouldFail_whenCallerNotFirstStakeBeneficiary() external {
        _mockStake(staker, stakeId1, initialEpoch, lockUpEpochs, amount, false);
        _mockStake(staker, stakeId2, initialEpoch, lockUpEpochs, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function test_shouldFail_whenCallerNotSecondStakeBeneficiary() external {
        _mockStake(staker, stakeId1, initialEpoch, lockUpEpochs, amount);
        _mockStake(staker, stakeId2, initialEpoch, lockUpEpochs, amount, false);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenFirstLockUpSmallerThanSecond(uint256 seed) external {
        uint8 lockUpEpochs1 = uint8(bound(seed, 1, 10 * EPOCHS_IN_YEAR - 1));
        uint8 lockUpEpochs2 = uint8(bound(seed, lockUpEpochs1 + 1, 10 * EPOCHS_IN_YEAR));
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs1, lockUpEpochs2, amount, amount
        );

        vm.expectRevert(abi.encodeWithSelector(Error.LockUpPeriodMismatch.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenBothStakesLockupEnded(uint8 _lockUpEpochs) external {
        lockUpEpochs = uint8(bound(_lockUpEpochs, 1, 21));
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs, lockUpEpochs, amount, amount
        );

        vm.expectRevert(abi.encodeWithSelector(Error.LockUpPeriodMismatch.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldClearRemainingTotalPowerChanges_whenDifferentPowerChangeEpochs(
        uint256 _initialEpoch1, uint256 _initialEpoch2,
        uint256 _lockUpEpochs1, uint256 _lockUpEpochs2,
        uint256 _amount1, uint256 _amount2
    ) external {
        (
            uint16 initialEpoch1, uint16 initialEpoch2,
            uint8 lockUpEpochs1, uint8 lockUpEpochs2,
            uint104 amount1, uint104 amount2
        ) = _boundMergeInputs(
            _initialEpoch1, _initialEpoch2, _lockUpEpochs1, _lockUpEpochs2, _amount1, _amount2
        );
        uint16 finalEpoch1 = initialEpoch1 + lockUpEpochs1;
        uint16 finalEpoch2 = initialEpoch2 + lockUpEpochs2;
        // assume different power changes epochs
        vm.assume(finalEpoch1 % EPOCHS_IN_YEAR != finalEpoch2 % EPOCHS_IN_YEAR);

        (, TestPowerChangeEpoch[] memory powerChanges2) = _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch1, initialEpoch2, lockUpEpochs1, lockUpEpochs2, amount1, amount2
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        // assert that second stake power change epochs after next epoch are zero
        uint16 nextEpoch = uint16(currentEpoch + 1);
        for (uint256 i; i < powerChanges2.length; ++i) {
            int104 power = vePWN.workaround_getTotalEpochPower(powerChanges2[i].epoch);
            if (powerChanges2[i].epoch > nextEpoch) {
                assertEq(power, 0);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldUpdateTotalPowerChanges(
        uint256 _initialEpoch1, uint256 _initialEpoch2,
        uint256 _lockUpEpochs1, uint256 _lockUpEpochs2,
        uint256 _amount1, uint256 _amount2
    ) external {
        (
            uint16 initialEpoch1, uint16 initialEpoch2,
            uint8 lockUpEpochs1, uint8 lockUpEpochs2,
            uint104 amount1, uint104 amount2
        ) = _boundMergeInputs(
            _initialEpoch1, _initialEpoch2, _lockUpEpochs1, _lockUpEpochs2, _amount1, _amount2
        );

        (TestPowerChangeEpoch[] memory powerChanges1, TestPowerChangeEpoch[] memory powerChanges2) = _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch1, initialEpoch2, lockUpEpochs1, lockUpEpochs2, amount1, amount2
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint16 nextEpoch = uint16(currentEpoch + 1);
        uint8 remainingEpochs = uint8(initialEpoch1 + lockUpEpochs1 - nextEpoch);
        // assert that all power changes before next epoch are unchanged
        TestPowerChangeEpoch[] memory immutablePowerChanges = _mergePowerChanges(powerChanges1, powerChanges2);
        for (uint256 i; i < immutablePowerChanges.length; ++i) {
            if (immutablePowerChanges[i].epoch < nextEpoch) {
                int104 power = vePWN.workaround_getTotalEpochPower(immutablePowerChanges[i].epoch);
                assertEq(power, immutablePowerChanges[i].powerChange);
            }
        }
        // assert that next epoch power is updated
        int104 nextEpochPower = vePWN.exposed_power(int104(amount2), remainingEpochs);
        if (initialEpoch2 < nextEpoch && initialEpoch2 + lockUpEpochs2 > currentEpoch) {
            nextEpochPower -= vePWN.exposed_power(
                int104(amount2), uint8(initialEpoch2 + lockUpEpochs2 - currentEpoch)
            );
        }
        if (initialEpoch1 == nextEpoch) {
            nextEpochPower += vePWN.exposed_power(int104(amount1), remainingEpochs);
        } else if ((initialEpoch1 + lockUpEpochs1 - nextEpoch) % EPOCHS_IN_YEAR == 0) {
            nextEpochPower += vePWN.exposed_powerDecrease(int104(amount1), remainingEpochs);
        }
        assertEq(vePWN.workaround_getTotalEpochPower(nextEpoch), nextEpochPower);
        // assert that all power changes after next epoch are updated
        TestPowerChangeEpoch[] memory mergedPowerChanges = _createPowerChangesArray(
            nextEpoch, remainingEpochs, amount1 + amount2
        );
        for (uint256 i; i < mergedPowerChanges.length; ++i) {
            if (mergedPowerChanges[i].epoch > nextEpoch) {
                int104 power = vePWN.workaround_getTotalEpochPower(mergedPowerChanges[i].epoch);
                assertEq(power, mergedPowerChanges[i].powerChange);
            }
        }
        // assert that all power changes sum to zero
        _assertTotalPowerChangesSumToZero(mergedPowerChanges[mergedPowerChanges.length - 1].epoch);
    }

    function test_shouldNotDeleteOriginalStakes() external {
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs, lockUpEpochs, amount, amount
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        bytes32 stakeValue1 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId1));
        assertEq(stakeValue1.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue1.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue1.maskUint104(16 + 8), amount); // amount
        bytes32 stakeValue2 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId2));
        assertEq(stakeValue2.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue2.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue2.maskUint104(16 + 8), amount); // amount
    }

    function test_shouldBurnOriginalStakedPWNTokens() external {
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs, lockUpEpochs, amount, amount
        );

        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId1));
        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId2));

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldCreateNewStake(uint256 _lockUpEpochs, uint256 _amount1, uint256 _amount2) external {
        lockUpEpochs = uint8(bound(
            _lockUpEpochs, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_YEAR
        ));
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs, lockUpEpochs, amount1, amount2
        );

        uint256 newStakeId = vePWN.lastStakeId() + 1;
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, newStakeId)
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint8 newLockUpEpochs = lockUpEpochs - uint8(currentEpoch + 1 - initialEpoch);
        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId));
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1, "initialEpoch mismatch"); // initialEpoch
        assertEq(stakeValue.maskUint8(16), newLockUpEpochs, "lockUpEpochs mismatch"); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount1 + amount2, "amount mismatch"); // amount
    }

    function testFuzz_shouldEmit_StakeMerged(uint256 _lockUpEpochs, uint256 _amount1, uint256 _amount2) external {
        lockUpEpochs = uint8(bound(
            _lockUpEpochs, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_YEAR
        ));
        uint8 newLockUpEpochs = lockUpEpochs - uint8(currentEpoch + 1 - initialEpoch);
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockTwoStakes(
            staker, stakeId1, stakeId2, initialEpoch, initialEpoch, lockUpEpochs, lockUpEpochs, amount1, amount2
        );

        vm.expectEmit();
        emit StakeMerged(stakeId1, stakeId2, staker, amount1 + amount2, newLockUpEpochs, vePWN.lastStakeId() + 1);

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

    uint256 public amount = 100;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = uint16(currentEpoch) - 20;
    uint16 public newInitialEpoch = uint16(currentEpoch) + 1;
    uint8 public lockUpEpochs = 23;
    uint256 public additionalAmount = 100;
    uint256 public additionalEpochs = 20;

    event StakeIncreased(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 additionalAmount,
        uint256 newAmount,
        uint256 additionalEpochs,
        uint256 newEpochs,
        uint256 newStakeId
    );

    function setUp() override public {
        super.setUp();

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));
    }

    function _boundIncreaseInputs(
        uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) private view returns (uint8, uint256, uint256, uint8) {
        uint8 lockUpEpochs_ = uint8(bound(_lockUpEpochs, 1, 130));
        uint8 remainingLockup = initialEpoch + lockUpEpochs_ <= currentEpoch
            ? 0
            : uint8(initialEpoch + lockUpEpochs_ - currentEpoch) - 1;
        uint256 additionalAmount_ = bound(_additionalAmount, 0, type(uint88).max / 100) * 100;
        uint256 additionalEpochs_ = bound(
            _additionalEpochs,
            Math.max(1 * EPOCHS_IN_YEAR, remainingLockup) - remainingLockup,
            Math.max(5 * EPOCHS_IN_YEAR, remainingLockup) - remainingLockup
        );
        additionalEpochs_ = additionalEpochs_ + remainingLockup > 5 * EPOCHS_IN_YEAR
            ? 10 * EPOCHS_IN_YEAR - remainingLockup
            : additionalEpochs_;

        return (lockUpEpochs_, additionalAmount_, additionalEpochs_, remainingLockup + uint8(additionalEpochs_));
    }


    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldFail_whenCallerNotStakeBeneficiary() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount), false);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldFail_whenNothingToIncrease() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectRevert(abi.encodeWithSelector(Error.NothingToIncrease.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, 0);
    }

    function testFuzz_shouldFail_whenIncorrectAdditionalAmount(uint256 _additionalAmount) external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        // over max
        additionalAmount = bound(_additionalAmount, uint256(type(uint88).max) + 1, type(uint256).max / 100);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount * 100, additionalEpochs);

        // not a multiple of 100
        additionalAmount = bound(_additionalAmount, 1, uint256(type(uint88).max) - 1);
        additionalAmount += additionalAmount % 100 == 0 ? 1 : 0;
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function testFuzz_shouldFail_whenIncorrectdAdditionalEpochs(uint256 _additionalEpochs) external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        uint8 remainingLockup = uint8(initialEpoch + lockUpEpochs - currentEpoch) - 1;
        // out of bounds
        additionalEpochs = bound(_additionalEpochs, 10 * EPOCHS_IN_YEAR + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // under a year
        additionalEpochs = bound(_additionalEpochs, 1, EPOCHS_IN_YEAR - remainingLockup - 1);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 5 & under 10 years
        additionalEpochs = bound(
            _additionalEpochs, 5 * EPOCHS_IN_YEAR - remainingLockup + 1, 10 * EPOCHS_IN_YEAR - remainingLockup - 1
        );
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 10 years
        additionalEpochs = bound(
            _additionalEpochs, 10 * EPOCHS_IN_YEAR - remainingLockup + 1, 10 * EPOCHS_IN_YEAR
        );
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldClearRemainingTotalPowerChanges_whenNonZeroAdditionalEpochs(
        uint16 _initialEpoch, uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - 130, currentEpoch + 1));
        (lockUpEpochs, additionalAmount, additionalEpochs, ) =
            _boundIncreaseInputs(_lockUpEpochs, _additionalAmount, _additionalEpochs);
        vm.assume(additionalEpochs + additionalAmount > 0);
        vm.assume(additionalEpochs % 13 > 0);
        TestPowerChangeEpoch[] memory powerChanges =
            _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        // assert that all power change epochs after next epoch are zero
        uint16 nextEpoch = uint16(currentEpoch + 1);
        for (uint256 i; i < powerChanges.length; ++i) {
            int104 power = vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch);
            if (powerChanges[i].epoch > nextEpoch) {
                assertEq(power, 0);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldUpdateTotalPowerChanges(
        uint16 _initialEpoch, uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - 130, currentEpoch + 1));
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundIncreaseInputs(
            _lockUpEpochs, _additionalAmount, _additionalEpochs
        );
        vm.assume(additionalEpochs + additionalAmount > 0);
        TestPowerChangeEpoch[] memory powerChanges =
            _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        uint16 nextEpoch = uint16(currentEpoch + 1);
        // assert that all power changes before next epoch are unchanged
        for (uint256 i; i < powerChanges.length; ++i) {
            if (powerChanges[i].epoch < nextEpoch) {
                int104 power = vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch);
                assertEq(power, powerChanges[i].powerChange);
            }
        }
        // assert that next epoch power is updated
        int104 nextEpochPower = vePWN.exposed_power(int104(int256(amount + additionalAmount)), remainingLockup);
        if (initialEpoch < nextEpoch && initialEpoch + lockUpEpochs > currentEpoch) {
            nextEpochPower -= vePWN.exposed_power(
                int104(int256(amount)), uint8(initialEpoch + lockUpEpochs - currentEpoch)
            );
        }
        assertEq(vePWN.workaround_getTotalEpochPower(nextEpoch), nextEpochPower);
        // assert that all power changes after next epoch are updated
        TestPowerChangeEpoch[] memory increasedPowerChanges =
            _createPowerChangesArray(nextEpoch, remainingLockup, amount + additionalAmount);
        for (uint256 i; i < increasedPowerChanges.length; ++i) {
            if (increasedPowerChanges[i].epoch > nextEpoch) {
                int104 power = vePWN.workaround_getTotalEpochPower(increasedPowerChanges[i].epoch);
                assertEq(power, increasedPowerChanges[i].powerChange);
            }
        }
        // assert that all power changes sum to zero
        _assertTotalPowerChangesSumToZero(increasedPowerChanges[increasedPowerChanges.length - 1].epoch);
    }

    function testFuzz_shouldStoreNewStakeData(
        uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundIncreaseInputs(
            _lockUpEpochs, _additionalAmount, _additionalEpochs
        );
        vm.assume(additionalEpochs + additionalAmount > 0);

        _mockStake(staker, stakeId + 1, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId + 1, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(vePWN.lastStakeId()));
        assertEq(stakeValue.maskUint16(0), newInitialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), remainingLockup); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount + additionalAmount); // amount
    }

    function test_shouldNotDeleteStakeData() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), uint104(amount)); // amount
    }

    function test_shouldEmit_StakeIncreased() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectEmit();
        emit StakeIncreased(
            stakeId,
            staker,
            additionalAmount,
            additionalAmount + amount,
            additionalEpochs,
            additionalEpochs + lockUpEpochs + initialEpoch - currentEpoch - 1,
            vePWN.lastStakeId() + 1
        );

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldBurnOldStakedPWNToken() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldMintNewStakedPWNToken() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectCall(stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function testFuzz_shouldTransferAdditionalPWNTokens(uint256 _additionalAmount) external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

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
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

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

    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 400;
    uint8 public lockUpEpochs = 13;

    event StakeWithdrawn(uint256 indexed stakeId, address indexed staker, uint256 amount);

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));
        vm.mockCall(stakedPWN, abi.encodeWithSignature("burn(uint256)"), abi.encode(""));
        vm.mockCall(pwnToken, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
    }


    function test_shouldFail_whenStakeDoesNotExist() external {
        vm.expectRevert();
        vm.prank(staker);
        vePWN.withdrawStake(stakeId + 1);
    }

    function testFuzz_shouldFail_whenCallerIsNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
        vePWN.withdrawStake(stakeId);
    }

    function test_shouldFail_whenCallerIsNotStakeOwner() external {
        _mockStake(staker, stakeId + 1, initialEpoch, lockUpEpochs, uint104(amount), false);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(staker);
        vePWN.withdrawStake(stakeId + 1);
    }

    function testFuzz_shouldFail_whenStillLock(uint256 _currentEpoch) external {
        currentEpoch = bound(_currentEpoch, 1, 139);
        vm.mockCall(epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch));

        uint256 runningStakeId = stakeId + 132;

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", runningStakeId), abi.encode(staker));
        _mockStake(
            staker,
            runningStakeId,
            10,
            130,
            uint104(amount)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.WithrawalBeforeLockUpEnd.selector));
        vm.prank(staker);
        vePWN.withdrawStake(runningStakeId);
    }

    function testFuzz_shouldPass_whenUnlocked(uint256 _currentEpoch) external {
        currentEpoch = bound(_currentEpoch, 140, 200);
        vm.mockCall(epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch));

        uint256 runningStakeId = stakeId + 132;

        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", runningStakeId), abi.encode(staker));
        _mockStake(
            staker,
            runningStakeId,
            10,
            130,
            uint104(amount)
        );

        vm.prank(staker);
        vePWN.withdrawStake(runningStakeId);
    }

    function test_shouldNotDeleteStakeData() external {
        vm.prank(staker);
        vePWN.withdrawStake(stakeId);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // lockUpEpochs
        assertEq(stakeValue.maskUint104(16 + 8), amount); // amount
    }

    function test_shouldEmit_StakeWithdrawn() external {
        vm.expectEmit();
        emit StakeWithdrawn(stakeId, staker, amount);

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
|*  # CLAIM STAKE POWER                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Stake_ClaimStakePower_Test is VoteEscrowedPWN_Stake_Test  {

    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 400;
    uint8 public lockUpEpochs = 13;
    address public currentBeneficiary = makeAddr("currentBeneficiary");

    event StakePowerClaimed(
        uint256 indexed stakeId,
        address indexed originalBeneficiary,
        address indexed newBeneficiary
    );

    function test_shouldFail_whenCallerIsCurrentBeneficiary() external {
        _mockStake(currentBeneficiary, stakeId, initialEpoch, lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        vm.expectRevert(abi.encodeWithSelector(Error.ClaimStakePowerFromSelf.selector));
        vm.prank(staker);
        vePWN.claimStakePower(stakeId, staker);
    }

    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        _mockStake(currentBeneficiary, stakeId, initialEpoch, lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
        vePWN.claimStakePower(stakeId, currentBeneficiary);
    }

    function test_shouldFail_whenProvidedAddressNotStakeBeneficiary() external {
        _mockStake(currentBeneficiary, stakeId, initialEpoch, lockUpEpochs, uint104(amount), false);
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeBeneficiary.selector));
        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);
    }

    function test_shouldRemoveStakeFromCurrentBeneficiary_whenSameEpoch() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch + 1), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        StakesInEpoch[] memory stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(currentBeneficiary);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[0].ids[0], stakeId);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);

        stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(currentBeneficiary);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[0].ids.length, 0);
    }

    function test_shouldRemoveStakeFromCurrentBeneficiary_whenNotSameEpoch() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        StakesInEpoch[] memory stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(currentBeneficiary);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[0].ids[0], stakeId);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);

        stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(currentBeneficiary);
        assertEq(stakesInEpochs.length, 2);
        assertEq(stakesInEpochs[0].epoch, currentEpoch);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[1].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[1].ids.length, 0);
    }

    function test_shouldAddStakeToNewBeneficiary_whenFirstStake() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch + 1), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        StakesInEpoch[] memory stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 0);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);

        stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[0].ids[0], stakeId);
    }

    function test_shouldAddStakeToNewBeneficiary_whenSameEpoch() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch + 1), lockUpEpochs, uint104(amount));
        _mockStake(staker, stakeId + 1, uint16(currentEpoch + 1), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        StakesInEpoch[] memory stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[0].ids[0], stakeId + 1);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);

        stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[0].ids.length, 2);
        assertEq(stakesInEpochs[0].ids[0], stakeId + 1);
        assertEq(stakesInEpochs[0].ids[1], stakeId);
    }

    function test_shouldAddStakeToNewBeneficiary_whenNotSameEpoch() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch), lockUpEpochs, uint104(amount));
        _mockStake(staker, stakeId + 1, uint16(currentEpoch), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        StakesInEpoch[] memory stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 1);
        assertEq(stakesInEpochs[0].epoch, currentEpoch);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[0].ids[0], stakeId + 1);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);

        stakesInEpochs = vePWN.exposed_beneficiaryOfStakes(staker);
        assertEq(stakesInEpochs.length, 2);
        assertEq(stakesInEpochs[0].epoch, currentEpoch);
        assertEq(stakesInEpochs[0].ids.length, 1);
        assertEq(stakesInEpochs[1].epoch, currentEpoch + 1);
        assertEq(stakesInEpochs[1].ids.length, 2);
        assertEq(stakesInEpochs[1].ids[0], stakeId + 1);
        assertEq(stakesInEpochs[1].ids[1], stakeId);
    }

    function test_shouldEmit_StakePowerClaimed() external {
        _mockStake(currentBeneficiary, stakeId, uint16(currentEpoch), lockUpEpochs, uint104(amount));
        _mockStake(staker, stakeId + 1, uint16(currentEpoch), lockUpEpochs, uint104(amount));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker));

        vm.expectEmit();
        emit StakePowerClaimed(stakeId, currentBeneficiary, staker);

        vm.prank(staker);
        vePWN.claimStakePower(stakeId, currentBeneficiary);
    }

}
