// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

// This code is based on the Aragon's optimistic token voting interface.
// https://github.com/aragon/optimistic-token-voting-plugin/blob/f25ea1db9b67a72b7a2e225d719577551e30ac9b/src/IOptimisticTokenVoting.sol
// Changes:
// - Remove `minProposerVotingPower`
// - Add `cancelProposal` and `canCancel`
// - Add `getProposal`

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";

/// @title PWN Optimistic Governance Interface
/// @notice The interface of an optimistic governance plugin.
interface IPWNOptimisticGovernance {

    // # LIFECYCLE

    /// @notice Creates a new optimistic proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts. Uses bitmap representation. If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed. Passing 0 will be treated as atomic execution.
    /// @param _startDate The start date of the proposal vote. If 0, the current timestamp is used and the vote starts immediately.
    /// @param _endDate The end date of the proposal vote. If 0, `_startDate + minDuration` is used.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate
    ) external returns (uint256 proposalId);

    /// @notice Registers a veto for the given proposal.
    /// @param _proposalId The ID of the proposal.
    function veto(uint256 _proposalId) external;

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    /// @notice Cancels a proposal.
    /// @param _proposalId The ID of the proposal to be cancelled.
    function cancelProposal(uint256 _proposalId) external;

    // # PROPOSAL

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotEpoch The epoch at which the voting power is checkpointed.
    /// @param minVetoVotingPower The minimum voting power needed to defeat the proposal.
    struct ProposalParameters {
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotEpoch;
        uint256 minVetoVotingPower;
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return cancelled Whether the proposal is cancelled or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return vetoTally The current voting power used to veto the proposal.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 _proposalId)
        external
        view
        returns (
            bool open,
            bool executed,
            bool cancelled,
            ProposalParameters memory parameters,
            uint256 vetoTally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        );

    /// @notice Checks if an account can participate on an optimistic proposal. This can be because the proposal
    /// - has not started,
    /// - has ended,
    /// - was cancelled,
    /// - was executed, or
    /// - the voter doesn't have voting power.
    /// @param _proposalId The proposal Id.
    /// @param _account The account address to be checked.
    /// @return Returns true if the account is allowed to veto.
    /// @dev The function assumes that the queried proposal exists.
    function canVeto(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Returns whether the account has voted for the proposal.  Note, that this does not check if the account has vetoing power.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The whether the given account has vetoed the given proposal.
    function hasVetoed(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Checks if the total votes against a proposal is greater than the veto threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the total veto power against the proposal is greater or equal than the threshold and `false` otherwise.
    function isMinVetoRatioReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if a proposal can be cancelled.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be cancelled, false otherwise.
    function canCancel(uint256 _proposalId) external view returns (bool);

    // # SETTINGS

    /// @notice Returns the veto ratio parameter stored in the optimistic governance settings.
    /// @return The veto ratio parameter.
    function minVetoRatio() external view returns (uint32);

    /// @notice Returns the minimum duration parameter stored in the optimistic governance settings.
    /// @return The minimum duration parameter.
    function minDuration() external view returns (uint64);

    // # VOTING TOKEN

    /// @notice Getter function for the voting token.
    /// @return The token used for voting.
    function getVotingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns the total voting power checkpointed for a specific epoch.
    /// @param _epoch The epoch to query.
    /// @return The total voting power.
    function totalVotingPower(uint256 _epoch) external view returns (uint256);

}
