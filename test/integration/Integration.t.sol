// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { TransparentUpgradeableProxy }
    from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWN } from "src/token/PWN.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";
import { VoteEscrowedPWN } from "src/token/VoteEscrowedPWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

import { Base_Test } from "../Base.t.sol";

abstract contract Integration_Test is Base_Test {

    uint256 public constant EPOCHS_IN_YEAR = 13;

    PWN public pwnToken;
    PWNEpochClock public epochClock;
    StakedPWN public stPWN;
    VoteEscrowedPWN public vePWN;

    address public dao = makeAddr("dao");
    address public staker = makeAddr("staker");
    address public votingContract = makeAddr("votingContract");

    uint256 public defaultFundAmount = 1000 ether;


    /// After setup:
    /// - the contracts are deployed and initialized
    /// - the staker address has 1,000 PWN tokens
    /// - the dao address owns the PWN contract
    /// - the dao is admin of the vePWN contract
    function setUp() public virtual {
        // deploy contracts
        epochClock = new PWNEpochClock(block.timestamp);
        pwnToken = new PWN(dao);
        VoteEscrowedPWN vePWNImpl = new VoteEscrowedPWN();
        vePWN = VoteEscrowedPWN(address(
            new TransparentUpgradeableProxy(address(vePWNImpl), dao, "")
        ));
        stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock));

        vm.startPrank(dao);
        stPWN.enableTransfers();
        pwnToken.enableTransfers();
        vm.stopPrank();

        // fund staker address
        _fundStaker(staker, defaultFundAmount);

        // label addresses for debugging
        vm.label(address(pwnToken), "PWN Token");
        vm.label(address(epochClock), "PWN Epoch Clock");
        vm.label(address(stPWN), "Staked PWN");
        vm.label(address(vePWN), "Vote Escrowed PWN");
        vm.label(staker, "Staker");
        vm.label(dao, "DAO");
    }


    function _fundStaker(address _staker, uint256 amount) internal {
        vm.startPrank(dao);
        pwnToken.mint(amount);
        pwnToken.transfer(_staker, amount);
        vm.stopPrank();
    }

    function _warpEpochs(uint256 epochs) internal {
        vm.warp(block.timestamp + epochs * epochClock.SECONDS_IN_EPOCH());
    }

    function _powerFor(uint256 amount, uint256 lockUpEpochs) internal pure returns (uint256) {
        if (lockUpEpochs == 0) return 0;
        else if (lockUpEpochs <= 1 * EPOCHS_IN_YEAR) return amount * 100 / 100;
        else if (lockUpEpochs <= 2 * EPOCHS_IN_YEAR) return amount * 115 / 100;
        else if (lockUpEpochs <= 3 * EPOCHS_IN_YEAR) return amount * 130 / 100;
        else if (lockUpEpochs <= 4 * EPOCHS_IN_YEAR) return amount * 150 / 100;
        else if (lockUpEpochs <= 5 * EPOCHS_IN_YEAR) return amount * 175 / 100;
        else if (lockUpEpochs <= 10 * EPOCHS_IN_YEAR) return amount * 350 / 100;
        revert("invalid lock up epochs");
    }

    function _boundAmountAndLockUp(uint256 amount, uint256 lockUpEpochs) internal view returns (uint256, uint256) {
        amount = bound(amount, 100, pwnToken.balanceOf(staker));
        amount = amount / 100 * 100; // get multiple of 100
        lockUpEpochs = bound(lockUpEpochs, EPOCHS_IN_YEAR, 5 * EPOCHS_IN_YEAR + 1);
        lockUpEpochs = lockUpEpochs > 5 * EPOCHS_IN_YEAR ? 10 * EPOCHS_IN_YEAR : lockUpEpochs;

        return (amount, lockUpEpochs);
    }

    function _createStake(uint256 amount, uint256 lockUpEpochs) internal returns (uint256 stakeId) {
        return _createStake(staker, amount, lockUpEpochs);
    }

    function _createStake(address _staker, uint256 amount, uint256 lockUpEpochs) internal returns (uint256 stakeId) {
        vm.startPrank(_staker);
        pwnToken.approve(address(vePWN), amount);
        stakeId = vePWN.createStake(amount, lockUpEpochs);
        vm.stopPrank();
    }

}


