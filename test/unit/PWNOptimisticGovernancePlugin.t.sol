// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { DaoUnauthorized } from "@aragon/osx/core/utils/auth.sol";
import { createERC1967Proxy } from "@aragon/osx/utils/Proxy.sol";
import { RATIO_BASE, RatioOutOfBounds, _applyRatioCeiled } from "@aragon/osx/plugins/utils/Ratio.sol";

import { PWNOptimisticGovernancePlugin } from "src/governance/optimistic/PWNOptimisticGovernancePlugin.sol";
import { IPWNEpochClock } from "src/interfaces/IPWNEpochClock.sol";
import { BitMaskLib } from "src/lib/BitMaskLib.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";

import { Base_Test, console2 } from "../Base.t.sol";

abstract contract PWNOptimisticGovernancePlugin_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant DAO_SLOT = bytes32(uint256(201));
    bytes32 public constant PROPOSAL_COUNTER_SLOT = bytes32(uint256(301));
    bytes32 public constant EPOCH_CLOCK_SLOT = bytes32(uint256(351));
    bytes32 public constant VOTING_TOKEN_SLOT = bytes32(uint256(352));
    bytes32 public constant GOVERNANCE_SETTINGS_SLOT = bytes32(uint256(353));
    bytes32 public constant PROPOSALS_SLOT = bytes32(uint256(354));

    address public dao = makeAddr("dao");
    address public epochClock = makeAddr("epochClock");
    address public votingToken = makeAddr("votingToken");
    address public proposer = makeAddr("proposer");
    address public voter = makeAddr("voter");

    uint64 public snapshotEpoch = 1;
    uint256 public pastTotalSupply = 100e18;

    address public pluginImpl;
    PWNOptimisticGovernancePlugin public plugin;
    PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings public settings;
    IDAO.Action[] public actions;
    address[] public vetoVoters;

    function setUp() virtual public {
        pluginImpl = address(new PWNOptimisticGovernancePlugin());
        settings = PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings({
            minVetoRatio: 100000, // 10%
            minDuration: 5 days
        });
        plugin = PWNOptimisticGovernancePlugin(
            createERC1967Proxy(
                pluginImpl,
                abi.encodeCall(
                    PWNOptimisticGovernancePlugin.initialize,
                    (IDAO(dao), settings, IPWNEpochClock(epochClock), IVotesUpgradeable(votingToken))
                )
            )
        );

        // nobody but the proposer has `PROPOSER_PERMISSION_ID` permission
        vm.mockCall(dao, abi.encodeWithSelector(IDAO.hasPermission.selector), abi.encode(false));
        vm.mockCall(
            dao,
            abi.encodeWithSelector(
                IDAO.hasPermission.selector,
                address(plugin), proposer, plugin.PROPOSER_PERMISSION_ID()
            ),
            abi.encode(true)
        );
        // mock epoch clock
        vm.mockCall(
            epochClock, abi.encodeWithSelector(IPWNEpochClock.currentEpoch.selector), abi.encode(snapshotEpoch)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector),
            abi.encode(pastTotalSupply)
        );

        vm.label(pluginImpl, "Optimistic Plugin Impl");
        vm.label(address(plugin), "Optimistic Plugin");
        vm.label(dao, "DAO");
        vm.label(epochClock, "Epoch Clock");
        vm.label(votingToken, "Voting Token");
        vm.label(proposer, "Proposer");
    }

    function _mockProposal(
        uint256 _proposalId,
        bool _executed,
        uint64 _startDate,
        uint64 _endDate,
        uint64 _snapshotEpoch,
        uint256 _minVetoVotingPower,
        uint256 _vetoTally,
        address[] memory _vetoVoters,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap
    ) internal {
        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(_proposalId);
        vm.store(address(plugin), proposalSlot.withArrayIndex(0), bytes32(uint256(_executed ? 1 : 0))); // executed
        bytes32 parametersData = abi.decode(
            abi.encodePacked(uint64(0), _snapshotEpoch, _endDate, _startDate), (bytes32)
        );
        vm.store(address(plugin), proposalSlot.withArrayIndex(1), parametersData); // parameters
        vm.store(address(plugin), proposalSlot.withArrayIndex(2), bytes32(_minVetoVotingPower)); // minVetoVotingPower
        vm.store(address(plugin), proposalSlot.withArrayIndex(3), bytes32(_vetoTally)); // vetoTally
        for (uint256 i; i < _vetoVoters.length; ++i) {
            vm.store( // vetoVoters
                address(plugin), proposalSlot.withArrayIndex(4).withMappingKey(_vetoVoters[i]), bytes32(uint256(1))
            );
        }
        vm.store(address(plugin), proposalSlot.withArrayIndex(5), bytes32(_actions.length)); // actions length
        bytes32 actionsSlot = keccak256(abi.encodePacked(proposalSlot.withArrayIndex(5)));
        for (uint256 i; i < _actions.length; ++i) {
            vm.store( // to
                address(plugin), actionsSlot.withArrayIndex((3 * i) + 0), bytes32(uint256(uint160(_actions[i].to)))
            );
            vm.store(address(plugin), actionsSlot.withArrayIndex((3 * i) + 1), bytes32(_actions[i].value)); // value
            // do not mock action data (yet)
        }
        vm.store(address(plugin), proposalSlot.withArrayIndex(6), bytes32(_allowFailureMap)); // allowFailureMap
    }

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_Initialize_Test is PWNOptimisticGovernancePlugin_Test {
    using BitMaskLib for bytes32;

    event MembershipContractAnnounced(address indexed definingContract);


    function testFuzz_shouldStoreProperties(
        address _dao, uint32 _minVetoRatio, uint64 _minDuration, address _epochClock, address _votingToken
    ) external {
        settings.minVetoRatio = uint32(bound(_minVetoRatio, 1, RATIO_BASE));
        settings.minDuration = uint64(bound(_minDuration, 4 days, 365 days));

        address _plugin = createERC1967Proxy(
            pluginImpl,
            abi.encodeCall(
                PWNOptimisticGovernancePlugin.initialize,
                (IDAO(_dao), settings, IPWNEpochClock(_epochClock), IVotesUpgradeable(_votingToken))
            )
        );

        bytes32 daoValue = vm.load(_plugin, DAO_SLOT);
        assertEq(address(uint160(uint256(daoValue))), _dao);

        bytes32 epochClockValue = vm.load(_plugin, EPOCH_CLOCK_SLOT);
        assertEq(address(uint160(uint256(epochClockValue))), _epochClock);

        bytes32 votingTokenValue = vm.load(_plugin, VOTING_TOKEN_SLOT);
        assertEq(address(uint160(uint256(votingTokenValue))), _votingToken);

        uint32 minVetoRatio = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint32(0);
        assertEq(uint256(minVetoRatio), settings.minVetoRatio);

        uint64 minDuration = vm.load(_plugin, GOVERNANCE_SETTINGS_SLOT).maskUint64(32);
        assertEq(uint256(minDuration), settings.minDuration);
    }

    function testFuzz_shouldEmit_MembershipContractAnnounced(address _votingToken) external {
        vm.expectEmit();
        emit MembershipContractAnnounced(_votingToken);

        createERC1967Proxy(
            pluginImpl,
            abi.encodeCall(
                PWNOptimisticGovernancePlugin.initialize,
                (IDAO(dao), settings, IPWNEpochClock(epochClock), IVotesUpgradeable(_votingToken))
            )
        );
    }

}


