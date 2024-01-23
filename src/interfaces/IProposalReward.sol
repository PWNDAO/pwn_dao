// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title Interface of the proposal reward contract.
/// @notice The contract is used to assign rewards to governance proposals.
interface IProposalReward {

    /// @notice Assigns a reward to a governance proposal.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    function assignProposalReward(address votingContract, uint256 proposalId) external;

}