/*----------------------------------------------------------*|
|*  # VOTE ESCROWED PWN - STAKE                             *|
|*----------------------------------------------------------*/

contract Integration_vePWN_Stake_Test is Integration_Test {

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_createStake(uint256 amount, uint256 lockUpEpochs) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);

        uint256 stakeId = _createStake(amount, lockUpEpochs);

        assertEq(vePWN.balanceOf(staker), 0); // power from the next epoch
        assertEq(vePWN.getVotes(staker), 0);
        assertEq(vePWN.totalSupply(), 0);
        assertEq(stPWN.ownerOf(stakeId), staker);
        assertEq(pwnToken.balanceOf(staker), 1_000 ether - amount);
        assertEq(pwnToken.balanceOf(address(vePWN)), amount);

        _warpEpochs(1);
        uint256 power = _powerFor(amount, lockUpEpochs);
        assertEq(vePWN.balanceOf(staker), power);
        assertEq(vePWN.getVotes(staker), power);
        assertEq(vePWN.totalSupply(), power);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_increaseStake(
        uint256 amount, uint256 lockUpEpochs, uint256 increaseAmount, uint256 increaseEpochs, uint256 waitingEpochs
    ) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);

        _fundStaker(staker, defaultFundAmount);
        increaseAmount = bound(increaseAmount, 0, pwnToken.balanceOf(staker));
        increaseAmount = increaseAmount / 100 * 100; // get multiple of 100
        waitingEpochs = bound(waitingEpochs, 0, lockUpEpochs + 1);
        uint256 remainingEpochs = lockUpEpochs - Math.min(lockUpEpochs, waitingEpochs);
        increaseEpochs = bound(
            increaseEpochs,
            Math.max(EPOCHS_IN_YEAR, remainingEpochs) - remainingEpochs,
            Math.max(5 * EPOCHS_IN_YEAR, remainingEpochs) - remainingEpochs + 1
        );
        increaseEpochs = increaseEpochs + remainingEpochs > 5 * EPOCHS_IN_YEAR
            ? 10 * EPOCHS_IN_YEAR - remainingEpochs
            : increaseEpochs;
        vm.assume(increaseAmount > 0 || increaseEpochs > 0);

        _warpEpochs(waitingEpochs);
        vm.startPrank(staker);
        pwnToken.approve(address(vePWN), increaseAmount);
        uint256 newStakeId = vePWN.increaseStake(stakeId, staker, increaseAmount, increaseEpochs);
        vm.stopPrank();

        vm.expectRevert();
        stPWN.ownerOf(stakeId);
        assertEq(stPWN.ownerOf(newStakeId), staker);
        assertEq(pwnToken.balanceOf(staker), 2 * defaultFundAmount - amount - increaseAmount);
        assertEq(pwnToken.balanceOf(address(vePWN)), amount + increaseAmount);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_withdrawStake(uint256 amount, uint256 lockUpEpochs) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);

        _warpEpochs(lockUpEpochs + 1);
        vm.prank(staker);
        vePWN.withdrawStake(stakeId, staker);

        vm.expectRevert();
        stPWN.ownerOf(stakeId);
        assertEq(pwnToken.balanceOf(staker), defaultFundAmount);
        assertEq(pwnToken.balanceOf(address(vePWN)), 0);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.getVotes(staker), 0);
        assertEq(vePWN.totalSupply(), 0);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_mergeStakes(
        uint256 amount1,
        uint256 amount2,
        uint256 lockUpEpochs1,
        uint256 lockUpEpochs2,
        uint256 delayStakes,
        uint256 delayMerge
    ) external {
        (amount1, lockUpEpochs1) = _boundAmountAndLockUp(amount1, lockUpEpochs1);
        uint256 stakeId1 = _createStake(amount1, lockUpEpochs1);
        delayStakes = bound(delayStakes, 0, lockUpEpochs1 - EPOCHS_IN_YEAR);
        _warpEpochs(delayStakes);
        _fundStaker(staker, defaultFundAmount);
        (amount2, lockUpEpochs2) = _boundAmountAndLockUp(amount2, lockUpEpochs2);
        lockUpEpochs2 = bound(lockUpEpochs2, EPOCHS_IN_YEAR, lockUpEpochs1 - delayStakes);
        if (lockUpEpochs2 < 10 * EPOCHS_IN_YEAR && lockUpEpochs2 > 5 * EPOCHS_IN_YEAR)
            lockUpEpochs2 = 5 * EPOCHS_IN_YEAR;
        uint256 stakeId2 = _createStake(amount2, lockUpEpochs2);
        delayMerge = bound(delayMerge, 0, lockUpEpochs1 - delayStakes - 1);

        _warpEpochs(delayMerge);
        vm.prank(staker);
        uint256 newStakeId = vePWN.mergeStakes(stakeId1, staker, stakeId2, staker);

        vm.expectRevert();
        stPWN.ownerOf(stakeId1);
        vm.expectRevert();
        stPWN.ownerOf(stakeId2);
        assertEq(stPWN.ownerOf(newStakeId), staker);
        assertEq(pwnToken.balanceOf(staker), 2 * defaultFundAmount - amount1 - amount2);
        assertEq(pwnToken.balanceOf(address(vePWN)), amount1 + amount2);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_splitStake(uint256 amount, uint256 splitAmount, uint256 lockUpEpochs, uint256 delaySplit)
        external
    {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);
        vm.assume(amount > 100);
        splitAmount = bound(splitAmount, 1, amount / 100 - 1) * 100;
        delaySplit = bound(delaySplit, 0, lockUpEpochs + 1);

        _warpEpochs(delaySplit);
        vm.prank(staker);
        (uint256 newStakeId1, uint256 newStakeId2) = vePWN.splitStake(stakeId, staker, splitAmount);

        vm.expectRevert();
        stPWN.ownerOf(stakeId);
        assertEq(stPWN.ownerOf(newStakeId1), staker);
        assertEq(stPWN.ownerOf(newStakeId2), staker);
        assertEq(pwnToken.balanceOf(staker), defaultFundAmount - amount);
        assertEq(pwnToken.balanceOf(address(vePWN)), amount);
    }

}