/*----------------------------------------------------------*|
|*  # CREATE PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_CreateProposal_Test is PWNOptimisticGovernancePlugin_Test {
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


    function testFuzz_shouldFail_whenCallerWithoutPermission(address caller) external checkAddress(caller) {
        vm.assume(caller != proposer);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, dao, address(plugin), caller, plugin.PROPOSER_PERMISSION_ID()
            )
        );
        vm.prank(caller);
        plugin.createProposal({ _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0 });
    }

    function test_shouldGetCurrentEpochFromEpochClock() external {
        vm.expectCall(epochClock, abi.encodeWithSelector(IPWNEpochClock.currentEpoch.selector));

        vm.prank(proposer);
        plugin.createProposal({ _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0 });
    }

    function test_shouldFail_whenNoVotingPower() external {
        vm.mockCall(votingToken, abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector), abi.encode(0));

        vm.expectRevert(abi.encodeWithSelector(PWNOptimisticGovernancePlugin.NoVotingPower.selector));
        vm.prank(proposer);
        plugin.createProposal({ _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0 });
    }

    function testFuzz_shouldFail_whenInvalidStartOrEndDate(uint256 seed) external {
        vm.warp(100_000); // make some space for the test

        // test start date
        uint256 startDate = bound(seed, 1, block.timestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.DateOutOfBounds.selector, block.timestamp, startDate)
        );
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: uint64(startDate), _endDate: 0
        });

        // test end date
        uint256 earliesEndDate = block.timestamp + settings.minDuration;
        uint256 endDate = bound(seed, 1, earliesEndDate - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.DateOutOfBounds.selector, earliesEndDate, endDate)
        );
        vm.prank(proposer);
        plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: uint64(endDate)
        });
    }

    function testFuzz_shouldStoreProposal(
        uint256 _snapshotEpoch, uint256 _totalPower, uint256 _startDat, uint256 _endDate, uint256 _allowFailureMap
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
            _endDate: uint64(endDate)
        });

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);

        assertEq( // executed
            vm.load(address(plugin), proposalSlot.withArrayIndex(0)).maskUint8(0),
            0
        );
        assertEq( // startDate
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(0),
            uint64(startDate)
        );
        assertEq( // endDate
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(64),
            uint64(endDate)
        );
        assertEq( // snapshotEpoch
            vm.load(address(plugin), proposalSlot.withArrayIndex(1)).maskUint64(128),
            uint64(snapshotEpoch)
        );
        assertEq( // minVetoVotingPower
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(2))),
            _applyRatioCeiled(pastTotalSupply, settings.minVetoRatio)
        );
        assertEq( // vetoTally
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(3))),
            0
        );
        assertEq( // actions length
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(5))),
            2
        );
        assertEq( // allowFailureMap
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(6))),
            _allowFailureMap
        );
        // actions
        bytes32 actionsSlot = keccak256(abi.encodePacked(proposalSlot.withArrayIndex(5)));
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
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0
        });
        assertEq(proposalId, initialProposalId);

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0
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
        plugin.createProposal({ _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0 });
    }

}


/*----------------------------------------------------------*|
|*  # VETO                                                  *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_Veto_Test is PWNOptimisticGovernancePlugin_Test {
    using SlotComputingLib for bytes32;

    uint256 public proposalId;
    uint256 public voterPower = 1e18;

    event VetoCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 votingPower
    );

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter, snapshotEpoch),
            abi.encode(voterPower)
        );

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0
        });

        vm.label(voter, "Voter");
    }


    function testFuzz_shouldFail_whenProposalNotStarted(uint256 startDate) external {
        uint256 timestamp = 1000;
        vm.warp(timestamp);
        startDate = bound(startDate, timestamp + 1, timestamp + 1000);

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: uint64(startDate), _endDate: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalVetoingForbidden.selector, proposalId, voter)
        );
        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

    function testFuzz_shouldFail_whenProposalEnded(uint256 timestamp) external {
        uint256 endDate = block.timestamp + settings.minDuration;
        timestamp = bound(timestamp, endDate + 1, endDate + 1000);
        vm.warp(timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalVetoingForbidden.selector, proposalId, voter)
        );
        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

    function test_shouldFail_whenVoterAlreadyVetoed() external {
        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalVetoingForbidden.selector, proposalId, voter)
        );
        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

    function test_shouldFail_whenVoterHasNoPower() external {
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter, snapshotEpoch),
            abi.encode(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalVetoingForbidden.selector, proposalId, voter)
        );
        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

    function testFuzz_shouldStoreVeto(uint256 vetoPower) external {
        vetoPower = bound(vetoPower, 1, voterPower);
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter, snapshotEpoch),
            abi.encode(vetoPower)
        );

        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        assertEq( // vetoTally
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(3))),
            vetoPower // excpecting vetoTally to be zero
        );
        assertEq( // vetoVoters
            uint256(vm.load(address(plugin), proposalSlot.withArrayIndex(4).withMappingKey(voter))),
            1
        );
    }

    function testFuzz_shouldBeAbleToVetoDuringVotingPeriod(uint256 warp) external {
        warp = bound(warp, 0, settings.minDuration - 1);
        vm.warp(block.timestamp + warp);

        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

    function test_shouldEmit_VetoCast() external {
        vm.expectEmit();
        emit VetoCast({
            proposalId: proposalId,
            voter: voter,
            votingPower: voterPower
        });

        vm.prank(voter);
        plugin.veto({ _proposalId: proposalId });
    }

}


/*----------------------------------------------------------*|
|*  # EXECUTE                                               *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_Execute_Test is PWNOptimisticGovernancePlugin_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    uint256 public proposalId;
    bytes[] public execResults;

    event ProposalExecuted(uint256 indexed proposalId);

    function setUp() override public {
        super.setUp();

        vm.mockCall(dao, abi.encodeWithSelector(IDAO.execute.selector), abi.encode(execResults, uint256(0)));

        actions.push( // dummy action
            IDAO.Action({
                to: makeAddr("action1.addr"),
                value: 10,
                data: "data1"
            })
        );

        vm.prank(proposer);
        proposalId = plugin.createProposal({
            _metadata: "", _actions: actions, _allowFailureMap: 0, _startDate: 0, _endDate: 0
        });
    }

    function _skipWaitingPeriod() internal {
        vm.warp(block.timestamp + settings.minDuration + 1);
    }


    function test_shouldFail_whenAlreadyExecuted() external {
        _skipWaitingPeriod();

        vm.prank(proposer);
        plugin.execute({ _proposalId: proposalId });

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldFail_whenProposalNotEnded(uint256 warp) external {
        warp = bound(warp, 0, settings.minDuration - 1);
        vm.warp(block.timestamp + warp);

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldFail_whenProposalVetoed() external {
        _skipWaitingPeriod();

        vm.store(
            address(plugin),
            PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(3),
            bytes32(_applyRatioCeiled(pastTotalSupply, settings.minVetoRatio))
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNOptimisticGovernancePlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldStoreExecutedProposal() external {
        _skipWaitingPeriod();

        plugin.execute({ _proposalId: proposalId });

        bytes32 proposalSlot = PROPOSALS_SLOT.withMappingKey(proposalId);
        assertEq( // executed
            vm.load(address(plugin), proposalSlot.withArrayIndex(0)).maskUint8(0),
            1
        );
    }

    function test_shouldExecuteActions() external {
        _skipWaitingPeriod();

        vm.expectCall(dao, abi.encodeWithSelector(IDAO.execute.selector, proposalId, actions, uint256(0)));

        plugin.execute({ _proposalId: proposalId });
    }

    function testFuzz_shouldBeAbleToExecute(address caller) external checkAddress(caller) {
        _skipWaitingPeriod();

        vm.prank(caller);
        plugin.execute({ _proposalId: proposalId });
    }

    function test_shouldEmit_ProposalExecuted() external {
        _skipWaitingPeriod();

        vm.expectEmit();
        emit ProposalExecuted({ proposalId: proposalId });

        plugin.execute({ _proposalId: proposalId });
    }

}


/*----------------------------------------------------------*|
|*  # UPDATE GOVERNANCE SETTINGS                            *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_UpdateGovernanceSettings_Test is PWNOptimisticGovernancePlugin_Test {
    using SlotComputingLib for bytes32;
    using BitMaskLib for bytes32;

    address public admin = makeAddr("admin");

    event OptimisticGovernanceSettingsUpdated(
        uint32 minVetoRatio,
        uint64 minDuration
    );

    function setUp() override public {
        super.setUp();

        // nobody but the admin has `UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID` permission
        vm.mockCall(
            dao,
            abi.encodeWithSelector(
                IDAO.hasPermission.selector,
                address(plugin), admin, plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
            ),
            abi.encode(true)
        );
    }


    function test_shouldFail_whenCallerWithoutPermission(address caller) external checkAddress(caller) {
        vm.assume(caller != admin);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                dao, address(plugin), caller, plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
            )
        );
        vm.prank(caller);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });
    }

    function test_shouldFail_whenMinVetoRatioOutOfBounds() external {
        settings.minVetoRatio = 0;
        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, 1, settings.minVetoRatio));
        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });

        settings.minVetoRatio = uint32(RATIO_BASE + 1);
        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE, settings.minVetoRatio));
        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });
    }

    function test_shouldFail_whenMinDurationOutOfBounds() external {
        settings.minDuration = 4 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                PWNOptimisticGovernancePlugin.MinDurationOutOfBounds.selector, 4 days, settings.minDuration
            )
        );
        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });

        settings.minDuration = 365 days + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                PWNOptimisticGovernancePlugin.MinDurationOutOfBounds.selector, 365 days, settings.minDuration
            )
        );
        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });
    }

    function testFuzz_shouldStoreNewSettings(uint256 minVetoRatio, uint256 minDuration) external {
        minVetoRatio = bound(minVetoRatio, 1, RATIO_BASE);
        minDuration = bound(minDuration, 4 days, 365 days);

        settings.minVetoRatio = uint32(minVetoRatio);
        settings.minDuration = uint64(minDuration);

        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });

        assertEq(
            uint256(vm.load(address(plugin), GOVERNANCE_SETTINGS_SLOT).maskUint32(0)),
            minVetoRatio
        );
        assertEq(
            uint256(vm.load(address(plugin), GOVERNANCE_SETTINGS_SLOT).maskUint64(32)),
            minDuration
        );
    }

    function testFuzz_shouldEmit_OptimisticGovernanceSettingsUpdated(uint256 minVetoRatio, uint256 minDuration)
        external
    {
        minVetoRatio = bound(minVetoRatio, 1, RATIO_BASE);
        minDuration = bound(minDuration, 4 days, 365 days);

        settings.minVetoRatio = uint32(minVetoRatio);
        settings.minDuration = uint64(minDuration);

        vm.expectEmit();
        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: settings.minVetoRatio,
            minDuration: settings.minDuration
        });

        vm.prank(admin);
        plugin.updateOptimisticGovernanceSettings({ _governanceSettings: settings });
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL                                          *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_GetProposal_Test is PWNOptimisticGovernancePlugin_Test {

    uint256 public proposalId = 420;

    function test_shouldReturnCorrectOpenStatus() external {
        uint64 timestamp = 1000;
        vm.warp(timestamp);
        bool open;

        // true when not executed, started and not ended
        _mockProposal(proposalId, false, timestamp - 10, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        (open,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open);
        // false when executed
        _mockProposal(proposalId, true, timestamp - 10, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        (open,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open);
        // false when not started
        _mockProposal(proposalId, false, timestamp + 1, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        (open,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open);
        // false when ended
        _mockProposal(proposalId, false, timestamp - 10, timestamp - 1, 0, 0, 0, vetoVoters, actions, 0);
        (open,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open);
    }

    function testFuzz_shouldReturnProposal(
        bool _executed,
        uint64 _startDate,
        uint64 _endDate,
        uint64 _snapshotEpoch,
        uint256 _minVetoVotingPower,
        uint256 _vetoTally,
        uint256 _allowFailureMap
    ) external {
        actions.push(IDAO.Action({
            to: makeAddr("action1.addr"),
            value: 10,
            data: ""
        }));
        actions.push(IDAO.Action({
            to: makeAddr("action2.addr"),
            value: 901,
            data: ""
        }));

        _mockProposal({
            _proposalId: proposalId,
            _executed: _executed,
            _startDate: _startDate,
            _endDate: _endDate,
            _snapshotEpoch: _snapshotEpoch,
            _minVetoVotingPower: _minVetoVotingPower,
            _vetoTally: _vetoTally,
            _vetoVoters: vetoVoters, // 0
            _actions: actions,
            _allowFailureMap: _allowFailureMap
        });

        (
            , bool executed,
            PWNOptimisticGovernancePlugin.ProposalParameters memory parameters,
            uint256 vetoTally,
            IDAO.Action[] memory actions_,
            uint256 allowFailureMap
        ) = plugin.getProposal(proposalId);

        assertEq(executed, _executed);
        assertEq(parameters.startDate, _startDate);
        assertEq(parameters.endDate, _endDate);
        assertEq(parameters.snapshotEpoch, _snapshotEpoch);
        assertEq(parameters.minVetoVotingPower, _minVetoVotingPower);
        assertEq(vetoTally, _vetoTally);
        assertEq(actions_.length, 2);
        assertEq(actions_[0].to, actions[0].to);
        assertEq(actions_[0].value, actions[0].value);
        assertEq(actions_[1].to, actions[1].to);
        assertEq(actions_[1].value, actions[1].value);
        assertEq(allowFailureMap, _allowFailureMap);
    }

}


/*----------------------------------------------------------*|
|*  # GET VOTING TOKEN                                      *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_GetVotingToken_Test is PWNOptimisticGovernancePlugin_Test {

    function testFuzz_shouldReturnVotingToken(address votingToken) external {
        vm.store(address(plugin), VOTING_TOKEN_SLOT, bytes32(uint256(uint160(votingToken))));

        assertEq(address(plugin.getVotingToken()), votingToken);
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL VOTING POWER                                    *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_TotalVotingPower_Test is PWNOptimisticGovernancePlugin_Test {

    function testFuzz_shouldCallVotingTokenPastTotalSupply(uint256 epoch, uint256 totalSupply) external {
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, epoch),
            abi.encode(totalSupply)
        );
        vm.expectCall(votingToken, abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, epoch));

        assertEq(plugin.totalVotingPower(epoch), totalSupply);
    }

}


/*----------------------------------------------------------*|
|*  # IS MEMBER                                             *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_IsMember_Test is PWNOptimisticGovernancePlugin_Test {

    function testFuzz_shouldReturnTrue_whenVotingPowerGreaterThanZero(uint256 votingPower) external {
        votingPower = bound(votingPower, 1, type(uint256).max);
        vm.mockCall(
            votingToken, abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, voter), abi.encode(votingPower)
        );

        assertEq(plugin.isMember(voter), true);
    }

    function test_shouldReturnFalse_whenVotingPowerEqualZero() external {
        vm.mockCall(
            votingToken, abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, voter), abi.encode(uint256(0))
        );

        assertEq(plugin.isMember(voter), false);
    }

}


/*----------------------------------------------------------*|
|*  # HAS VETOED                                            *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_HasVetoed_Test is PWNOptimisticGovernancePlugin_Test {
    using SlotComputingLib for bytes32;

    function test_shouldReturnCorrectValue() external {
        uint256 proposalId = 420;
        bytes32 vetoedSlot = PROPOSALS_SLOT.withMappingKey(proposalId).withArrayIndex(4).withMappingKey(voter);

        vm.store(address(plugin), vetoedSlot, bytes32(uint256(1)));
        assertEq(plugin.hasVetoed(proposalId, voter), true);

        vm.store(address(plugin), vetoedSlot, bytes32(uint256(0)));
        assertEq(plugin.hasVetoed(proposalId, voter), false);
    }

}


/*----------------------------------------------------------*|
|*  # CAN VETO                                              *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_CanVeto_Test is PWNOptimisticGovernancePlugin_Test {

    uint256 public proposalId = 420;
    uint64 public timestamp = 1000;

    function setUp() override public {
        super.setUp();

        vm.warp(timestamp);

        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter, snapshotEpoch),
            abi.encode(uint256(1))
        );
    }


    function test_shouldReturnFalse_whenProposalClosed() external {
        _mockProposal(proposalId, true, timestamp - 10, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        assertFalse(plugin.canVeto(proposalId, voter));

        _mockProposal(proposalId, false, timestamp + 1, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        assertFalse(plugin.canVeto(proposalId, voter));

        _mockProposal(proposalId, false, timestamp - 10, timestamp - 1, 0, 0, 0, vetoVoters, actions, 0);
        assertFalse(plugin.canVeto(proposalId, voter));
    }

    function test_shouldReturnFalse_whenVetoed() external {
        vetoVoters.push(voter);

        _mockProposal(proposalId, false, timestamp - 10, timestamp + 10, 0, 0, 0, vetoVoters, actions, 0);
        assertFalse(plugin.canVeto(proposalId, voter));
    }

    function test_shouldReturnFalse_whenZeroPower() external {
        vm.mockCall(
            votingToken,
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, voter, snapshotEpoch),
            abi.encode(uint256(0))
        );

        _mockProposal(proposalId, false, timestamp - 10, timestamp + 10, snapshotEpoch, 0, 0, vetoVoters, actions, 0);
        assertFalse(plugin.canVeto(proposalId, voter));
    }

    function test_shouldReturnTrue_whenOpen_whenNotVetoed_whenNonZeroPower() external {
        _mockProposal(proposalId, false, timestamp - 10, timestamp + 10, snapshotEpoch, 0, 0, vetoVoters, actions, 0);
        assertTrue(plugin.canVeto(proposalId, voter));
    }

}


/*----------------------------------------------------------*|
|*  # CAN EXECUTE                                           *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_CanExecute_Test is PWNOptimisticGovernancePlugin_Test {

    uint256 public proposalId = 420;
    uint64 public timestamp = 1000;

    function setUp() override public {
        super.setUp();

        vm.warp(timestamp);
    }


    function test_shouldReturnFalse_whenExecuted() external {
        _mockProposal(proposalId, true, 0, timestamp - 10, 0, 20, 10, vetoVoters, actions, 0);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_shouldReturnFalse_whenEnded() external {
        _mockProposal(proposalId, false, 0, timestamp + 10, 0, 20, 10, vetoVoters, actions, 0);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_shouldReturnFalse_whenVetoed() external {
        _mockProposal(proposalId, false, 0, timestamp - 10, 0, 20, 21, vetoVoters, actions, 0);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_shouldReturnTrue_whenNotExecuted_whenNotEnded_whenNotVetoed() external {
        _mockProposal(proposalId, false, 0, timestamp - 10, 0, 20, 10, vetoVoters, actions, 0);
        assertTrue(plugin.canExecute(proposalId));
    }

}


/*----------------------------------------------------------*|
|*  # IS MIN VETO RATIO REACHED                             *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_IsMinVetoRatioReached_Test is PWNOptimisticGovernancePlugin_Test {

    function test_shouldReturnTrue_whenMinVetoPowerReached() external {
        uint256 proposalId = 420;

        _mockProposal(proposalId, false, 0, 0, 0, 20, 20, vetoVoters, actions, 0);
        assertTrue(plugin.isMinVetoRatioReached(proposalId));

        _mockProposal(proposalId, false, 0, 0, 0, 20, 10, vetoVoters, actions, 0);
        assertFalse(plugin.isMinVetoRatioReached(proposalId));
    }

}


/*----------------------------------------------------------*|
|*  # MIN VETO RATIO                                        *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_MinVetoRatio_Test is PWNOptimisticGovernancePlugin_Test {

    function test_shouldReturnStoredMinVetoRatio() external {
        assertEq(plugin.minVetoRatio(), settings.minVetoRatio);
    }

}


/*----------------------------------------------------------*|
|*  # MIN DURATION                                          *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePlugin_MinDuration_Test is PWNOptimisticGovernancePlugin_Test {

    function test_shouldReturnStoredMinDuration() external {
        assertEq(plugin.minDuration(), settings.minDuration);
    }

}
