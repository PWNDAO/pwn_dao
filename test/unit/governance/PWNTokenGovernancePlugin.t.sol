// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { DaoUnauthorized } from "@aragon/osx/core/utils/auth.sol";
import { createERC1967Proxy } from "@aragon/osx/utils/Proxy.sol";
import { RATIO_BASE, RatioOutOfBounds, _applyRatioCeiled } from "@aragon/osx/plugins/utils/Ratio.sol";

import { IPWNTokenGovernance } from "src/governance/token/IPWNTokenGovernance.sol";
import { PWNTokenGovernancePlugin } from "src/governance/token/PWNTokenGovernancePlugin.sol";
import { IPWNEpochClock } from "src/interfaces/IPWNEpochClock.sol";
import { BitMaskLib } from "src/lib/BitMaskLib.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";

import { Base_Test } from "test/Base.t.sol";

abstract contract PWNTokenGovernancePlugin_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant DAO_SLOT = bytes32(uint256(201));
    bytes32 public constant PROPOSAL_COUNTER_SLOT = bytes32(uint256(301));
    bytes32 public constant EPOCH_CLOCK_SLOT = bytes32(uint256(351));
    bytes32 public constant VOTING_TOKEN_SLOT = bytes32(uint256(352));
    bytes32 public constant GOVERNANCE_SETTINGS_SLOT = bytes32(uint256(353));
    bytes32 public constant PROPOSALS_SLOT = bytes32(uint256(355));

    address public dao = makeAddr("dao");
    address public epochClock = makeAddr("epochClock");
    address public votingToken = makeAddr("votingToken");
    address public proposer = makeAddr("proposer"); // has min proposer voting power
    address public voter = makeAddr("voter"); // has some voting power

    uint64 public snapshotEpoch = 1;
    uint256 public pastTotalSupply = 100e18;
    uint256 public proposerVotingPower = 10e18;
    uint256 public voterVotingPower = 1e18;

    address public pluginImpl;
    PWNTokenGovernancePlugin public plugin;
    PWNTokenGovernancePlugin.TokenGovernanceSettings public settings;
    IDAO.Action[] public actions;
    address[] public voters;
    bytes32[] public execResults;

    function setUp() virtual public {
        pluginImpl = address(new PWNTokenGovernancePlugin());
        settings = PWNTokenGovernancePlugin.TokenGovernanceSettings({
            votingMode: IPWNTokenGovernance.VotingMode.Standard,
            supportThreshold: 500000, // 50:50
            minParticipation: 100000, // 10%
            minDuration: 1 days,
            minProposerVotingPower: proposerVotingPower
        });
        plugin = PWNTokenGovernancePlugin(
            createERC1967Proxy(
                pluginImpl,
                abi.encodeWithSelector(
                    PWNTokenGovernancePlugin.initialize.selector, dao, settings, epochClock, votingToken
                )
            )
        );

        vm.mockCall(dao, abi.encodeWithSelector(IDAO.hasPermission.selector), abi.encode(false));
        vm.mockCall(dao, abi.encodeWithSelector(IDAO.execute.selector), abi.encode(execResults, 0));
        vm.mockCall(
            epochClock,
            abi.encodeWithSelector(IPWNEpochClock.currentEpoch.selector),
            abi.encode(snapshotEpoch)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector),
            abi.encode(pastTotalSupply)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, proposer),
            abi.encode(proposerVotingPower)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, proposer),
            abi.encode(proposerVotingPower)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter),
            abi.encode(voterVotingPower)
        );

        vm.label(pluginImpl, "Token Plugin Impl");
        vm.label(address(plugin), "Token Plugin");
        vm.label(dao, "DAO");
        vm.label(epochClock, "Epoch Clock");
        vm.label(votingToken, "Voting Token");
        vm.label(proposer, "Proposer");
        vm.label(voter, "Voter");
    }

    function _mockProposal(
        uint256 _proposalId,
        bool _executed,
        IPWNTokenGovernance.VotingMode _votingMode,
        uint32 _supportThreshold,
        uint64 _startDate,
        uint64 _endDate,
        uint64 _snapshotEpoch,
        uint256 _minVotingPower,
        uint256 _abstainTally,
        uint256 _yesTally,
        uint256 _noTally,
        address[] memory _voters,
        IPWNTokenGovernance.VoteOption[] memory _voterOptions,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap
    ) internal {
        require(_voters.length == _voterOptions.length, "arrays length mismatch");

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(_proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(0), bytes32(uint256(_executed ? 1 : 0))); // executed
        bytes32 parametersData = abi.decode(
            abi.encodePacked(uint24(0), _snapshotEpoch, _endDate, _startDate, _supportThreshold, uint8(_votingMode)),
            (bytes32)
        );
        vm.store(address(plugin), proposalSlot.withArrayIndex(1), parametersData); // parameters
        vm.store(address(plugin), proposalSlot.withArrayIndex(2), bytes32(_minVotingPower)); // minVotingPower
        vm.store(address(plugin), proposalSlot.withArrayIndex(3), bytes32(_abstainTally)); // tally.abstain
        vm.store(address(plugin), proposalSlot.withArrayIndex(4), bytes32(_yesTally)); // tally.yes
        vm.store(address(plugin), proposalSlot.withArrayIndex(5), bytes32(_noTally)); // tally.no
        bytes32 votersSlot = proposalSlot.withArrayIndex(6);
        for (uint256 i; i < _voters.length; ++i) {
            vm.store( // voters
                address(plugin), votersSlot.withMappingKey(_voters[i]), bytes32(uint256(_voterOptions[i]))
            );
        }
        vm.store(address(plugin), proposalSlot.withArrayIndex(7), bytes32(_actions.length)); // actions length
        bytes32 actionsSlot = keccak256(abi.encodePacked(proposalSlot.withArrayIndex(7)));
        for (uint256 i; i < _actions.length; ++i) {
            vm.store( // to
                address(plugin), actionsSlot.withArrayIndex((3 * i) + 0), bytes32(uint256(uint160(_actions[i].to)))
            );
            vm.store(address(plugin), actionsSlot.withArrayIndex((3 * i) + 1), bytes32(_actions[i].value)); // value
            // do not mock action data (yet)
        }
        vm.store(address(plugin), proposalSlot.withArrayIndex(8), bytes32(_allowFailureMap)); // allowFailureMap
    }

    function _setVotingMode(uint256 _proposalId, IPWNTokenGovernance.VotingMode votingMode) internal {
        bytes32 proposalParametersSlot = PROPOSALS_SLOT.withMappingKey(_proposalId).withArrayIndex(1);
        bytes32 proposalParametersValue = vm.load(address(plugin), proposalParametersSlot);
        vm.store(
            address(plugin),
            proposalParametersSlot,
            proposalParametersValue | bytes32(uint256(votingMode))
        );

    }

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePlugin_Initialize_Test is PWNTokenGovernancePlugin_Test {
    using BitMaskLib for bytes32;
    using SlotComputingLib for bytes32;

    event MembershipContractAnnounced(address indexed definingContract);
    event TokenGovernanceSettingsUpdated(
        IPWNTokenGovernance.VotingMode votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );


    function testFuzz_shouldStoreProperties(
        address _dao,
        uint8 _votingMode,
        uint32 _supportThreshold,
        uint32 _minParticipation,
        uint64 _minDuration,
        uint256 _minProposerVotingPower,
        address _epochClock,
        address _votingToken
    ) external {
        settings.votingMode = IPWNTokenGovernance.VotingMode(uint8(bound(_votingMode, 0, 2)));
        settings.supportThreshold = uint32(bound(_supportThreshold, 1, RATIO_BASE - 1));
        settings.minParticipation = uint32(bound(_minParticipation, 1, RATIO_BASE));
        settings.minDuration = uint64(bound(_minDuration, 1 hours, 365 days));
        settings.minProposerVotingPower = _minProposerVotingPower;

        address _plugin = createERC1967Proxy(
            pluginImpl,
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.initialize.selector, _dao, settings, _epochClock, _votingToken
            )
        );

        bytes32 daoValue = vm.load(_plugin, DAO_SLOT);
        assertEq(address(uint160(uint256(daoValue))), _dao);

        bytes32 epochClockValue = vm.load(_plugin, EPOCH_CLOCK_SLOT);
        assertEq(address(uint160(uint256(epochClockValue))), _epochClock);

        bytes32 votingTokenValue = vm.load(_plugin, VOTING_TOKEN_SLOT);
        assertEq(address(uint160(uint256(votingTokenValue))), _votingToken);

        uint8 votingMode = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint8(0);
        assertEq(votingMode, uint8(settings.votingMode));

        uint32 supportThreshold = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint32(8);
        assertEq(supportThreshold, settings.supportThreshold);

        uint32 minParticipation = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint32(40);
        assertEq(minParticipation, settings.minParticipation);

        uint64 minDuration = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint64(72);
        assertEq(uint256(minDuration), settings.minDuration);

        bytes32 minProposerVotingPower = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT.withArrayIndex(1));
        assertEq(uint256(minProposerVotingPower), settings.minProposerVotingPower);
    }

    function testFuzz_shouldEmit_MembershipContractAnnounced(address _votingToken) external {
        vm.expectEmit();
        emit MembershipContractAnnounced({ definingContract: _votingToken });

        createERC1967Proxy(
            pluginImpl,
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.initialize.selector, dao, settings, epochClock, _votingToken
            )
        );
    }

    function testFuzz_shouldEmit_TokenGovernanceSettingsUpdated(
        uint8 _votingMode,
        uint32 _supportThreshold,
        uint32 _minParticipation,
        uint64 _minDuration,
        uint256 _minProposerVotingPower
    ) external {
        settings.votingMode = IPWNTokenGovernance.VotingMode(uint8(bound(_votingMode, 0, 2)));
        settings.supportThreshold = uint32(bound(_supportThreshold, 1, RATIO_BASE - 1));
        settings.minParticipation = uint32(bound(_minParticipation, 1, RATIO_BASE));
        settings.minDuration = uint64(bound(_minDuration, 1 hours, 365 days));
        settings.minProposerVotingPower = _minProposerVotingPower;

        vm.expectEmit();
        emit TokenGovernanceSettingsUpdated({
            votingMode: settings.votingMode,
            supportThreshold: settings.supportThreshold,
            minParticipation: settings.minParticipation,
            minDuration: settings.minDuration,
            minProposerVotingPower: settings.minProposerVotingPower
        });

        createERC1967Proxy(
            pluginImpl,
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.initialize.selector, dao, settings, epochClock, votingToken
            )
        );
    }

}


