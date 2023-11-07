// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { BasePWNTest } from "../BasePWNTest.t.sol";


contract VoteEscrowedPWN_RevenueExposed is VoteEscrowedPWN {

    function workaround_pushDaoRevenuePortionCheckpoint(uint16 initialEpoch, uint16 portion) external {
        daoRevenuePortion.push(PortionCheckpoint(initialEpoch, portion));
    }

    function workaround_getDaoRevenuePortionCheckpointAt(uint256 index) external returns (PortionCheckpoint memory) {
        return daoRevenuePortion[index];
    }

    function workaround_clearDaoRevenuePortionCheckpoints() external {
        delete daoRevenuePortion;
    }

    function workaround_getDaoRevenuePortionCheckpointsLength() external view returns (uint256) {
        return daoRevenuePortion.length;
    }


    struct StakerPowerInput {
        address staker;
        uint256 epoch;
    }
    StakerPowerInput public expectedStakerPowerInput;
    uint256 public stakerPowerReturn;
    function stakerPower(address staker, uint256 epoch) virtual public view override returns (uint256) {
        require(expectedStakerPowerInput.staker == staker, "stakerPower: staker");
        require(expectedStakerPowerInput.epoch == epoch, "stakerPower: epoch");
        return stakerPowerReturn;
    }

    struct TotalPowerAtInput {
        uint256 epoch;
    }
    TotalPowerAtInput public expectedTotalPowerAtInput;
    uint256 public totalPowerAtReturn;
    function totalPowerAt(uint256 epoch) virtual public view override returns (uint256) {
        require(expectedTotalPowerAtInput.epoch == epoch, "totalPowerAt: epoch");
        return totalPowerAtReturn;
    }


    // setters

    function _setStakerPowerInput(StakerPowerInput memory input) external {
        expectedStakerPowerInput = input;
    }

    function _setStakerPowerReturn(uint256 value) external {
        stakerPowerReturn = value;
    }

    function _setTotalPowerAtInput(TotalPowerAtInput memory input) external {
        expectedTotalPowerAtInput = input;
    }

    function _setTotalPowerAtReturn(uint256 value) external {
        totalPowerAtReturn = value;
    }

}

