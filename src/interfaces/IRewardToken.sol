// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title Interface of the proposal reward contract.
/// @notice The contract is used to assign rewards to governance proposals.
interface IRewardToken {

    /// @notice Assigns a reward to a governance proposal.
    /// @param proposalId The proposal id.
    function assignProposalReward(uint256 proposalId) external;

}