/*----------------------------------------------------------*|
|*  # CREATE PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePlugin_CreateProposal_Test is PWNTokenGovernancePlugin_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );


    function testFuzz_shouldFail_whenCallerWithoutMinPower(uint256 power) external {
        power = bound(power, 0, settings.minProposerVotingPower - 1);

        vm.mockCall(
            votingToken, abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, proposer), abi.encode(power)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalCreationForbidden.selector, proposer));
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function test_shouldGetCurrentEpochFromEpochClock() external {
        vm.expectCall(epochClock, abi.encodeWithSelector(IPWNEpochClock.currentEpoch.selector));

        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenNoVotingPower() external {
        vm.mockCall(votingToken, abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector), abi.encode(0));

        vm.expectRevert(abi.encodeWithSelector(PWNTokenGovernancePlugin.NoVotingPower.selector));
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenNoPower_whenMinPowerZero_whenVoting() external {
        // set minProposerVotingPower to 0
        vm.store(address(plugin), GOVERNANCE_SETTINGS_SLOT.withArrayIndex(1), bytes32(0));
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, proposer),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, proposer),
            abi.encode(uint256(0))
        );
        uint256 expectedProposalId = uint256(vm.load(address(plugin), PROPOSAL_COUNTER_SLOT));

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.VoteCastForbidden.selector,
                expectedProposalId, proposer, IPWNTokenGovernance.VoteOption.Yes
            )
        );
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: false
        });
    }

    function test_shouldCreateProposal_whenNoPower_whenMinPowerZero_whenNoVoting() external {
        // set minProposerVotingPower to 0
        vm.store(address(plugin), GOVERNANCE_SETTINGS_SLOT.withArrayIndex(1), bytes32(0));
        vm.mockCall(
            votingToken, abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, proposer), abi.encode(uint256(0))
        );

        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function testFuzz_shouldFail_whenInvalidStartOrEndDate(uint256 seed) external {
        vm.warp(100_000); // make some space for the test

        // test start date
        uint256 startDate = bound(seed, 1, block.timestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.DateOutOfBounds.selector, block.timestamp, startDate)
        );
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: uint64(startDate),
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });

        // test end date
        uint256 earliesEndDate = block.timestamp + settings.minDuration;
        uint256 endDate = bound(seed, 1, earliesEndDate - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.DateOutOfBounds.selector, earliesEndDate, endDate)
        );
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: uint64(endDate),
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function testFuzz_shouldStoreProposal(
        uint256 _snapshotEpoch,
        uint256 _totalPower,
        uint256 _startDat,
        uint256 _endDate,
        uint256 _allowFailureMap
    ) external {
        uint256 snapshotEpoch = uint64(bound(_snapshotEpoch, 1, 1000));
        pastTotalSupply = bound(_totalPower, 1e6, 100_000_000e18);
        uint256 startDate = bound(_startDat, block.timestamp, block.timestamp + 1000);
        uint256 endDate = bound(_endDate, startDate + settings.minDuration, startDate + settings.minDuration + 1000);

        vm.mockCall(
            epochClock, abi.encodeWithSelector(IPWNEpochClock.currentEpoch.selector), abi.encode(snapshotEpoch)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, snapshotEpoch),
            abi.encode(pastTotalSupply)
        );

        actions.push(IDAO.Action({
            to: makeAddr("action1.addr"),
            value: 10,
            data: "data1"
        }));
        actions.push(IDAO.Action({
            to: makeAddr("action2.addr"),
            value: 901,
            data: "data2"
        }));

        vm.prank(proposer);
        uint256 proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: _allowFailureMap,
            _startDate: uint64(startDate),
            _endDate: uint64(endDate),
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);

        assertEq( // executed
            vm.load(address(plugin), proposalSlot.withArrayIndex(0)).maskUint8(0),
            0
        );
        assertEq( // voting mode
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint8(0),
            uint8(settings.votingMode)
        );
        assertEq( // supportThreshold
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint32(8),
            uint32(settings.supportThreshold)
        );
        assertEq( // startDate
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(40),
            uint64(startDate)
        );
        assertEq( // endDate
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(104),
            uint64(endDate)
        );
        assertEq( // snapshotEpoch
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(168),
            uint64(snapshotEpoch)
        );
        assertEq( // minVotingPower
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(2))),
            _applyRatioCeiled(pastTotalSupply, settings.minParticipation)
        );
        assertEq( // actions length
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(7))),
            2
        );
        assertEq( // allowFailureMap
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(8))),
            _allowFailureMap
        );
        // actions
        bytes32 actionsSlot = keccak256(abi.encodePacked(proposalSlot.withArrayIndex(7)));
        assertEq(
            address(uint160(uint256(vm.load(address(plugin), actionsSlot.withArrayIndex(0))))),
            actions[0].to
        );
        assertEq(
            uint256(vm.load(address(plugin), actionsSlot.withArrayIndex(1))),
            actions[0].value
        );
        // skip action data check
        assertEq(
            address(uint160(uint256(vm.load(address(plugin), actionsSlot.withArrayIndex(3))))),
            actions[1].to
        );
        assertEq(
            uint256(vm.load(address(plugin), actionsSlot.withArrayIndex(4))),
            actions[1].value
        );
        // skip action data check
    }

    function testFuzz_shouldIncreaseAndReturnProposalId(uint256 initialProposalId) external {
        initialProposalId = bound(initialProposalId, 0, type(uint256).max - 2);
        vm.store(address(plugin), PROPOSAL_COUNTER_SLOT, bytes32(initialProposalId));

        vm.prank(proposer);
        uint256 proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
        assertEq(proposalId, initialProposalId);

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
        assertEq(proposalId, initialProposalId + 1);
    }

    function test_shouldEmit_ProposalCreated() external {
        vm.store(address(plugin), PROPOSAL_COUNTER_SLOT, bytes32(uint256(101)));
        vm.warp(432);

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 101,
            creator: proposer,
            startDate: 432,
            endDate: 432 + settings.minDuration,
            metadata: "",
            actions: actions,
            allowFailureMap: 0
        });

        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function test_shouldVote_whenVoteOptionProvided() external {
        // abstain voting option
        vm.prank(proposer);
        uint256 proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Abstain,
            _tryEarlyExecution: false
        });

        bytes32 abstainTally = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(3));
        assertEq(uint256(abstainTally), proposerVotingPower);

        // yes voting option
        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: false
        });

        bytes32 yesTally = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(4));
        assertEq(uint256(yesTally), proposerVotingPower);

        // no voting option
        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.No,
            _tryEarlyExecution: false
        });

        bytes32 noTally = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(5));
        assertEq(uint256(noTally), proposerVotingPower);
    }

    function test_shouldExecute_whenVoteOptionProvided_whenTryEarlyExecution_whenEarlyExecutionMode_whenSupportThresholdReachedEarly() external {
        bytes32 settingsValue = vm.load(address(plugin), GOVERNANCE_SETTINGS_SLOT);
        vm.store(
            address(plugin),
            GOVERNANCE_SETTINGS_SLOT,
            settingsValue | bytes32(uint256(IPWNTokenGovernance.VotingMode.EarlyExecution))
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, proposer),
            abi.encode(pastTotalSupply / 2 + 1) // expecting supportThreshold to be 50%
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, proposer),
            abi.encode(pastTotalSupply / 2 + 1) // expecting supportThreshold to be 50%
        );

        vm.prank(proposer);
        uint256 proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: true
        });

        bytes32 executed = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId));
        assertEq(uint256(executed), 1);
    }

}


/*----------------------------------------------------------*|
|*  # VOTE                                                  *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePlugin_Vote_Test is PWNTokenGovernancePlugin_Test {
    using SlotComputingLib for bytes32;

    uint256 public proposalId;
    uint256 public timestamp = 1000;
    IPWNTokenGovernance.VoteOption public voteOption;

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        IPWNTokenGovernance.VoteOption voteOption,
        uint256 votingPower
    );

    function setUp() override public {
        super.setUp();

        vm.warp(timestamp);

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }


    function testFuzz_shouldFail_whenProposalNotStarted(uint256 _timestamp) external {
        vm.warp(bound(_timestamp, 0, timestamp - 1));
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function testFuzz_shouldFail_whenProposalEnded(uint256 _timestamp) external {
        uint256 endDate = timestamp + settings.minDuration;
        vm.warp(bound(_timestamp, endDate + 1, endDate + 1000));
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenProposalExecuted() external {
        vm.store(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId), bytes32(uint256(1)));
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenVoteOptionNone() external {
        voteOption = IPWNTokenGovernance.VoteOption.None;

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenNoVotingPower() external {
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter),
            abi.encode(uint256(0))
        );
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldFail_whenAlreadyVoted_whenNotVoteReplacementMode() external {
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.VoteCastForbidden.selector, proposalId, voter, voteOption)
        );
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldVote_whenAlreadyVoted_whenVoteReplacementMode() external {
        _setVotingMode(proposalId, IPWNTokenGovernance.VotingMode.VoteReplacement);
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: false
        });

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption.No,
            _tryEarlyExecution: false
        });
    }

    function testFuzz_shouldUpdateTally(uint8 _voteOption, uint256 _votingPower) external {
        _voteOption = uint8(bound(_voteOption, 1, 3));
        _votingPower = bound(_votingPower, 1, type(uint256).max);
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter),
            abi.encode(_votingPower)
        );

        uint256 tallyIndex = 2 + _voteOption;
        bytes32 tallyValue = vm.load(
            address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(tallyIndex)
        );
        assertEq(uint256(tallyValue), 0);

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_voteOption),
            _tryEarlyExecution: false
        });

        tallyValue = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(tallyIndex));
        assertEq(uint256(tallyValue), _votingPower);
    }

    function testFuzz_shouldUpdateTally_whenVoteReplacementMode(uint8 _voteOption, uint256 _votingPower) external {
        _setVotingMode(proposalId, IPWNTokenGovernance.VotingMode.VoteReplacement);
        _voteOption = uint8(bound(_voteOption, 1, 3));
        _votingPower = bound(_votingPower, 1, type(uint256).max);
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter),
            abi.encode(_votingPower)
        );
        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);

        // vote
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_voteOption),
            _tryEarlyExecution: false
        });

        // check that vote option tally was updated
        bytes32 tallyValue = vm.load(address(plugin), proposalSlot.withArrayIndex(2 + _voteOption));
        assertEq(uint256(tallyValue), _votingPower);

        // pick another vote option
        uint8 _replacementVoteOption = _voteOption + 1;
        _replacementVoteOption = _replacementVoteOption > 3 ? 1 : _replacementVoteOption;

        // vote again
        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_replacementVoteOption),
            _tryEarlyExecution: false
        });

        // check that previous vote option tally was reset
        tallyValue = vm.load(address(plugin), proposalSlot.withArrayIndex(2 + _voteOption));
        assertEq(uint256(tallyValue), 0);
        // check that new vote option tally was updated
        tallyValue = vm.load(address(plugin), proposalSlot.withArrayIndex(2 + _replacementVoteOption));
        assertEq(uint256(tallyValue), _votingPower);
    }

    function testFuzz_shouldStoreVoteOption(uint8 _voteOption) external {
        _voteOption = uint8(bound(_voteOption, 1, 3));

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_voteOption),
            _tryEarlyExecution: false
        });

        bytes32 voteOptionSlot = PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(6).withMappingKey(voter);
        bytes32 voteOptionValue = vm.load(address(plugin), voteOptionSlot);
        assertEq(uint256(voteOptionValue), uint256(_voteOption));
    }

    function testFuzz_shouldUpdateVoteOption_whenVoteReplacementMode(uint8 _voteOption) external {
        _setVotingMode(proposalId, IPWNTokenGovernance.VotingMode.VoteReplacement);
        _voteOption = uint8(bound(_voteOption, 1, 3));

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_voteOption),
            _tryEarlyExecution: false
        });

        bytes32 voteOptionSlot = PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(6).withMappingKey(voter);
        bytes32 voteOptionValue = vm.load(address(plugin), voteOptionSlot);
        assertEq(uint256(voteOptionValue), uint256(_voteOption));

        uint8 _replacementVoteOption = _voteOption + 1;
        _replacementVoteOption = _replacementVoteOption > 3 ? 1 : _replacementVoteOption;

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption(_replacementVoteOption),
            _tryEarlyExecution: false
        });

        voteOptionValue = vm.load(address(plugin), voteOptionSlot);
        assertEq(uint256(voteOptionValue), uint256(_replacementVoteOption));
    }

    function test_shouldEmit_VoteCast() external {
        voteOption = IPWNTokenGovernance.VoteOption.Yes;

        vm.expectEmit();
        emit VoteCast({
            proposalId: proposalId,
            voter: voter,
            voteOption: voteOption,
            votingPower: voterVotingPower
        });

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: voteOption,
            _tryEarlyExecution: false
        });
    }

    function test_shouldExecute_whenTryEarlyExecution_whenEarlyExecutionMode_whenSupportThresholdReachedEarly() external {
        _setVotingMode(proposalId, IPWNTokenGovernance.VotingMode.EarlyExecution);
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter),
            abi.encode(pastTotalSupply / 2 + 1) // expecting supportThreshold to be 50%
        );

        vm.prank(voter);
        plugin.vote({
            _proposalId: proposalId,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: true
        });

        bytes32 executed = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId));
        assertEq(uint256(executed), 1);
    }

}


/*----------------------------------------------------------*|
|*  # EXECUTE                                               *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePlugin_Execute_Test is PWNTokenGovernancePlugin_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    uint256 public proposalId;
    uint256 public timestamp = 1000;

    event ProposalExecuted(uint256 indexed proposalId);

    function setUp() override public {
        super.setUp();

        vm.warp(timestamp);

        actions.push( // dummy action
            IDAO.Action({
                to: makeAddr("action1.addr"),
                value: 10,
                data: "data1"
            })
        );

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.None,
            _tryEarlyExecution: false
        });
    }

    function _mockProposalPassed() internal {
        // proposal must have yes votes > no votes
        // and at least 10% of total voting power
        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(4), bytes32(uint256(pastTotalSupply / 10 + 1)));
    }

    function _skipWaitingPeriod() internal {
        vm.warp(timestamp + settings.minDuration + 1);
    }


    function test_shouldFail_whenAlreadyExecuted() external {
        vm.store(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId), bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldFail_whenNoEarlyExecutionMode_whenProposalNotEnded(uint256 warp) external {
        warp = bound(warp, 0, settings.minDuration - 1);
        vm.warp(timestamp + warp);

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldFail_whenNoEarlyExecutionMode_whenSupportThresholdNotReached() external {
        _skipWaitingPeriod();

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(4), bytes32(uint256(pastTotalSupply / 10 + 1)));
        vm.store(address(plugin), proposalSlot.withArrayIndex(5), bytes32(uint256(pastTotalSupply / 10 + 1)));

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldFail_whenEarlyExecutionMode_whenSupportThresholdNotReachedEarly(uint256 _votingPower) external {
        _votingPower = bound(_votingPower, 1, pastTotalSupply / 2);
        _setVotingMode(proposalId, IPWNTokenGovernance.VotingMode.EarlyExecution);

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(4), bytes32(_votingPower));

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldFail_whenMinParticipationNotReached(uint256 _votingPower) external {
        _votingPower = bound(_votingPower, 1, pastTotalSupply / 10 - 1);
        _skipWaitingPeriod();

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(4), bytes32(_votingPower));

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldStoreExecutedProposal() external {
        _mockProposalPassed();
        _skipWaitingPeriod();

        plugin.execute({ _proposalId: proposalId });

        bytes32 executedValue = vm.load(address(plugin), PROPOSALS_SLOT.withMappingKey(proposalId));
        assertEq(executedValue, bytes32(uint256(1)));
    }

    function test_shouldExecuteActions() external {
        _mockProposalPassed();
        _skipWaitingPeriod();

        vm.expectCall(dao, abi.encodeWithSelector(IDAO.execute.selector, proposalId, actions, uint256(0)));

        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldBeAbleToExecuteByAnyAddress(address caller) external checkAddress(caller) {
        _mockProposalPassed();
        _skipWaitingPeriod();

        vm.prank(caller);
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldEmit_ProposalExecuted() external {
        _mockProposalPassed();
        _skipWaitingPeriod();

        vm.expectEmit();
        emit ProposalExecuted({ proposalId: proposalId });

        plugin.execute({ _proposalId: proposalId });
    }

}
