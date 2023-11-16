// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { VoteEscrowedPWNHarness } from "../harness/VoteEscrowedPWNHarness.sol";
import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

abstract contract VoteEscrowedPWN_Revenue_Test is VoteEscrowedPWN_Test {

    function _setupDaoRevenueShares(uint256 seed) internal returns (uint256) {
        return _setupDaoRevenueShares(seed, type(uint16).max);
    }

    // helper function to make sorted increasing array with no duplicates
    function _setupDaoRevenueShares(uint256 seed, uint256 maxEpoch) internal returns (uint256) {
        vePWN.workaround_clearDaoRevenueShares();
        uint256 maxLength = 1000;
        seed = bound(seed, 0, type(uint256).max - maxLength);
        uint256 length = bound(seed, 1, maxLength);

        for (uint256 i; i < length; i++) {
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            uint16 initialEpoch = uint16(bound(iSeed, 1, 10));
            if (i > 0) {
                // cannot override, max length is 1000 and max value is 10 => max epoch is 10000 < type(uint16).max
                initialEpoch += vePWN.workaround_getDaoRevenueShareAt(i - 1).initialEpoch;
            }
            if (initialEpoch > maxEpoch) {
                length = i;
                break;
            }
            // use index as share
            vePWN.workaround_pushDaoRevenueShare(initialEpoch, uint16(i));
        }

        return length;
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_Helpers_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuzzHelper_setupDaoRevenueShares(uint256 seed) external {
        uint256 length = _setupDaoRevenueShares(seed);
        vm.assume(length > 0);

        for (uint256 i = 1; i < length; ++i) {
            assertLt(
                vePWN.workaround_getDaoRevenueShareAt(i - 1).initialEpoch,
                vePWN.workaround_getDaoRevenueShareAt(i).initialEpoch
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

    function testFuzz_shouldFail_whenEpochsTotalPowerNotCalculated(
        uint256 epoch, uint256 lastCalculatedEpoch
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        lastCalculatedEpoch = bound(lastCalculatedEpoch, 0, epoch - 1);

        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(lastCalculatedEpoch));

        vm.expectRevert("vePWN: need to have calculated total power for the epoch");
        vePWN.claimRevenue(epoch, new address[](0));
    }

    function test_shouldFail_whenTotalPowerZero() external {
        uint256 epoch = currentEpoch - 1;
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));
        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput(epoch));
        vePWN.workaround_setTotalPowerAtReturn(0);

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
        uint256 daoRevenueShare
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));

        totalPower = bound(totalPower, 100, type(uint256).max / 10000);
        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput(epoch));
        vePWN.workaround_setTotalPowerAtReturn(totalPower);

        stakerPower = bound(stakerPower, 100, totalPower);
        vePWN.workaround_setStakerPowerInput(VoteEscrowedPWNHarness.StakerPowerInput(caller, epoch));
        vePWN.workaround_setStakerPowerReturn(stakerPower);

        daoRevenueShare = bound(daoRevenueShare, 0, 10000);
        vePWN.workaround_pushDaoRevenueShare(0, uint16(daoRevenueShare));

        uint256 stakerRealPower = stakerPower * (10000 - daoRevenueShare) / 10000;

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

    function testFuzz_shouldFail_whenEpochsTotalPowerNotCalculated(
        uint256 epoch, uint256 lastCalculatedEpoch
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        lastCalculatedEpoch = bound(lastCalculatedEpoch, 0, epoch - 1);

        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(lastCalculatedEpoch));

        vm.expectRevert("vePWN: need to have calculated total power for the epoch");
        vm.prank(owner);
        vePWN.claimDaoRevenue(epoch, new address[](0));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_shouldClaimRevenue_whenTotalPowerNotZero(
        uint256 epoch, address[] memory assets, uint256 totalPower, uint256 daoRevenueShare
    ) external {
        epoch = bound(epoch, 1, currentEpoch - 1);
        vm.store(address(vePWN), LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT, bytes32(epoch));

        totalPower = bound(totalPower, 100, type(uint256).max / 10000);
        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput(epoch));
        vePWN.workaround_setTotalPowerAtReturn(totalPower);

        daoRevenueShare = bound(daoRevenueShare, 0, 10000);
        vePWN.workaround_pushDaoRevenueShare(0, uint16(daoRevenueShare));

        uint256 realPower = totalPower * daoRevenueShare / 10000;

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

        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput(epoch));
        vePWN.workaround_setTotalPowerAtReturn(0);

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
|*  # SET DAO REVENUE SHARE                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_SetDaoRevenueShare_Test is VoteEscrowedPWN_Revenue_Test {

    event DaoRevenueShareChanged(uint256 indexed epoch, uint16 oldValue, uint16 newValue);

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert();
        vm.prank(caller);
        vePWN.setDaoRevenueShare(100);
    }

    function testFuzz_shouldFaile_whenShareAboveMax(uint16 share) external {
        share = uint16(bound(share, 5001, type(uint16).max));

        vm.expectRevert("vePWN: share must be less than or equal 50%");
        vm.prank(owner);
        vePWN.setDaoRevenueShare(share);
    }

    function testFuzz_shouldFaile_whenShareAlreadySet(uint16 share) external {
        share = uint16(bound(share, 0, 5000));
        vePWN.workaround_pushDaoRevenueShare(uint16(currentEpoch), share);

        vm.expectRevert("vePWN: share already set");
        vm.prank(owner);
        vePWN.setDaoRevenueShare(share);
    }

    function testFuzz_shouldPushNewCheckpoint_whenLastCheckpointIsNotNextEpoch(uint256 seed, uint16 share) external {
        share = uint16(bound(share, 0, 5000));
        uint256 originalLength = _setupDaoRevenueShares(seed, currentEpoch);
        vm.assume(share != vePWN.workaround_getDaoRevenueShareAt(originalLength - 1).share);

        vm.prank(owner);
        vePWN.setDaoRevenueShare(share);

        assertEq(vePWN.workaround_getDaoRevenueSharesLength(), originalLength + 1);
        VoteEscrowedPWNHarness.RevenueShareCheckpoint memory checkpoint = vePWN.workaround_getDaoRevenueShareAt(
            originalLength
        );
        assertEq(checkpoint.initialEpoch, currentEpoch + 1);
        assertEq(checkpoint.share, share);
    }

    function testFuzz_shouldOverrideCheckpoint_whenLastCheckpointIsNextEpoch(uint256 seed, uint16 share) external {
        share = uint16(bound(share, 1, 5000));
        uint256 originalLength = _setupDaoRevenueShares(seed, currentEpoch);
        vePWN.workaround_pushDaoRevenueShare(uint16(currentEpoch) + 1, 0);
        originalLength++;

        vm.prank(owner);
        vePWN.setDaoRevenueShare(share);

        assertEq(vePWN.workaround_getDaoRevenueSharesLength(), originalLength);
        VoteEscrowedPWNHarness.RevenueShareCheckpoint memory checkpoint = vePWN.workaround_getDaoRevenueShareAt(
            originalLength - 1
        );
        assertEq(checkpoint.initialEpoch, uint16(currentEpoch) + 1);
        assertEq(checkpoint.share, share);
    }

    function test_shouldEmit_DaoRevenueShareChanged(uint16 oldShare, uint16 newShare) external {
        oldShare = uint16(bound(oldShare, 0, 5000));
        newShare = uint16(bound(newShare, 0, 5000));
        vm.assume(oldShare != newShare);
        vePWN.workaround_pushDaoRevenueShare(uint16(currentEpoch), oldShare);

        vm.expectEmit();
        emit DaoRevenueShareChanged(currentEpoch + 1, oldShare, newShare);

        vm.prank(owner);
        vePWN.setDaoRevenueShare(newShare);
    }

}