abstract contract VoteEscrowedPWN_Revenue_Test is BasePWNTest {

    bytes32 public constant LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT = bytes32(uint256(12));

    VoteEscrowedPWN_RevenueExposed public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public feeCollector = makeAddr("feeCollector");
    address public owner = makeAddr("owner");
    address public staker = makeAddr("staker");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );
        vm.mockCall(
            feeCollector,
            abi.encodeWithSignature("claimFees(address,uint256,address[],uint256,uint256)"),
            abi.encode(0)
        );

        vePWN = new VoteEscrowedPWN_RevenueExposed();
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock,
            _feeCollector: feeCollector,
            _owner: owner
        });
    }


    function _setupDaoRevenuePortionCheckpoints(uint256 seed) internal returns (uint256) {
        return _setupDaoRevenuePortionCheckpoints(seed, type(uint16).max);
    }

    // helper function to make sorted increasing array with no duplicates
    function _setupDaoRevenuePortionCheckpoints(uint256 seed, uint256 maxEpoch) internal returns (uint256) {
        vePWN.workaround_clearDaoRevenuePortionCheckpoints();
        uint256 maxLength = 1000;
        seed = bound(seed, 0, type(uint256).max - maxLength);
        uint256 length = bound(seed, 1, maxLength);

        for (uint256 i; i < length; i++) {
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            uint16 initialEpoch = uint16(bound(iSeed, 1, 10));
            if (i > 0) {
                // cannot override because max length is 1000 and max value is 10 => max epoch is 10000 < type(uint16).max
                initialEpoch += vePWN.workaround_getDaoRevenuePortionCheckpointAt(i - 1).initialEpoch;
            }
            if (initialEpoch > maxEpoch) {
                length = i;
                break;
            }
            // use index as portion
            vePWN.workaround_pushDaoRevenuePortionCheckpoint(initialEpoch, uint16(i));
        }

        return length;
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_Helpers_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuzzHelper_setupDaoRevenuePortionCheckpoints(uint256 seed) external {
        uint256 length = _setupDaoRevenuePortionCheckpoints(seed);
        vm.assume(length > 0);

        for (uint256 i = 1; i < length; ++i) {
            assertLt(
                vePWN.workaround_getDaoRevenuePortionCheckpointAt(i - 1).initialEpoch,
                vePWN.workaround_getDaoRevenuePortionCheckpointAt(i).initialEpoch
            );
        }
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM REVENUE                                         *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_ClaimRevenue_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuzz_shouldFail_whenEpochDidNotEnd(uint256 epoch) external {
        epoch = bound(epoch, currentEpoch, type(uint256).max);

        vm.expectRevert("vePWN: epoch not finished");
        vePWN.claimRevenue(epoch, new address[](0));
    }

    function testFuzz_shouldFail_whenEpochsTotalPowerNotCalculated(uint256 epoch, uint256 lastCalculatedEpoch) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        lastCalculatedEpoch = bound(lastCalculatedEpoch, 0, epoch - 1);

        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(lastCalculatedEpoch));

        vm.expectRevert("vePWN: need to have calculated total power for the epoch");
        vePWN.claimRevenue(epoch, new address[](0));
    }

    function test_shouldFail_whenTotalPowerZero() external {
        uint256 epoch = currentEpoch - 1;
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));
        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_RevenueExposed.TotalPowerAtInput(epoch));
        vePWN._setTotalPowerAtReturn(0);

        vm.expectRevert("vePWN: no stakers");
        vePWN.claimRevenue(epoch, new address[](0));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldClaimRevenue(
        address caller,
        uint256 epoch,
        address[] memory assets,
        uint256 stakerPower,
        uint256 totalPower,
        uint256 daoRevenuePortion
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));

        totalPower = bound(totalPower, 100, type(uint256).max / 10000);
        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_RevenueExposed.TotalPowerAtInput(epoch));
        vePWN._setTotalPowerAtReturn(totalPower);

        stakerPower = bound(stakerPower, 100, totalPower);
        vePWN._setStakerPowerInput(VoteEscrowedPWN_RevenueExposed.StakerPowerInput(caller, epoch));
        vePWN._setStakerPowerReturn(stakerPower);

        daoRevenuePortion = bound(daoRevenuePortion, 0, 10000);
        vePWN.workaround_pushDaoRevenuePortionCheckpoint(0, uint16(daoRevenuePortion));

        uint256 stakerRealPower = stakerPower * (10000 - daoRevenuePortion) / 10000;

        vm.expectCall(
            feeCollector,
            abi.encodeWithSignature(
                "claimFees(address,uint256,address[],uint256,uint256)",
                caller, epoch, assets, stakerRealPower, totalPower
            )
        );

        vm.prank(caller);
        vePWN.claimRevenue(epoch, assets);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM DAO REVENUE                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_ClaimDaoRevenue_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert();
        vm.prank(caller);
        vePWN.claimDaoRevenue(currentEpoch - 1, new address[](0));
    }

    function testFuzz_shouldFail_whenEpochDidNotEnd(uint256 epoch) external {
        epoch = bound(epoch, currentEpoch, type(uint256).max);

        vm.expectRevert("vePWN: epoch not finished");
        vm.prank(owner);
        vePWN.claimDaoRevenue(epoch, new address[](0));
    }

    function testFuzz_shouldFail_whenEpochsTotalPowerNotCalculated(uint256 epoch, uint256 lastCalculatedEpoch) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        lastCalculatedEpoch = bound(lastCalculatedEpoch, 0, epoch - 1);

        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(lastCalculatedEpoch));

        vm.expectRevert("vePWN: need to have calculated total power for the epoch");
        vm.prank(owner);
        vePWN.claimDaoRevenue(epoch, new address[](0));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldClaimRevenue_whenTotalPowerNotZero(
        uint256 epoch,
        address[] memory assets,
        uint256 totalPower,
        uint256 daoRevenuePortion
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));

        totalPower = bound(totalPower, 100, type(uint256).max / 10000);
        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_RevenueExposed.TotalPowerAtInput(epoch));
        vePWN._setTotalPowerAtReturn(totalPower);

        daoRevenuePortion = bound(daoRevenuePortion, 0, 10000);
        vePWN.workaround_pushDaoRevenuePortionCheckpoint(0, uint16(daoRevenuePortion));

        uint256 realPower = totalPower * daoRevenuePortion / 10000;

        vm.expectCall(
            feeCollector,
            abi.encodeWithSignature(
                "claimFees(address,uint256,address[],uint256,uint256)",
                owner, epoch, assets, realPower, totalPower
            )
        );

        vm.prank(owner);
        vePWN.claimDaoRevenue(epoch, assets);
    }

    function testFuzz_shouldClaimAllRevenue_whenTotalPowerZero(uint256 epoch, address[] memory assets) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));

        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_RevenueExposed.TotalPowerAtInput(epoch));
        vePWN._setTotalPowerAtReturn(0);

        vm.expectCall(
            feeCollector,
            abi.encodeWithSignature(
                "claimFees(address,uint256,address[],uint256,uint256)", owner, epoch, assets, 1, 1
            )
        );

        vm.prank(owner);
        vePWN.claimDaoRevenue(epoch, assets);
    }

}


