// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

library Error {

    // PWN
    error MintableSupplyExceeded();
    error ZeroVotingContract();
    error VotingRewardNotSet();
    error ProposalNotExecuted();
    error CallerHasNotVoted();
    error ProposalRewardAlreadyClaimed();
    error ProposalRewardNotAssigned();
    error InvalidVotingReward();
    error IncreaseAllowanceNotSupported();
    error DecreaseAllowanceNotSupported();

    // PWNEpochClock
    error InitialEpochTimestampInFuture(uint256 currentTimestamp);

    // StakedPWN
    error CallerNotSupplyManager();
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
    error CallerNotStakedPWNContract();

}
