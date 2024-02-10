// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

// solhint-disable max-line-length

// This code is based on the Aragon's token voting plugin.
// https://github.com/aragon/osx/blob/e90ea8f5cd6b98cbba16db07ab7bc0cdbf517f3e/packages/contracts/src/plugins/governance/majority-voting/token/TokenVoting.sol
// Changes:
// - Remove `MAJORITY_VOTING_BASE_INTERFACE_ID` and `TOKEN_VOTING_INTERFACE_ID`
// - Use epochs instead of block numbers
// - Assign voting reward on proposal creation

// solhint-enable max-line-length

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { IMembership } from "@aragon/osx/core/plugin/membership/IMembership.sol";
import { ProposalUpgradeable } from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import { PluginUUPSUpgradeable } from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import { RATIO_BASE, _applyRatioCeiled, RatioOutOfBounds } from "@aragon/osx/plugins/utils/Ratio.sol";

import { IPWNTokenGovernance } from "./IPWNTokenGovernance.sol";
import { IPWNEpochClock } from "src/interfaces/IPWNEpochClock.sol";
import { IRewardToken } from "src/interfaces/IRewardToken.sol";

// solhint-disable max-line-length

/// @title PWN Token Governance Plugin
/// @notice The implementation of token governance plugin.
///
/// ### Parameterization
///
/// We define two parameters
/// $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes} + N_\text{no}} \in [0,1]$$
/// and
/// $$\texttt{participation} = \frac{N_\text{yes} + N_\text{no} + N_\text{abstain}}{N_\text{total}} \in [0,1],$$
/// where $N_\text{yes}$, $N_\text{no}$, and $N_\text{abstain}$ are the yes, no, and abstain votes that have been cast and $N_\text{total}$ is the total voting power available at proposal creation time.
///
/// #### Limit Values: Support Threshold & Minimum Participation
///
/// Two limit values are associated with these parameters and decide if a proposal execution should be possible: $\texttt{supportThreshold} \in [0,1]$ and $\texttt{minParticipation} \in [0,1]$.
///
/// For threshold values, $>$ comparison is used. This **does not** include the threshold value. E.g., for $\texttt{supportThreshold} = 50\%$, the criterion is fulfilled if there is at least one more yes than no votes ($N_\text{yes} = N_\text{no} + 1$).
/// For minimum values, $\ge{}$ comparison is used. This **does** include the minimum participation value. E.g., for $\texttt{minParticipation} = 40\%$ and $N_\text{total} = 10$, the criterion is fulfilled if 4 out of 10 votes were casted.
///
/// Majority voting implies that the support threshold is set with
/// $$\texttt{supportThreshold} \ge 50\% .$$
/// However, this is not enforced by the contract code and developers can make unsafe parameters and only the frontend will warn about bad parameter settings.
///
/// ### Execution Criteria
///
/// After the vote is closed, two criteria decide if the proposal passes.
///
/// #### The Support Criterion
///
/// For a proposal to pass, the required ratio of yes and no votes must be met:
/// $$(1- \texttt{supportThreshold}) \cdot N_\text{yes} > \texttt{supportThreshold} \cdot N_\text{no}.$$
/// Note, that the inequality yields the simple majority voting condition for $\texttt{supportThreshold}=\frac{1}{2}$.
///
/// #### The Participation Criterion
///
/// For a proposal to pass, the minimum voting power must have been cast:
/// $$N_\text{yes} + N_\text{no} + N_\text{abstain} \ge \texttt{minVotingPower},$$
/// where $\texttt{minVotingPower} = \texttt{minParticipation} \cdot N_\text{total}$.
///
/// ### Vote Replacement Execution
///
/// The contract allows votes to be replaced. Voters can vote multiple times and only the latest voteOption is tallied.
///
/// ### Early Execution
///
/// This contract allows a proposal to be executed early, iff the vote outcome cannot change anymore by more people voting. Accordingly, vote replacement and early execution are /// mutually exclusive options.
/// The outcome cannot change anymore iff the support threshold is met even if all remaining votes are no votes. We call this number the worst-case number of no votes and define it as
///
/// $$N_\text{no, worst-case} = N_\text{no} + \texttt{remainingVotes}$$
///
/// where
///
/// $$\texttt{remainingVotes} = N_\text{total}-\underbrace{(N_\text{yes}+N_\text{no}+N_\text{abstain})}_{\text{turnout}}.$$
///
/// We can use this quantity to calculate the worst-case support that would be obtained if all remaining votes are casted with no:
///
/// $$
/// \begin{align*}
///   \texttt{worstCaseSupport}
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no, worst-case})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no} + \texttt{remainingVotes})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} +  N_\text{no} + N_\text{total} - (N_\text{yes} + N_\text{no} + N_\text{abstain})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{total} - N_\text{abstain}}
/// \end{align*}
/// $$
///
/// In analogy, we can modify [the support criterion](#the-support-criterion) from above to allow for early execution:
///
/// $$
/// \begin{align*}
///   (1 - \texttt{supportThreshold}) \cdot N_\text{yes}
///   &> \texttt{supportThreshold} \cdot  N_\text{no, worst-case} \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{no} + \texttt{remainingVotes}) \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{no} + N_\text{total}-(N_\text{yes}+N_\text{no}+N_\text{abstain})) \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{total} - N_\text{yes} - N_\text{abstain})
/// \end{align*}
/// $$
///
/// Accordingly, early execution is possible when the vote is open, the modified support criterion, and the particicpation criterion are met.
/// @dev This contract implements the `IPWNTokenGovernance` interface.
// solhint-enable max-line-length
contract PWNTokenGovernancePlugin is
    IPWNTokenGovernance,
    IMembership,
    Initializable,
    ERC165Upgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The ID of the permission required to call the `updateTokenGovernanceSettings` function.
    bytes32 public constant UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION");

    /// @notice The epoch clock contract.
    IPWNEpochClock private epochClock;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
    /// compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken;

    /// @notice The reward token. Voters who vote in proposals can claim a reward proportional to their voting power.
    IRewardToken public rewardToken;

    /// @notice A container for the token governance settings that will be applied as parameters on proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// In standard mode (0), early execution and vote replacement are disabled.
    /// In early execution mode (1), a proposal can be executed early before the end date if the vote outcome cannot
    /// mathematically change by more voters voting. In vote replacement mode (2), voters can change their vote
    /// multiple times and only the latest vote option is tallied.
    /// @param supportThreshold The support threshold value.
    /// Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minParticipation The minimum participation value.
    /// Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    struct TokenGovernanceSettings {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint32 minParticipation;
        uint64 minDuration;
        uint256 minProposerVotingPower;
    }

    /// @notice The property storing the token governance settings.
    TokenGovernanceSettings private governanceSettings;

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param tally The vote tally of the proposal.
    /// @param voters The votes casted by the voters.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    /// If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.
    /// A failure map value of 0 requires every action to not revert.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        Tally tally;
        mapping(address => VoteOption) voters;
        IDAO.Action[] actions;
        uint256 allowFailureMap;
    }

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS                                       *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when a vote is cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the vote.
    /// @param voteOption The casted vote option.
    /// @param votingPower The voting power behind this vote.
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteOption voteOption,
        uint256 votingPower
    );

    /// @notice Emitted when the token governance settings are updated.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    /// @param minParticipation The minimum participation value.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    event TokenGovernanceSettingsUpdated(
        VotingMode votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the minimal duration value is out of bounds (less than one hour or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown if an account is not allowed to cast a vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have voting powers.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    /// @param voteOption The chosen vote option.
    error VoteCastForbidden(uint256 proposalId, address account, VoteOption voteOption);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);


    /*----------------------------------------------------------*|
    |*  # INITIALIZE                                            *|
    |*----------------------------------------------------------*/

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _governanceSettings The voting settings.
    /// @param _epochClock The epoch clock used for time tracking.
    /// @param _token The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token used for voting.
    function initialize(
        IDAO _dao,
        TokenGovernanceSettings calldata _governanceSettings,
        IPWNEpochClock _epochClock,
        IVotesUpgradeable _token,
        IRewardToken _rewardToken
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        epochClock = _epochClock;
        votingToken = _token;
        rewardToken = _rewardToken;

        _updateTokenGovernanceSettings(_governanceSettings);
        emit MembershipContractAnnounced({ definingContract: address(_token) });
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL LIFECYCLE                                    *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPWNTokenGovernance
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) external returns (uint256 proposalId) {
        // check that `_msgSender` has enough voting power
        {
            uint256 minProposerVotingPower_ = minProposerVotingPower();

            if (minProposerVotingPower_ != 0) {
                if (votingToken.getVotes(_msgSender()) < minProposerVotingPower_) {
                    revert ProposalCreationForbidden(_msgSender());
                }
            }
        }

        uint256 snapshotEpoch = epochClock.currentEpoch();
        uint256 totalVotingPower_ = totalVotingPower(snapshotEpoch);

        if (totalVotingPower_ == 0) {
            revert NoVotingPower();
        }

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposal({
            _creator: _msgSender(),
            _metadata: _metadata,
            _startDate: _startDate,
            _endDate: _endDate,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap
        });

        // store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.snapshotEpoch = snapshotEpoch.toUint64();
        proposal_.parameters.votingMode = votingMode();
        proposal_.parameters.supportThreshold = supportThreshold();
        proposal_.parameters.minVotingPower = _applyRatioCeiled(totalVotingPower_, minParticipation());

        // reduce costs
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length;) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        // assign voting reward
        rewardToken.assignProposalReward(proposalId);

        if (_voteOption != VoteOption.None) {
            vote(proposalId, _voteOption, _tryEarlyExecution);
        }
    }

    /// @inheritdoc IPWNTokenGovernance
    function vote(uint256 _proposalId, VoteOption _voteOption, bool _tryEarlyExecution) public {
        address _voter = _msgSender();

        (bool canVote_, uint256 votingPower) = _canVote(_proposalId, _voter, _voteOption);
        if (!canVote_) {
            revert VoteCastForbidden({ proposalId: _proposalId, account: _voter, voteOption: _voteOption });
        }
        _vote(_proposalId, _voteOption, _voter, votingPower, _tryEarlyExecution);
    }

    /// @inheritdoc IPWNTokenGovernance
    function execute(uint256 _proposalId) public {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }
        _execute(_proposalId);
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL                                              *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPWNTokenGovernance
    function getProposal(uint256 _proposalId)
        public
        view
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            Tally memory tally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        tally = proposal_.tally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
    }

    /// @inheritdoc IPWNTokenGovernance
    function isSupportThresholdReached(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * proposal_.tally.no;
    }

    /// @inheritdoc IPWNTokenGovernance
    function isSupportThresholdReachedEarly(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        uint256 noVotesWorstCase = totalVotingPower(proposal_.parameters.snapshotEpoch) -
            proposal_.tally.yes -
            proposal_.tally.abstain;

        // The code below implements the formula of the early execution support criterion explained
        // in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no,worst-case`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * noVotesWorstCase;
    }

    /// @inheritdoc IPWNTokenGovernance
    function isMinParticipationReached(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the participation criterion explained in the top of this file.
        // `N_yes + N_no + N_abstain >= minVotingPower = minParticipation * N_total`
        return
            proposal_.tally.yes + proposal_.tally.no + proposal_.tally.abstain >=
            proposal_.parameters.minVotingPower;
    }

    /// @inheritdoc IPWNTokenGovernance
    function canVote(uint256 _proposalId, address _voter, VoteOption _voteOption)
        public
        view
        returns (bool canVote_)
    {
        (canVote_, ) = _canVote(_proposalId, _voter, _voteOption);
    }

    /// @inheritdoc IPWNTokenGovernance
    function canExecute(uint256 _proposalId) public view returns (bool) {
        return _canExecute(_proposalId);
    }

    /// @inheritdoc IPWNTokenGovernance
    function getVoteOption(uint256 _proposalId, address _voter) public view returns (VoteOption) {
        return proposals[_proposalId].voters[_voter];
    }


    /*----------------------------------------------------------*|
    |*  # SETTINGS                                              *|
    |*----------------------------------------------------------*/

    /// @notice Updates the token governance settings.
    /// @param _governanceSettings The new governance settings.
    function updateTokenGovernanceSettings(TokenGovernanceSettings calldata _governanceSettings)
        external
        auth(UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID)
    {
        _updateTokenGovernanceSettings(_governanceSettings);
    }

    /// @inheritdoc IPWNTokenGovernance
    function supportThreshold() public view returns (uint32) {
        return governanceSettings.supportThreshold;
    }

    /// @inheritdoc IPWNTokenGovernance
    function minParticipation() public view returns (uint32) {
        return governanceSettings.minParticipation;
    }

    /// @inheritdoc IPWNTokenGovernance
    function minDuration() public view returns (uint64) {
        return governanceSettings.minDuration;
    }

    /// @inheritdoc IPWNTokenGovernance
    function minProposerVotingPower() public view returns (uint256) {
        return governanceSettings.minProposerVotingPower;
    }

    /// @inheritdoc IPWNTokenGovernance
    function votingMode() public view returns (VotingMode) {
        return governanceSettings.votingMode;
    }


    /*----------------------------------------------------------*|
    |*  # VOTING TOKEN                                          *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPWNTokenGovernance
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @inheritdoc IPWNTokenGovernance
    function totalVotingPower(uint256 _epoch) public view returns (uint256) {
        return votingToken.getPastTotalSupply(_epoch);
    }


    /*----------------------------------------------------------*|
    |*  # MEMBERSHIP                                            *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must have at least one voting power.
        return votingToken.getVotes(_account) > 0;
    }


    /*----------------------------------------------------------*|
    |*  # SUPPORTED INTERFACE                                   *|
    |*----------------------------------------------------------*/

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC165Upgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return
            _interfaceId == type(IPWNTokenGovernance).interfaceId ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /// @notice Internal implementation.
    function _canVote(uint256 _proposalId, address _account, VoteOption _voteOption)
        internal
        view
        returns (bool, uint256)
    {
        Proposal storage proposal_ = proposals[_proposalId];

        // the proposal vote hasn't started or has already ended
        if (!_isProposalOpen(proposal_)) {
            return (false, 0);
        }

        // the voter votes `None` which is not allowed
        if (_voteOption == VoteOption.None) {
            return (false, 0);
        }

        // the voter has no voting power
        uint256 votingPower = votingToken.getPastVotes(_account, proposal_.parameters.snapshotEpoch);
        if (votingPower == 0) {
            return (false, 0);
        }

        // the voter has already voted but vote replacment is not allowed
        if (
            proposal_.voters[_account] != VoteOption.None &&
            proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return (false, 0);
        }

        return (true, votingPower);
    }

    /// @notice Internal implementation.
    function _vote(
        uint256 _proposalId,
        VoteOption _voteOption,
        address _voter,
        uint256 _votingPower,
        bool _tryEarlyExecution
    ) internal {
        Proposal storage proposal_ = proposals[_proposalId];

        VoteOption state = proposal_.voters[_voter];

        // if voter had previously voted, decrease count
        if (state == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes - _votingPower;
        } else if (state == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no - _votingPower;
        } else if (state == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain - _votingPower;
        }

        // write the updated/new vote for the voter
        if (_voteOption == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes + _votingPower;
        } else if (_voteOption == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no + _votingPower;
        } else if (_voteOption == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain + _votingPower;
        }

        proposal_.voters[_voter] = _voteOption;

        emit VoteCast({
            proposalId: _proposalId,
            voter: _voter,
            voteOption: _voteOption,
            votingPower: _votingPower
        });

        if (_tryEarlyExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @dev Threshold and minimal values are compared with `>` and `>=` comparators, respectively.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal can be executed, false otherwise.
    function _canExecute(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }

        if (_isProposalOpen(proposal_)) {
            // Early execution
            if (proposal_.parameters.votingMode != VotingMode.EarlyExecution) {
                return false;
            }
            if (!isSupportThresholdReachedEarly(_proposalId)) {
                return false;
            }
        } else {
            // Normal execution
            if (!isSupportThresholdReached(_proposalId)) {
                return false;
            }
        }
        if (!isMinParticipationReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// @notice Internal function to execute a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal {
        proposals[_proposalId].executed = true;

        _executeProposal(
            dao(),
            _proposalId,
            proposals[_proposalId].actions,
            proposals[_proposalId].allowFailureMap
        );
    }

    /// @notice Internal function to check if a proposal vote is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    /// @notice Internal function to update the plugin-wide governance settings.
    /// @param _governanceSettings The governance settings to be validated and updated.
    function _updateTokenGovernanceSettings(TokenGovernanceSettings calldata _governanceSettings) internal {
        // Require the support threshold value to be in the interval [0, 10^6-1],
        // because `>` comparision is used in the support criterion and >100% could never be reached.
        if (_governanceSettings.supportThreshold > RATIO_BASE - 1) {
            revert RatioOutOfBounds({
                limit: RATIO_BASE - 1,
                actual: _governanceSettings.supportThreshold
            });
        }

        // Require the minimum participation value to be in the interval [0, 10^6], because `>=` comparision is used
        // in the participation criterion.
        if (_governanceSettings.minParticipation > RATIO_BASE) {
            revert RatioOutOfBounds({ limit: RATIO_BASE, actual: _governanceSettings.minParticipation });
        }

        if (_governanceSettings.minDuration < 60 minutes) {
            revert MinDurationOutOfBounds({ limit: 60 minutes, actual: _governanceSettings.minDuration });
        }

        if (_governanceSettings.minDuration > 365 days) {
            revert MinDurationOutOfBounds({ limit: 365 days, actual: _governanceSettings.minDuration });
        }

        governanceSettings = _governanceSettings;

        emit TokenGovernanceSettingsUpdated({
            votingMode: _governanceSettings.votingMode,
            supportThreshold: _governanceSettings.supportThreshold,
            minParticipation: _governanceSettings.minParticipation,
            minDuration: _governanceSettings.minDuration,
            minProposerVotingPower: _governanceSettings.minProposerVotingPower
        });
    }

    /// @notice Validates and returns the proposal vote dates.
    /// @param _start The start date of the proposal vote.
    /// If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal vote. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal vote.
    /// @return endDate The validated end date of the proposal vote.
    function _validateProposalDates(uint64 _start, uint64 _end)
        internal
        view
        returns (uint64 startDate, uint64 endDate)
    {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({ limit: currentTimestamp, actual: startDate });
            }
        }

        // Since `minDuration` is limited to 1 year, `startDate + minDuration` can only overflow if
        // the `startDate` is after `type(uint64).max - minDuration`. In this case, the proposal creation will revert
        // and another date can be picked.
        uint64 earliestEndDate = startDate + governanceSettings.minDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({ limit: earliestEndDate, actual: endDate });
            }
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[49] private __gap;
}