/*----------------------------------------------------------*|
|*  # SET DAO REVENUE PORTION                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_SetDaoRevenuePortion_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert();
        vm.prank(caller);
        vePWN.setDaoRevenuePortion(100);
    }

    function testFuzz_shouldFaile_whenPortionAboveMax(uint16 portion) external {
        portion = uint16(bound(portion, 5001, type(uint16).max));

        vm.expectRevert("vePWN: portion must be less than or equal 50%");
        vm.prank(owner);
        vePWN.setDaoRevenuePortion(portion);
    }

    function testFuzz_shouldPushNewCheckpoint_whenLastCheckpointIsNotNextEpoch(uint256 seed, uint16 portion) external {
        portion = uint16(bound(portion, 0, 5000));
        uint256 originalLength = _setupDaoRevenuePortionCheckpoints(seed, currentEpoch);

        vm.prank(owner);
        vePWN.setDaoRevenuePortion(portion);

        assertEq(vePWN.workaround_getDaoRevenuePortionCheckpointsLength(), originalLength + 1);
        VoteEscrowedPWN.PortionCheckpoint memory checkpoint = vePWN.workaround_getDaoRevenuePortionCheckpointAt(originalLength);
        assertEq(checkpoint.initialEpoch, currentEpoch + 1);
        assertEq(checkpoint.portion, portion);
    }

    function testFuzz_shouldOverrideCheckpoint_whenLastCheckpointIsNextEpoch(uint256 seed, uint16 portion) external {
        portion = uint16(bound(portion, 1, 5000));
        uint256 originalLength = _setupDaoRevenuePortionCheckpoints(seed, currentEpoch);
        vePWN.workaround_pushDaoRevenuePortionCheckpoint(uint16(currentEpoch) + 1, 0);
        originalLength++;

        vm.prank(owner);
        vePWN.setDaoRevenuePortion(portion);

        assertEq(vePWN.workaround_getDaoRevenuePortionCheckpointsLength(), originalLength);
        VoteEscrowedPWN.PortionCheckpoint memory checkpoint = vePWN.workaround_getDaoRevenuePortionCheckpointAt(originalLength - 1);
        assertEq(checkpoint.initialEpoch, uint16(currentEpoch) + 1);
        assertEq(checkpoint.portion, portion);
    }

}


/*----------------------------------------------------------*|
|*  # DAO REVENUE PORTION                                   *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_DaoRevenuePortion_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuuz_currentDaoRevenuePortion(uint256 seed) external {
        _setupDaoRevenuePortionCheckpoints(seed);
        uint256 expectedPortion = vePWN.daoRevenuePortionFor(currentEpoch);

        uint256 portion = vePWN.currentDaoRevenuePortion();

        assertEq(expectedPortion, portion);
    }

    function testFuzz_daoRevenuePortionFor(uint256 seed, uint16 epoch) external {
        uint256 length = _setupDaoRevenuePortionCheckpoints(seed);
        uint256 expectedPortion;

        if (length > 0) {
            VoteEscrowedPWN.PortionCheckpoint memory checkpoint1 = vePWN.workaround_getDaoRevenuePortionCheckpointAt(0);
            VoteEscrowedPWN.PortionCheckpoint memory checkpoint2 = vePWN.workaround_getDaoRevenuePortionCheckpointAt(length - 1);
            if (checkpoint1.initialEpoch > epoch) {
                expectedPortion = 0;
            } else if (checkpoint2.initialEpoch <= epoch) {
                expectedPortion = checkpoint2.portion;
            } else {
                for (uint256 i; i < length - 1; ++i) {
                    checkpoint1 = vePWN.workaround_getDaoRevenuePortionCheckpointAt(i);
                    checkpoint2 = vePWN.workaround_getDaoRevenuePortionCheckpointAt(i + 1);

                    if (checkpoint1.initialEpoch <= epoch && checkpoint2.initialEpoch > epoch) {
                        expectedPortion = checkpoint1.portion;
                        break;
                    }
                }
            }
        }

        uint256 portion = vePWN.daoRevenuePortionFor(epoch);

        assertEq(expectedPortion, portion);
    }

}