/*----------------------------------------------------------*|
|*  # VOTE ESCROWED PWN - POWER                             *|
|*----------------------------------------------------------*/

contract Integration_vePWN_Power_Test is Integration_Test {

    uint256 public defaultLockUpEpochs = 30;
    uint256 public stakeId;

    function setUp() public override {
        super.setUp();

        stakeId = _createStake(defaultFundAmount, defaultLockUpEpochs);
    }


    function test_pastAndCurrentPowerIsImmutable_whenSplit() external {
        _warpEpochs(defaultLockUpEpochs / 2);

        vm.prank(staker);
        vePWN.splitStake({ stakeId: stakeId, stakeBeneficiary: staker, splitAmount: defaultFundAmount / 4 });

        uint16 currentEpoch = epochClock.currentEpoch();
        for (uint256 i; i < defaultLockUpEpochs / 2; ++i) {
            uint256 lockUpEpochs = defaultLockUpEpochs + 1 - defaultLockUpEpochs / 2 + i;
            uint256 power = _powerFor(defaultFundAmount, lockUpEpochs);
            assertEq(vePWN.stakerPowerAt(staker, currentEpoch - i), power);
        }
    }

    function test_pastAndCurrentPowerIsImmutable_whenMerge() external {
        _fundStaker(staker, defaultFundAmount);
        uint256 stakeId2 = _createStake(defaultFundAmount, defaultLockUpEpochs);

        _warpEpochs(defaultLockUpEpochs / 2);

        vm.prank(staker);
        vePWN.mergeStakes({ stakeId1: stakeId, stakeBeneficiary1: staker, stakeId2: stakeId2, stakeBeneficiary2: staker });

        uint16 currentEpoch = epochClock.currentEpoch();
        for (uint256 i; i < defaultLockUpEpochs / 2; ++i) {
            uint256 lockUpEpochs = defaultLockUpEpochs + 1 - defaultLockUpEpochs / 2 + i;
            uint256 power = _powerFor(2 * defaultFundAmount, lockUpEpochs);
            assertEq(vePWN.stakerPowerAt(staker, currentEpoch - i), power);
        }
    }

    function test_pastAndCurrentPowerIsImmutable_whenIncrease() external {
        _warpEpochs(defaultLockUpEpochs / 2);

        vm.prank(staker);
        vePWN.increaseStake({ stakeId: stakeId, stakeBeneficiary: staker, additionalAmount: 0, additionalEpochs: 20 });

        uint16 currentEpoch = epochClock.currentEpoch();
        for (uint256 i; i < defaultLockUpEpochs / 2; ++i) {
            uint256 lockUpEpochs = defaultLockUpEpochs + 1 - defaultLockUpEpochs / 2 + i;
            uint256 power = _powerFor(defaultFundAmount, lockUpEpochs);
            assertEq(vePWN.stakerPowerAt(staker, currentEpoch - i), power);
        }
    }

    function test_pastAndCurrentPowerIsImmutable_whenWithdraw() external {
        _warpEpochs(defaultLockUpEpochs + 1);

        vm.prank(staker);
        vePWN.withdrawStake(stakeId, staker);

        uint16 currentEpoch = epochClock.currentEpoch();
        for (uint256 i; i < defaultLockUpEpochs; ++i) {
            uint256 lockUpEpochs = i;
            uint256 power = _powerFor(defaultFundAmount, lockUpEpochs);
            assertEq(vePWN.stakerPowerAt(staker, currentEpoch - lockUpEpochs), power);
        }
    }

}


