// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";
import { VoteEscrowedPWNStake } from "src/token/vePWN/VoteEscrowedPWNStake.sol";

import { VoteEscrowedPWNHarness, StakesInEpoch } from "test/harness/VoteEscrowedPWNHarness.sol";
import { Base_Test } from "test/Base.t.sol";

abstract contract VoteEscrowedPWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    uint8 public constant EPOCHS_IN_YEAR = 13;
    bytes32 public constant STAKES_SLOT = bytes32(uint256(4));
    bytes32 public constant BENEFICIARY_OF_STAKES = bytes32(uint256(5));
    bytes32 public constant LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT = bytes32(uint256(6));

    VoteEscrowedPWNHarness public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public staker = makeAddr("staker");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch));
        vm.mockCall(pwnToken, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
        vm.mockCall(pwnToken, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
        vm.mockCall(stakedPWN, abi.encodeWithSignature("mint(address,uint256)"), abi.encode(0));
        vm.mockCall(stakedPWN, abi.encodeWithSignature("burn(uint256)"), abi.encode(0));

        vePWN = new VoteEscrowedPWNHarness();
        vm.store(address(vePWN), bytes32(0), bytes32(0)); // workaround to enable initializers
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock
        });
    }


    struct TestPowerChangeEpoch {
        uint16 epoch;
        int104 powerChange;
    }

    function _createPowerChangesArray(uint256 _lockUpEpochs, uint256 _amount)
        internal
        returns (TestPowerChangeEpoch[] memory)
    {
        return _createPowerChangesArray(uint16(currentEpoch + 1), _lockUpEpochs, _amount);
    }

    function _createPowerChangesArray(uint16 _initialEpoch, uint256 _lockUpEpochs, uint256 _amount)
        internal
        returns (TestPowerChangeEpoch[] memory)
    {
        return _createPowerChangesArray(_initialEpoch, type(uint16).max, _lockUpEpochs, _amount);
    }

    // solhint-disable-next-line var-name-mixedcase
    TestPowerChangeEpoch[] private helper_powerChanges;
    function _createPowerChangesArray(uint16 _initialEpoch, uint16 _finalEpoch, uint256 _lockUpEpochs, uint256 _amount)
        internal
        returns (TestPowerChangeEpoch[] memory)
    {
        if (_initialEpoch >= _finalEpoch) {
            return new TestPowerChangeEpoch[](0);
        }

        uint16 epoch = _initialEpoch;
        uint8 remainingLockup = uint8(_lockUpEpochs);
        int104 int104amount = int104(int256(_amount));
        int104 powerChange = vePWN.exposed_power(int104amount, remainingLockup);

        helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        while (remainingLockup > 0) {
            uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(remainingLockup);
            remainingLockup -= epochsToNextPowerChange;
            epoch += epochsToNextPowerChange;
            if (epoch >= _finalEpoch) {
                break;
            }
            helper_powerChanges.push(
                TestPowerChangeEpoch({
                    epoch: epoch,
                    powerChange: vePWN.exposed_powerDecrease(int104amount, remainingLockup)
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


    // expects storage to be empty
    function _storeTotalPowerChanges(TestPowerChangeEpoch[] memory powerChanges) internal {
        for (uint256 i; i < powerChanges.length; ++i) {
            vePWN.workaround_storeTotalEpochPower(powerChanges[i].epoch, powerChanges[i].powerChange);
        }
    }

    function _mockStake(
        address _staker, uint256 _stakeId, uint16 _initialEpoch, uint8 _lockUpEpochs, uint104 _amount
    ) internal returns (TestPowerChangeEpoch[] memory powerChanges) {
        return _mockStake(_staker, _staker, _stakeId, _initialEpoch, _lockUpEpochs, _amount);
    }

    function _mockStake(
        address _staker, address _beneficiary, uint256 _stakeId, uint16 _initialEpoch, uint8 _lockUpEpochs, uint104 _amount
    ) internal returns (TestPowerChangeEpoch[] memory powerChanges) {
        _storeStake(_stakeId, _initialEpoch, _lockUpEpochs, _amount);
        powerChanges = _createPowerChangesArray(_initialEpoch, _lockUpEpochs, _amount);
        _storeTotalPowerChanges(powerChanges);
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", _stakeId), abi.encode(_staker));
        _mockStakeBeneficiary(_beneficiary, _stakeId, _initialEpoch);
    }

    function _mockTwoStakes(
        address _staker,
        uint256 _stakeId1, uint256 _stakeId2,
        uint16 _initialEpoch1, uint16 _initialEpoch2,
        uint8 _lockUpEpochs1, uint8 _lockUpEpochs2,
        uint104 _amount1, uint104 _amount2
    ) internal returns (TestPowerChangeEpoch[] memory powerChanges1, TestPowerChangeEpoch[] memory powerChanges2) {
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", _stakeId1), abi.encode(_staker));
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", _stakeId2), abi.encode(_staker));
        _storeStake(_stakeId1, _initialEpoch1, _lockUpEpochs1, _amount1);
        _storeStake(_stakeId2, _initialEpoch2, _lockUpEpochs2, _amount2);
        powerChanges1 = _createPowerChangesArray(_initialEpoch1, _lockUpEpochs1, _amount1);
        powerChanges2 = _createPowerChangesArray(_initialEpoch2, _lockUpEpochs2, _amount2);
        _storeTotalPowerChanges(powerChanges1);
        _storeTotalPowerChanges(powerChanges2);

        vePWN.workaround_addStakeToBeneficiary(
            _staker, _makeStakesInEpoch(_initialEpoch1, _initialEpoch2, _stakeId1, _stakeId2)
        );
    }

    function _makeStakesInEpoch(
        uint16 _epoch1, uint16 _epoch2, uint256 _stakeId1, uint256 _stakeId2
    ) private pure returns (StakesInEpoch[] memory) {
        bool sameEpoch = _epoch1 == _epoch2;
        bool sorted = _epoch1 <= _epoch2;
        StakesInEpoch[] memory stakesInEpochs = new StakesInEpoch[](sameEpoch ? 1 : 2);
        uint48[] memory ids = new uint48[](sameEpoch ? 2 : 1);
        ids[0] = uint48(sorted ? _stakeId1 : _stakeId2);
        if (sameEpoch) {
            ids[1] = uint48(sorted ? _stakeId2 : _stakeId1);
        }
        stakesInEpochs[0].epoch = sorted ? _epoch1 : _epoch2;
        stakesInEpochs[0].ids = ids;
        if (!sameEpoch) {
            ids = new uint48[](2);
            ids[0] = uint48(_stakeId1);
            ids[1] = uint48(_stakeId2);
            stakesInEpochs[1].epoch = sorted ? _epoch2 : _epoch1;
            stakesInEpochs[1].ids = ids;
        }
        return stakesInEpochs;
    }

    function _mockStakeBeneficiary(address _staker, uint256 _stakeId, uint16 _epoch) internal {
        StakesInEpoch[] memory stakesInEpochs = new StakesInEpoch[](1);
        uint48[] memory ids = new uint48[](1);
        ids[0] = uint48(_stakeId);
        stakesInEpochs[0].epoch = _epoch;
        stakesInEpochs[0].ids = ids;
        vePWN.workaround_addStakeToBeneficiary(_staker, stakesInEpochs);
    }

    function _storeStake(uint256 _stakeId, uint16 _initialEpoch, uint8 _lockUpEpochs, uint104 _amount) internal {
        bytes memory rawStakeData = abi.encodePacked(uint128(0), _amount, _lockUpEpochs, _initialEpoch);
        vm.store(address(vePWN), STAKES_SLOT.withMappingKey(_stakeId), abi.decode(rawStakeData, (bytes32)));
    }

    // bound

    function _boundAmount(uint256 seed) internal pure returns (uint256) {
        return bound(seed, 1, 1e24) * 100;
    }

    function _boundLockUpEpochs(uint256 seed) internal pure returns (uint8) {
        uint8 lockUpEpochs = uint8(bound(seed, EPOCHS_IN_YEAR, 10 * EPOCHS_IN_YEAR));
        return lockUpEpochs > 5 * EPOCHS_IN_YEAR ? 10 * EPOCHS_IN_YEAR : lockUpEpochs;
    }

    function _boundRemainingLockups(uint256 seed) internal pure returns (uint8) {
        return uint8(bound(seed, 1, 10 * EPOCHS_IN_YEAR));
    }

    // assert

    function _assertTotalPowerChangesSumToZero(uint256 lastEpoch) internal {
        int104 sum;
        for (uint256 i; i <= lastEpoch; ++i) {
            sum += vePWN.workaround_getTotalEpochPower(i);
        }
        assertEq(sum, 0);
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Helpers_Test is VoteEscrowedPWN_Test {

    function testFuzzHelper_storeStake(
        uint256 _stakeId, uint16 _initialEpoch, uint8 _lockUpEpochs, uint104 _amount
    ) external {
        _initialEpoch = uint16(bound(_initialEpoch, 1, type(uint16).max / 2));

        _storeStake(_stakeId, _initialEpoch, _lockUpEpochs, _amount);
        vm.mockCall(address(stakedPWN), abi.encodeWithSignature("ownerOf(uint256)", _stakeId), abi.encode(staker));

        VoteEscrowedPWNStake.StakeData memory stake = vePWN.getStake(_stakeId);
        assertEq(stake.initialEpoch, _initialEpoch);
        assertEq(stake.lockUpEpochs, _lockUpEpochs);
        assertEq(stake.amount, _amount);
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

    // powerChangeMultipliers

    function testFuzz_powerChangeMultipliers_initialPower(uint256 amount, uint8 lockUpEpochs) external {
        amount = _boundAmount(amount);
        lockUpEpochs = uint8(bound(lockUpEpochs, 1, 130));

        int104[] memory yearMultiplier = new int104[](6);
        yearMultiplier[0] = 100;
        yearMultiplier[1] = 115;
        yearMultiplier[2] = 130;
        yearMultiplier[3] = 150;
        yearMultiplier[4] = 175;
        yearMultiplier[5] = 350;

        int104 power = vePWN.exposed_power(int104(uint104(amount)), lockUpEpochs);

        int104 multiplier;
        if (lockUpEpochs > EPOCHS_IN_YEAR * 5)
            multiplier = yearMultiplier[5];
        else
            multiplier = yearMultiplier[
                lockUpEpochs / EPOCHS_IN_YEAR - (lockUpEpochs % EPOCHS_IN_YEAR == 0 ? 1 : 0)
            ];
        assertEq(power, int104(uint104(amount)) * multiplier / 100);
    }

    function testFuzz_powerChangeMultipliers_decreasePower(uint256 amount, uint8 lockUpEpochs) external {
        amount = _boundAmount(amount);
        lockUpEpochs = uint8(bound(lockUpEpochs, 1, 130));

        int104[] memory yearMultiplier = new int104[](6);
        yearMultiplier[0] = 15;
        yearMultiplier[1] = 15;
        yearMultiplier[2] = 20;
        yearMultiplier[3] = 25;
        yearMultiplier[4] = 175;
        yearMultiplier[5] = 0;

        int104 power = vePWN.exposed_powerDecrease(int104(uint104(amount)), lockUpEpochs);

        int104 multiplier;
        if (lockUpEpochs > EPOCHS_IN_YEAR * 5)
            multiplier = yearMultiplier[5];
        else if (lockUpEpochs == 0)
            multiplier = 100;
        else
            multiplier = yearMultiplier[
                lockUpEpochs / EPOCHS_IN_YEAR - (lockUpEpochs % EPOCHS_IN_YEAR == 0 ? 1 : 0)
            ];
        assertEq(power, -int104(uint104(amount)) * multiplier / 100);
    }

    function test_powerChangeMultipliers_powerChangesShouldSumToZero(uint8 remainingLockup) external {
        vm.assume(remainingLockup > 0);

        int104 amount = 100;
        int104 sum = vePWN.exposed_power(amount, remainingLockup);
        while (remainingLockup > 0) {
            uint8 epochsToNextPowerChange = vePWN.exposed_epochsToNextPowerChange(remainingLockup);
            remainingLockup -= epochsToNextPowerChange;
            sum += vePWN.exposed_powerDecrease(amount, remainingLockup);
        }

        assertEq(sum, 0);
    }

}
