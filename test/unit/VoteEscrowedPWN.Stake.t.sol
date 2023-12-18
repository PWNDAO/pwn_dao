// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { Error } from "src/lib/Error.sol";

import { BitMaskLib } from "../utils/BitMaskLib.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

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
        vePWN.createStake({ amount: 0, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: 99, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: uint256(type(uint88).max) + 1, lockUpEpochs: EPOCHS_IN_PERIOD });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidAmount.selector));
        vePWN.createStake({ amount: 101, lockUpEpochs: EPOCHS_IN_PERIOD });
    }

    function test_shouldFail_whenInvalidLockUpEpochs() external {
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vePWN.createStake({ amount: 100, lockUpEpochs: EPOCHS_IN_PERIOD - 1 });

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
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
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), amount); // amount
    }

    function testFuzz_shouldStoreStakerPowerChanges(uint256 _lockUpEpochs, uint256 _amount) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        amount = _boundAmount(_amount);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            int104 powerChange = vePWN.workaround_getStakerEpochPower(staker, powerChanges[i].epoch);
            assertEq(powerChange, powerChanges[i].powerChange);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function testFuzz_shouldStoreTotalPowerChanges(uint256 _lockUpEpochs, uint256 _amount) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        amount = _boundAmount(_amount);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            int104 powerChange = vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch);
            assertEq(powerChange, powerChanges[i].powerChange);
        }

        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function testFuzz_shouldUpdateStakerPowerChanges(uint256 _lockUpEpochs, uint256 _amount) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        amount = _boundAmount(_amount);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            int104 powerChange = vePWN.workaround_getStakerEpochPower(staker, powerChanges[i].epoch);
            assertEq(powerChange, powerChanges[i].powerChange * 2);
        }

        _assertPowerChangesSumToZero(staker);
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

    function testFuzz_shouldStorePowerChangeEpochs(uint256 _lockUpEpochs) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(staker)[i]);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function testFuzz_shouldNotUpdatePowerChangeEpochs_whenSameEpochs(uint256 _lockUpEpochs) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });

        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(lockUpEpochs, amount);
        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(staker)[i]);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function test_shouldKeepPowerChangeEpochsSorted() external {
        lockUpEpochs = 130;

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        TestPowerChangeEpoch[] memory powerChanges1 = _createPowerChangesArray(lockUpEpochs, amount);

        currentEpoch += 3;
        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
        TestPowerChangeEpoch[] memory powerChanges2 = _createPowerChangesArray(lockUpEpochs, amount);

        assertEq(powerChanges1.length, powerChanges2.length);
        for (uint256 i; i < powerChanges1.length; ++i) {
            assertEq(powerChanges1[i].epoch, vePWN.powerChangeEpochs(staker)[2 * i]);
            assertEq(powerChanges2[i].epoch, vePWN.powerChangeEpochs(staker)[2 * i + 1]);
        }

        _assertPowerChangesSumToZero(staker);
    }

    function test_shouldEmit_StakeCreated() external {
        vm.expectEmit();
        emit StakeCreated(vePWN.lastStakeId() + 1, staker, amount, lockUpEpochs);

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldTransferPWNTokens() external {
        vm.expectCall(
            pwnToken,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", staker, address(vePWN), amount)
        );

        vm.prank(staker);
        vePWN.createStake({ amount: amount, lockUpEpochs: lockUpEpochs });
    }

    function test_shouldMintStakedPWNToken() external {
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

    uint256 public amount = 100 ether;
    uint256 public stakeId = 69;
    uint16 public initialEpoch = 543;
    uint8 public lockUpEpochs = 13;

    event StakeSplit(
        uint256 indexed stakeId, address indexed staker, uint256 splitAmount, uint256 newStakeId1, uint256 newStakeId2
    );

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker)
        );
    }


    function testFuzz_shouldFail_whenCallerNotStakeOwner(address caller) external {
        vm.assume(caller != staker);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
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
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), amount - splitAmount); // amount

        stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId2));
        assertEq(stakeValue.maskUint16(0), initialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), lockUpEpochs); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), splitAmount); // amount
    }

    function test_shouldDeleteOriginalStake() external {
        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), 0); // initialEpoch
        assertEq(stakeValue.maskUint8(16), 0); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), 0); // amount
    }

    function test_shouldNotUpdatePowerChanges() external {
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(
            initialEpoch, lockUpEpochs, uint104(amount)
        );

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);

        uint256 length = vePWN.workaround_stakerPowerChangeEpochsLength(staker);
        assertEq(powerChanges.length, length);
        _assertPowerChangesSumToZero(staker);
        for (uint256 i; i < length; ++i) {
            _assertEpochPowerAndPosition(staker, i, powerChanges[i].epoch, powerChanges[i].powerChange);
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }
    }

    function test_shouldEmit_StakeSplit() external {
        vm.expectEmit();
        emit StakeSplit(stakeId, staker, amount / 4, vePWN.lastStakeId() + 1, vePWN.lastStakeId() + 2);

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);
    }

    function test_shouldBurnOriginalStakedPWNToken() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId)
        );

        vm.prank(staker);
        vePWN.splitStake(stakeId, amount / 4);
    }

    function test_shouldMintNewStakedPWNTokens() external {
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1)
        );
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 2)
        );

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
    uint8 public remainingLockup = 30;

    event StakeMerged(
        uint256 indexed stakeId1,
        uint256 indexed stakeId2,
        address indexed staker,
        uint256 amount,
        uint256 remainingLockup,
        uint256 newStakeId
    );


    function test_shouldFail_whenCallerNotFirstStakeOwner() external {
        _mockStake(makeAddr("notOwner"), stakeId1, initialEpoch, remainingLockup, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function test_shouldFail_whenCallerNotSecondStakeOwner() external {
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup, amount);
        _mockStake(makeAddr("notOwner"), stakeId2, initialEpoch, remainingLockup, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenFirstRemainingLockupSmallerThanSecond(uint256 seed) external {
        uint8 remainingLockup1 = uint8(bound(seed, 1, 10 * EPOCHS_IN_PERIOD - 1));
        uint8 remainingLockup2 = uint8(bound(seed, remainingLockup1 + 1, 10 * EPOCHS_IN_PERIOD));
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup1, amount);
        _mockStake(staker, stakeId2, initialEpoch, remainingLockup2, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.LockUpPeriodMismatch.selector));
        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);
    }

    function testFuzz_shouldFail_whenBothStakesLockupEnded(uint8 _remainingLockup) external {
        remainingLockup = uint8(bound(_remainingLockup, 1, 21));
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup, amount);
        _mockStake(staker, stakeId2, initialEpoch, remainingLockup, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.LockUpPeriodMismatch.selector));
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
        uint16 initialEpoch1 = uint16(bound(
            _initialEpoch1, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)
        ));
        uint16 initialEpoch2 = uint16(bound(
            _initialEpoch2, uint16(currentEpoch + 2 - maxLockup), uint16(currentEpoch + 1)
        ));
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
        _storeStake(stakeId1, initialEpoch1, remainingLockup1, amount1);
        _storeStake(stakeId2, initialEpoch2, remainingLockup2, amount2);
        TestPowerChangeEpoch[] memory powerChanges1 = _createPowerChangesArray(
            initialEpoch1, remainingLockup1, amount1
        );
        TestPowerChangeEpoch[] memory powerChanges2 = _createPowerChangesArray(
            initialEpoch2, remainingLockup2, amount2
        );
        TestPowerChangeEpoch[] memory originalPowerChanges = _mergePowerChanges(powerChanges1, powerChanges2);
        _storePowerChanges(staker, originalPowerChanges);

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint16 newInitialEpoch = uint16(currentEpoch) + 1;
        uint8 newRemainingLockup = remainingLockup1 - uint8(newInitialEpoch - initialEpoch1);
        // merge unchanged power changes 1 with immutable power changes 2
        TestPowerChangeEpoch[] memory mergedPowerChanges = _mergePowerChanges(
            powerChanges1, _createPowerChangesArray(initialEpoch2, newInitialEpoch, remainingLockup2, amount2)
        );
        // merge with new power changes 2
        mergedPowerChanges = _mergePowerChanges(
            mergedPowerChanges, _createPowerChangesArray(newInitialEpoch, newRemainingLockup, amount2)
        );
        // remove existing power from stake 2
        if (newInitialEpoch > initialEpoch2 && initialEpoch2 + remainingLockup2 > currentEpoch) {
            TestPowerChangeEpoch[] memory adjustingPowerChange = new TestPowerChangeEpoch[](1);
            adjustingPowerChange[0].epoch = newInitialEpoch;
            adjustingPowerChange[0].powerChange = -vePWN.exposed_initialPower(
                int104(amount2), remainingLockup2 - uint8(newInitialEpoch - initialEpoch2) + 1
            );
            mergedPowerChanges = _mergePowerChanges(mergedPowerChanges, adjustingPowerChange);
        }

        for (uint256 i; i < mergedPowerChanges.length; ++i) {
            _assertEpochPowerAndPosition(staker, i, mergedPowerChanges[i].epoch, mergedPowerChanges[i].powerChange);
            assertEq(
                vePWN.workaround_getTotalEpochPower(mergedPowerChanges[i].epoch),
                mergedPowerChanges[i].powerChange
            );
        }
        _assertPowerChangesSumToZero(staker);
        _assertTotalPowerChangesSumToZero(mergedPowerChanges[mergedPowerChanges.length - 1].epoch);
    }

    function test_shouldDeleteOriginalStakes() external {
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup, amount);
        _mockStake(staker, stakeId2, initialEpoch, remainingLockup, amount);

        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId1));
        vm.expectCall(stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId2));

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        bytes32 stakeValue1 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId1));
        assertEq(stakeValue1, bytes32(0));
        bytes32 stakeValue2 = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId2));
        assertEq(stakeValue2, bytes32(0));
    }

    function testFuzz_shouldCreateNewStake(uint256 _remainingLockup, uint256 _amount1, uint256 _amount2) external {
        remainingLockup = uint8(bound(
            _remainingLockup, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_PERIOD
        ));
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup, amount1);
        _mockStake(staker, stakeId2, initialEpoch, remainingLockup, amount2);

        uint256 newStakeId = vePWN.lastStakeId() + 1;
        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, newStakeId)
        );

        vm.prank(staker);
        vePWN.mergeStakes(stakeId1, stakeId2);

        uint8 newRemainingLockup = remainingLockup - uint8(currentEpoch + 1 - initialEpoch);
        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(newStakeId));
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1, "initialEpoch mismatch"); // initialEpoch
        assertEq(stakeValue.maskUint8(16), newRemainingLockup, "remainingLockup mismatch"); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), amount1 + amount2, "amount mismatch"); // amount
    }

    function testFuzz_shouldEmit_StakeMerged(uint256 _remainingLockup, uint256 _amount1, uint256 _amount2) external {
        remainingLockup = uint8(bound(
            _remainingLockup, uint16(currentEpoch) + 2 - initialEpoch, 10 * EPOCHS_IN_PERIOD
        ));
        uint8 newRemainingLockup = remainingLockup - uint8(currentEpoch + 1 - initialEpoch);
        uint104 amount1 = uint104(_boundAmount(_amount1));
        uint104 amount2 = uint104(_boundAmount(_amount2));
        _mockStake(staker, stakeId1, initialEpoch, remainingLockup, amount1);
        _mockStake(staker, stakeId2, initialEpoch, remainingLockup, amount2);

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
        uint256 additionalEpochs,
        uint256 newStakeId
    );

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(staker)
        );
    }

    function _boundInputs(
        uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) private view returns (uint8, uint256, uint256, uint8) {
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

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(caller);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldFail_whenNothingToIncrease() external {
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
        additionalEpochs = bound(_additionalEpochs, 10 * EPOCHS_IN_PERIOD + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // under a period
        additionalEpochs = bound(_additionalEpochs, 1, EPOCHS_IN_PERIOD - remainingLockup - 1);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 5 & under 10 periods
        additionalEpochs = bound(
            _additionalEpochs, 5 * EPOCHS_IN_PERIOD - remainingLockup + 1, 10 * EPOCHS_IN_PERIOD - remainingLockup - 1
        );
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);

        // over 10 periods
        additionalEpochs = bound(
            _additionalEpochs, 10 * EPOCHS_IN_PERIOD - remainingLockup + 1, 10 * EPOCHS_IN_PERIOD
        );
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidLockUpPeriod.selector));
        vm.prank(staker);
        vePWN.increaseStake(stakeId, 0, additionalEpochs);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldUpdatePowerChanges(
        uint16 _initialEpoch, uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - 130, currentEpoch + 1));
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundInputs(
            _lockUpEpochs, _additionalAmount, _additionalEpochs
        );
        vm.assume(additionalEpochs + additionalAmount > 0);

        _mockStake(staker, stakeId + 1, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId + 1, additionalAmount, additionalEpochs);

        // create immutable part of power changes
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(
            initialEpoch, newInitialEpoch, lockUpEpochs, amount
        );
        powerChanges = _mergePowerChanges( // merge with increased power changes
            powerChanges, _createPowerChangesArray(
                newInitialEpoch, remainingLockup + uint8(additionalEpochs), amount + additionalAmount
            )
        );
        // remove existing power from original stake
        if (initialEpoch <= uint16(currentEpoch) && initialEpoch + lockUpEpochs > uint16(currentEpoch)) {
            TestPowerChangeEpoch[] memory adjustingPowerChange = new TestPowerChangeEpoch[](1);
            adjustingPowerChange[0].epoch = newInitialEpoch;
            adjustingPowerChange[0].powerChange = -vePWN.exposed_initialPower(
                int104(int256(amount)), remainingLockup + 1
            );
            powerChanges = _mergePowerChanges(powerChanges, adjustingPowerChange);
        }

        // staker power changes
        for (uint256 i; i < powerChanges.length; ++i) {
            _assertEpochPowerAndPosition(staker, i, powerChanges[i].epoch, powerChanges[i].powerChange);
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }
        _assertPowerChangesSumToZero(staker);
        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function testFuzz_shouldStoreNewStakeData(
        uint8 _lockUpEpochs, uint256 _additionalAmount, uint256 _additionalEpochs
    ) external {
        uint8 remainingLockup;
        (lockUpEpochs, additionalAmount, additionalEpochs, remainingLockup) = _boundInputs(
            _lockUpEpochs, _additionalAmount, _additionalEpochs
        );
        vm.assume(additionalEpochs + additionalAmount > 0);

        _mockStake(staker, stakeId + 1, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId + 1, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(vePWN.lastStakeId()));
        assertEq(stakeValue.maskUint16(0), newInitialEpoch); // initialEpoch
        assertEq(stakeValue.maskUint8(16), remainingLockup + uint8(additionalEpochs)); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), amount + additionalAmount); // amount
    }

    function test_shouldDeleteOldStakeData() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue, bytes32(0));
    }

    function test_shouldEmit_StakeIncreased() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectEmit();
        emit StakeIncreased(stakeId, staker, additionalAmount, additionalEpochs, vePWN.lastStakeId() + 1);

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldBurnOldStakedPWNToken() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)", stakeId)
        );

        vm.prank(staker);
        vePWN.increaseStake(stakeId, additionalAmount, additionalEpochs);
    }

    function test_shouldMintNewStakedPWNToken() external {
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

        vm.expectCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)", staker, vePWN.lastStakeId() + 1)
        );

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

    event StakeWithdrawn(address indexed staker, uint256 amount);

    function setUp() override public {
        super.setUp();

        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(amount));

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

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
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
            staker, runningStakeId, uint16(currentEpoch) - lockUpEpochs + remainingLockup, lockUpEpochs, uint104(amount)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.WithrawalBeforeLockUpEnd.selector));
        vm.prank(staker);
        vePWN.withdrawStake(runningStakeId);
    }

    function test_shouldDeleteStakeData() external {
        vm.prank(staker);
        vePWN.withdrawStake(stakeId);

        bytes32 stakeValue = vm.load(address(vePWN), STAKES_SLOT.withMappingKey(stakeId));
        assertEq(stakeValue.maskUint16(0), 0); // initialEpoch
        assertEq(stakeValue.maskUint8(16), 0); // remainingLockup
        assertEq(stakeValue.maskUint104(16 + 8), 0); // amount
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

    event StakeTransferred(
        uint256 indexed stakeId, address indexed fromStaker, address indexed toStaker, uint256 amount
    );


    function test_shouldFail_whenCallerIsNotStakedPwnContract() external {
        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotStakedPWNContract.selector));
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

    function test_shouldFail_whenSenderNotStakeOwner() external {
        vm.mockCall(
            address(stakedPWN),
            abi.encodeWithSignature("ownerOf(uint256)", stakeId),
            abi.encode(makeAddr("notOwner"))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.NotStakeOwner.selector));
        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);
    }

    function testFuzz_shouldSkip_whenLockupPeriodEnded(uint16 _initialEpoch) external {
        initialEpoch = uint16(bound(_initialEpoch, 1, currentEpoch - remainingLockup + 1));
        _mockStake(from, stakeId, initialEpoch, remainingLockup, amount);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), initialEpoch);
        assertEq(stakeValue.maskUint8(16), remainingLockup);
    }

    function testFuzz_shouldUpdateStakeData(uint16 _initialEpoch) external {
        initialEpoch = uint16(bound(_initialEpoch, currentEpoch - remainingLockup + 2, currentEpoch));
        _mockStake(from, stakeId, initialEpoch, remainingLockup, amount);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        bytes32 stakeValue = vm.load(
            address(vePWN),
            STAKES_SLOT.withMappingKey(stakeId)
        );
        assertEq(stakeValue.maskUint16(0), currentEpoch + 1);
        assertEq(stakeValue.maskUint8(16), remainingLockup - (currentEpoch - initialEpoch + 1));
    }

    function testFuzz_shouldUpdatePowerChange_whenTransferredBeforeInitialEpoch(
        uint8 _remainingLockup, uint256 _amount
    ) external {
        remainingLockup = _boundLockUpEpochs(_remainingLockup);
        amount = uint104(_boundAmount(_amount));

        initialEpoch = uint16(currentEpoch) + 1;
        TestPowerChangeEpoch[] memory powerChanges = _mockStake(from, stakeId, initialEpoch, remainingLockup, amount);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);

        // check cliff transfer
        for (uint256 i; i < powerChanges.length; ++i) {
            _assertEpochPowerAndPosition(to, i, powerChanges[i].epoch, powerChanges[i].powerChange);
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }

        // check correct number of cliffs
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(from), 0);
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(to), powerChanges.length);

        // check power changes sum to zero
        _assertPowerChangesSumToZero(from);
        _assertPowerChangesSumToZero(to);
        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function testFuzz_shouldUpdatePowerChanges_whenTransferredAfterInitialEpoch(
        uint256 _amount, uint8 _lockUpEpochs, uint8 _remainingLockup
    ) external {
        amount = uint104(_boundAmount(_amount));
        uint8 lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        uint256 numberOfCliffs = uint256(lockUpEpochs) / uint256(EPOCHS_IN_PERIOD) + 1;
        numberOfCliffs += lockUpEpochs % EPOCHS_IN_PERIOD == 0 ? 0 : 1;
        remainingLockup = uint8(bound(_remainingLockup, 2, lockUpEpochs));

        initialEpoch = uint16(currentEpoch) - lockUpEpochs + remainingLockup;
        TestPowerChangeEpoch[] memory powerChanges = _mockStake(from, stakeId, initialEpoch, lockUpEpochs, amount);

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
                // skipping adjusting epochs (first)
                onSenderPart ? i : i - sendersNumberOfCliffs + 1 - adjustingReceiverIndex,
                powerChanges[i].epoch,
                powerChanges[i].powerChange
            );
            assertEq(vePWN.workaround_getTotalEpochPower(powerChanges[i].epoch), powerChanges[i].powerChange);
        }

        // add adjusting epoch to the number of cliffs
        ++sendersNumberOfCliffs;
        ++receiversNumberOfCliffs;

        // check adjusting epoch power
        int104 power = vePWN.exposed_initialPower(int104(amount), remainingLockup - 1);
        _assertEpochPowerAndPosition(to, 0, adjustingEpoch, power);
        if (adjustingReceiverIndex > 0) {
            // in case the last cliff has to be updated instead of created
            power -= vePWN.exposed_decreasePower(int104(amount), remainingLockup - 1);
        }
        _assertEpochPowerAndPosition(from, sendersNumberOfCliffs - 1, adjustingEpoch, -power);

        // check correct number of cliffs
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(from), sendersNumberOfCliffs);
        assertEq(vePWN.workaround_stakerPowerChangeEpochsLength(to), receiversNumberOfCliffs);

        // check power changes sum to zero
        _assertPowerChangesSumToZero(from);
        _assertPowerChangesSumToZero(to);
        _assertTotalPowerChangesSumToZero(powerChanges[powerChanges.length - 1].epoch);
    }

    function test_shouldEmit_StakeTransferred() external {
        _mockStake(from, stakeId, initialEpoch, remainingLockup, amount);

        vm.expectEmit();
        emit StakeTransferred(stakeId, from, to, amount);

        vm.prank(stakedPWN);
        vePWN.transferStake(from, to, stakeId);
    }

}