/*----------------------------------------------------------*|
|*  # DAO REVENUE SHARE                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Revenue_DaoRevenueShare_Test is VoteEscrowedPWN_Revenue_Test {

    function testFuuz_currentDaoRevenueShare(uint256 seed) external {
        _setupDaoRevenueShares(seed);
        uint256 expectedShare = vePWN.daoRevenueShareFor(currentEpoch);

        uint256 share = vePWN.currentDaoRevenueShare();

        assertEq(expectedShare, share);
    }

    function testFuzz_daoRevenueShareFor(uint256 seed, uint16 epoch) external {
        uint256 length = _setupDaoRevenueShares(seed);
        uint256 expectedShare;

        if (length > 0) {
            VoteEscrowedPWNHarness.RevenueShareCheckpoint memory checkpoint1 =
                vePWN.workaround_getDaoRevenueShareAt(0);
            VoteEscrowedPWNHarness.RevenueShareCheckpoint memory checkpoint2 =
                vePWN.workaround_getDaoRevenueShareAt(length - 1);
            if (checkpoint1.initialEpoch > epoch) {
                expectedShare = 0;
            } else if (checkpoint2.initialEpoch <= epoch) {
                expectedShare = checkpoint2.share;
            } else {
                for (uint256 i; i < length - 1; ++i) {
                    checkpoint1 = vePWN.workaround_getDaoRevenueShareAt(i);
                    checkpoint2 = vePWN.workaround_getDaoRevenueShareAt(i + 1);

                    if (checkpoint1.initialEpoch <= epoch && checkpoint2.initialEpoch > epoch) {
                        expectedShare = checkpoint1.share;
                        break;
                    }
                }
            }
        }

        uint256 share = vePWN.daoRevenueShareFor(epoch);

        assertEq(expectedShare, share);
    }

}
