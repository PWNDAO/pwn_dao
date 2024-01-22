// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { IMembership } from "@aragon/osx/core/plugin/membership/IMembership.sol";
import { ProposalUpgradeable } from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import { PluginUUPSUpgradeable } from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import { RATIO_BASE, _applyRatioCeiled, RatioOutOfBounds } from "@aragon/osx/plugins/utils/Ratio.sol";

import { IPWNOptimisticGovernance } from "./IPWNOptimisticGovernance.sol";
import { IPWNEpochClock } from "../../interfaces/IPWNEpochClock.sol";

/// @title PWNOptimisticGovernancePlugin
/// @notice The implementation of optimistic governance plugins.
/// @dev This contract implements the `IPWNOptimisticGovernance` interface.
contract PWNOptimisticGovernancePlugin is
    IPWNOptimisticGovernance,
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

    /// @notice The ID of the permission required to create a proposal.
    bytes32 public constant PROPOSER_PERMISSION_ID = keccak256("PROPOSER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateOptimisticGovernanceSettings` function.
    bytes32 public constant UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION");

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 public constant OPTIMISTIC_GOVERNANCE_INTERFACE_ID =
        this.initialize.selector ^
        this.getProposal.selector ^
        this.updateOptimisticGovernanceSettings.selector;

    /// @notice The epoch clock contract.
    IPWNEpochClock private epochClock;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes) compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken;

    /// @notice A container for the optimistic majority settings that will be applied as parameters on proposal creation.
    /// @param minVetoRatio The support threshold value. Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    struct OptimisticGovernanceSettings {
        uint32 minVetoRatio;
        uint64 minDuration;
    }

    /// @notice The struct storing the governance settings.
    OptimisticGovernanceSettings private governanceSettings;

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

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param vetoTally The amount of voting power used to veto the proposal.
    /// @param vetoVoters The voters who have vetoed.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        uint256 vetoTally;
        mapping(address => bool) vetoVoters;
        IDAO.Action[] actions;
        uint256 allowFailureMap;
    }

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS                                       *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when the vetoing settings are updated.
    /// @param minVetoRatio The support threshold value.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    event OptimisticGovernanceSettingsUpdated(
        uint32 minVetoRatio,
        uint64 minDuration
    );

    /// @notice Emitted when a veto is cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the veto.
    /// @param votingPower The voting power behind this veto.
    event VetoCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 votingPower
    );

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the minimum duration value is out of bounds (less than four days or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if an account is not allowed to cast a veto. This can be because the challenge period
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have vetoing powers.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    error ProposalVetoingForbidden(uint256 proposalId, address account);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    // solhint-disable-next-line no-empty-blocks
    constructor() {
        // Is used as a proxy. Use initializer to setup initial properties.
    }

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _governanceSettings The vetoing settings.
    /// @param _token The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token used for voting.
    function initialize(
        IDAO _dao,
        OptimisticGovernanceSettings calldata _governanceSettings,
        IPWNEpochClock _epochClock,
        IVotesUpgradeable _token
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        epochClock = _epochClock;
        votingToken = _token;

        _updateOptimisticGovernanceSettings(_governanceSettings);
        emit MembershipContractAnnounced({ definingContract: address(_token) });
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL LIFECYCLE                                    *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPWNOptimisticGovernance
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate
    ) external auth(PROPOSER_PERMISSION_ID) returns (uint256 proposalId) {
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

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.snapshotEpoch = snapshotEpoch.toUint64();
        proposal_.parameters.minVetoVotingPower = _applyRatioCeiled(
            totalVotingPower_,
            minVetoRatio()
        );

        // Save gas
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length; ) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function veto(uint256 _proposalId) public virtual {
        address _voter = _msgSender();

        // Not using `canVeto` function here to save gas on `getPastVotes` call.

        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            revert ProposalVetoingForbidden({
                proposalId: _proposalId,
                account: _voter
            });
        }

        // The voter already vetoed.
        if (proposal_.vetoVoters[_voter]) {
            revert ProposalVetoingForbidden({
                proposalId: _proposalId,
                account: _voter
            });
        }

        // This could re-enter, though we can assume the governance token is not malicious
        uint256 votingPower = votingToken.getPastVotes(_voter, proposal_.parameters.snapshotEpoch);
        // The voter has no voting power.
        if (votingPower == 0) {
            revert ProposalVetoingForbidden({
                proposalId: _proposalId,
                account: _voter
            });
        }

        // Write the updated tally.
        proposal_.vetoTally += votingPower;
        proposal_.vetoVoters[_voter] = true;

        emit VetoCast({
            proposalId: _proposalId,
            voter: _voter,
            votingPower: votingPower
        });
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function execute(uint256 _proposalId) public virtual {
        if (!canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        proposals[_proposalId].executed = true;

        _executeProposal(
            dao(),
            _proposalId,
            proposals[_proposalId].actions,
            proposals[_proposalId].allowFailureMap
        );
    }


    /*----------------------------------------------------------*|
    |*  # SETTINGS                                              *|
    |*----------------------------------------------------------*/

    /// @notice Updates the governance settings.
    /// @param _governanceSettings The new governance settings.
    function updateOptimisticGovernanceSettings(OptimisticGovernanceSettings calldata _governanceSettings)
        public
        virtual
        auth(UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID)
    {
        _updateOptimisticGovernanceSettings(_governanceSettings);
    }


    /*----------------------------------------------------------*|
    |*  # GETTERS                                               *|
    |*----------------------------------------------------------*/

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return vetoTally The current voting power used to veto the proposal.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 _proposalId)
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 vetoTally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        vetoTally = proposal_.vetoTally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function totalVotingPower(uint256 _epoch) public view returns (uint256) {
        return votingToken.getPastTotalSupply(_epoch);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must have at least one voting power.
        return votingToken.getVotes(_account) > 0;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function hasVetoed(uint256 _proposalId, address _voter) public view returns (bool) {
        return proposals[_proposalId].vetoVoters[_voter];
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function canVeto(uint256 _proposalId, address _voter) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // The voter already vetoed.
        if (proposal_.vetoVoters[_voter]) {
            return false;
        }

        // The voter has no voting power.
        if (votingToken.getPastVotes(_voter, proposal_.parameters.snapshotEpoch) == 0) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function canExecute(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }
        // Check that the proposal vetoing time frame already expired
        else if (!_isProposalEnded(proposal_)) {
            return false;
        }
        // Check that not enough voters have vetoed the proposal
        else if (isMinVetoRatioReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function isMinVetoRatioReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        return proposal_.vetoTally >= proposal_.parameters.minVetoVotingPower;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function minVetoRatio() public view virtual returns (uint32) {
        return governanceSettings.minVetoRatio;
    }

    /// @inheritdoc IPWNOptimisticGovernance
    function minDuration() public view virtual returns (uint64) {
        return governanceSettings.minDuration;
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return
            _interfaceId == OPTIMISTIC_GOVERNANCE_INTERFACE_ID ||
            _interfaceId == type(IPWNOptimisticGovernance).interfaceId ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /// @notice Internal implementation
    function _updateOptimisticGovernanceSettings(OptimisticGovernanceSettings calldata _governanceSettings) internal {
        // Require the minimum veto ratio value to be in the interval [0, 10^6], because `>=` comparision is used.
        if (_governanceSettings.minVetoRatio == 0) {
            revert RatioOutOfBounds({
                limit: 1,
                actual: _governanceSettings.minVetoRatio
            });
        } else if (_governanceSettings.minVetoRatio > RATIO_BASE) {
            revert RatioOutOfBounds({
                limit: RATIO_BASE,
                actual: _governanceSettings.minVetoRatio
            });
        }

        if (_governanceSettings.minDuration < 4 days) {
            revert MinDurationOutOfBounds({
                limit: 4 days,
                actual: _governanceSettings.minDuration
            });
        } else if (_governanceSettings.minDuration > 365 days) {
            revert MinDurationOutOfBounds({
                limit: 365 days,
                actual: _governanceSettings.minDuration
            });
        }

        governanceSettings = _governanceSettings;

        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: _governanceSettings.minVetoRatio,
            minDuration: _governanceSettings.minDuration
        });
    }

    /// @notice Internal function to check if a proposal vote is open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    /// @notice Internal function to check if a proposal already ended.
    /// @param proposal_ The proposal struct.
    /// @return True if the end date of the proposal is already in the past, false otherwise.
    function _isProposalEnded(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return currentTime >= proposal_.parameters.endDate;
    }

    /// @notice Validates and returns the proposal vote dates.
    /// @param _start The start date of the proposal vote. If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal vote. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal vote.
    /// @return endDate The validated end date of the proposal vote.
    function _validateProposalDates(uint64 _start, uint64 _end)
        internal
        view
        virtual
        returns (uint64 startDate, uint64 endDate)
    {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({
                    limit: currentTimestamp,
                    actual: startDate
                });
            }
        }

        uint64 earliestEndDate = startDate + governanceSettings.minDuration; // Since `minDuration` will be less than 1 year, `startDate + minDuration` can only overflow if the `startDate` is after `type(uint64).max - minDuration`. In this case, the proposal creation will revert and another date can be picked.

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({
                    limit: earliestEndDate,
                    actual: endDate
                });
            }
        }
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables without shifting down storage in the inheritance chain (see [OpenZeppelin's guide about storage gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[50] private __gap;
}