/*----------------------------------------------------------*|
|*  # VOTE ESCROWED PWN - POWER TRANSFER                    *|
|*----------------------------------------------------------*/

contract Integration_vePWN_PowerTransfer_Test is Integration_Test {

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_transferStake_whenNotInInitialEpoch(uint256 amount, uint256 lockUpEpochs) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);
        address otherStaker = makeAddr("otherStaker");

        vm.prank(staker);
        stPWN.transferFrom(staker, otherStaker, stakeId);

        _warpEpochs(1);

        vm.prank(otherStaker);
        vePWN.delegateStakePower(stakeId, staker, otherStaker);

        uint256 power = _powerFor(amount, lockUpEpochs);
        assertEq(stPWN.ownerOf(stakeId), otherStaker);
        assertEq(vePWN.balanceOf(staker), power);
        assertEq(vePWN.balanceOf(otherStaker), 0);
        assertEq(vePWN.totalSupply(), power);

        _warpEpochs(1);
        power = _powerFor(amount, lockUpEpochs - 1);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.balanceOf(otherStaker), power);
        assertEq(vePWN.totalSupply(), power);
    }

    function testFuzz_transferStake_whenInInitialEpoch(uint256 amount, uint256 lockUpEpochs) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);
        address otherStaker = makeAddr("otherStaker");

        vm.prank(staker);
        stPWN.transferFrom(staker, otherStaker, stakeId);

        vm.prank(otherStaker);
        vePWN.delegateStakePower(stakeId, staker, otherStaker);

        assertEq(stPWN.ownerOf(stakeId), otherStaker);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.balanceOf(otherStaker), 0);
        assertEq(vePWN.totalSupply(), 0);

        _warpEpochs(1);
        uint256 power = _powerFor(amount, lockUpEpochs);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.balanceOf(otherStaker), power);
        assertEq(vePWN.totalSupply(), power);
    }

    function testFuzz_transferStake_whenAfterFinalEpoch(uint256 amount, uint256 lockUpEpochs) external {
        (amount, lockUpEpochs) = _boundAmountAndLockUp(amount, lockUpEpochs);
        uint256 stakeId = _createStake(amount, lockUpEpochs);
        address otherStaker = makeAddr("otherStaker");
        _warpEpochs(lockUpEpochs + 1);

        vm.prank(staker);
        stPWN.transferFrom(staker, otherStaker, stakeId);
        vm.prank(otherStaker);
        vePWN.delegateStakePower(stakeId, staker, otherStaker);

        assertEq(stPWN.ownerOf(stakeId), otherStaker);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.balanceOf(otherStaker), 0);
        assertEq(vePWN.totalSupply(), 0);

        _warpEpochs(1);
        assertEq(vePWN.balanceOf(staker), 0);
        assertEq(vePWN.balanceOf(otherStaker), 0);
        assertEq(vePWN.totalSupply(), 0);
    }

}
