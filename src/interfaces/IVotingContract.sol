// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

// Documentation is taken from the Aragon OSx contracts:
// IDAO: https://github.com/aragon/osx/blob/1e6d56dc1c353796c92c2a77a50e3febda25773c/packages/contracts/src/core/dao/IDAO.sol
// IMajorityVoting: https://github.com/aragon/osx/blob/1e6d56dc1c353796c92c2a77a50e3febda25773c/packages/contracts/src/plugins/governance/majority-voting/IMajorityVoting.sol]
// MajorityVotingBase: https://github.com/aragon/osx/blob/1e6d56dc1c353796c92c2a77a50e3febda25773c/packages/contracts/src/plugins/governance/majority-voting/MajorityVotingBase.sol]
// TokenVoting: https://github.com/aragon/osx/blob/1e6d56dc1c353796c92c2a77a50e3febda25773c/packages/contracts/src/plugins/governance/majority-voting/token/TokenVoting.sol

/// @title IVotingContract
/// @notice Interface for the VotingContract.
/// @dev Compatible with Aragon OSx {TokenVoting} contracts.
interface IVotingContract {

    /// @notice Vote options that a voter can chose from.
    /// @param None The default option state of a voter indicating the absence from the vote. This option neither influences support nor participation.
    /// @param Abstain This option does not influence the support but counts towards participation.
    /// @param Yes This option increases the support and counts towards participation.
    /// @param No This option decreases the support and counts towards participation.
    enum VoteOption {
        None, Abstain, Yes, No
    }

    /// @notice The different voting modes available.
    /// @param Standard In standard mode, early execution and vote replacement are disabled.
    /// @param EarlyExecution In early execution mode, a proposal can be executed early before the end date if the vote outcome cannot mathematically change by more voters voting.
    /// @param VoteReplacement In vote replacement mode, voters can change their vote multiple times and only the latest vote option is tallied.
    enum VotingMode {
        Standard, EarlyExecution, VoteReplacement
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value. The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param minVotingPower The minimum voting power needed.
    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotEpoch;
        uint256 minVotingPower;
    }

    /// @notice A container for the proposal vote tally.
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    /// @notice The action struct to be consumed by the DAO's `execute` function resulting in an external call.
    /// @param to The address to call.
    /// @param value The native token value to be sent with the call.
    /// @param data The bytes-encoded function selector and calldata for the call.
    struct Action {
        address to;
        uint256 value;
        bytes data;
    }

    /// @notice Getter function for the voting token.
    /// @dev Public function also useful for registering interfaceId and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function getVotingToken() external view returns (IVotes);

    /// @notice Returns whether the account has voted for the proposal. Note, that this does not check if the account has voting power.
    /// @param proposalId The ID of the proposal.
    /// @param voter The account address to be checked.
    /// @return The vote option cast by a voter for a certain proposal.
    function getVoteOption(uint256 proposalId, address voter) external view returns (VoteOption);

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return tally The current tally of the proposal vote.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 proposalId) external view returns (
        bool open,
        bool executed,
        ProposalParameters memory parameters,
        Tally memory tally,
        Action[] memory actions,
        uint256 allowFailureMap
    );
}
