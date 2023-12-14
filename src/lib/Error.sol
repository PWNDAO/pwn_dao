// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

library Error {

    // PWN
    error MintableSupplyExceeded();
    error InImmutablePeriod();
    error RewardTooHigh(uint256 maxReward);
    error ZeroReward();
    error RewardAlreadyAssigned(uint256 currentReward);
    error ZeroVotingContract();
    error ProposalNotExecuted();
    error CallerHasNotVoted();
    error RewardAlreadyClaimed();

    // PWNEpochClock
    error InitialEpochTimestampInFuture(uint256 currentTimestamp);

    // StakedPWN
    error NotVoteEscrowedPWNContract();
    error TransfersDisabled();
    error TransfersAlreadyEnabled();

    // VoteEscrowedPWN.Base
    error TransferDisabled();
    error TransferFromDisabled();
    error ApproveDisabled();
    error DelegateDisabled();
    error DelegateBySigDisabled();

    // VoteEscrowedPWN.Power
    error NoPowerChanges();
    error EpochStillRunning();
    error PowerAlreadyCalculated(uint256 lastCalculatedEpoch);
    error InvariantFail_NegativeCalculatedPower();

    // VoteEscrowedPWN.Stake
    error InvalidAmount();
    error InvalidLockUpPeriod();
    error NotStakeOwner();
    error LockUpPeriodMismatch();
    error NothingToIncrease();
    error WithrawalBeforeLockUpEnd();
    error NotStakedPWNContract();

}
