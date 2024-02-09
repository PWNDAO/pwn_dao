// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { PermissionLib } from "@aragon/osx/core/permission/PermissionLib.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { IPluginSetup } from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginSetupRef, hashHelpers } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import { IPWNOptimisticGovernance, PWNOptimisticGovernancePlugin }
    from "src/governance/optimistic/PWNOptimisticGovernancePlugin.sol";
import { PWNOptimisticGovernancePluginSetup } from "src/governance/optimistic/PWNOptimisticGovernancePluginSetup.sol";
import { IPWNTokenGovernance, PWNTokenGovernancePlugin } from "src/governance/token/PWNTokenGovernancePlugin.sol";
import { PWNTokenGovernancePluginSetup } from "src/governance/token/PWNTokenGovernancePluginSetup.sol";
import { DAOExecuteAllowlist } from "src/governance/permission/DAOExecuteAllowlist.sol";
import { ProposalRewardAssignerCondition } from "src/governance/permission/ProposalRewardAssignerCondition.sol";

import { Base_Test, console2 } from "../Base.t.sol";

contract PWNGovernance_ForkTest is Base_Test {

    bytes32 constant public ROOT_PERMISSION_ID = keccak256("ROOT_PERMISSION");
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    address public pluginRepoFactory = vm.envAddress("OSX_PLUGIN_REPO_FACTORY");
    address public pluginSetupProcessor = vm.envAddress("OSX_PLUGIN_SETUP_PROCESSOR");
    address public dao = vm.envAddress("DAO");
    address public multisigGovernancePlugin = vm.envAddress("MULTISIG_GOVERNANCE_PLUGIN");

    address public pwnToken = makeAddr("pwnToken");
    address public epochClock = makeAddr("epochClock");
    address public vePWN = makeAddr("vePWN");
    address public proposer = makeAddr("proposer");
    address public voter = makeAddr("voter");

    uint256 public votingPower = 100_000e18; // 100k vePWN
    uint256 public totalVotingPower = 250_000e18; // 250k vePWN
    uint256 public currentEpoch = 10;

    IDAO.Action[] public actions;

    PluginRepo public tokenPluginRepo;
    PWNTokenGovernancePluginSetup public tokenPluginSetup;
    PWNTokenGovernancePlugin public tokenGovernance;

    PluginRepo public optimisticPluginRepo;
    PWNOptimisticGovernancePluginSetup public optimisticPluginSetup;
    PWNOptimisticGovernancePlugin public optimisticGovernance;

    DAOExecuteAllowlist public allowlist;
    ProposalRewardAssignerCondition public rewardAssignerCondition;

    function setUp() external {
        vm.createSelectFork("ethereum", 19193581);

        vm.mockCall(vePWN, abi.encodeWithSignature("getVotes(address)"), abi.encode(votingPower));
        vm.mockCall(vePWN, abi.encodeWithSignature("getPastVotes(address,uint256)"), abi.encode(votingPower));
        vm.mockCall(vePWN, abi.encodeWithSignature("getPastTotalSupply(uint256)"), abi.encode(totalVotingPower));
        vm.mockCall(epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch));

        // deploy plugin setup contract
        tokenPluginSetup = new PWNTokenGovernancePluginSetup();
        optimisticPluginSetup = new PWNOptimisticGovernancePluginSetup();

        // create plugin repo
        tokenPluginRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepoWithFirstVersion({
            _subdomain: "pwn-token-governance-plugin",
            _pluginSetup: address(tokenPluginSetup),
            _maintainer: makeAddr("DAO_SAFE"),
            _releaseMetadata: "dummy",
            _buildMetadata: ""
        });
        optimisticPluginRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepoWithFirstVersion({
            _subdomain: "pwn-optimistic-governance-plugin",
            _pluginSetup: address(optimisticPluginSetup),
            _maintainer: makeAddr("DAO_SAFE"),
            _releaseMetadata: "dummy",
            _buildMetadata: ""
        });

        // prepare plugin installation params
        PluginSetupProcessor.PrepareInstallationParams memory tokenParams = PluginSetupProcessor.PrepareInstallationParams({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 1 }),
                pluginSetupRepo: tokenPluginRepo
            }),
            data: tokenPluginSetup.encodeInstallationParams({
                _governanceSettings: PWNTokenGovernancePlugin.TokenGovernanceSettings({
                    votingMode: IPWNTokenGovernance.VotingMode.Standard,
                    supportThreshold: 500000, // 50%
                    minParticipation: 200000, // 20%
                    minDuration: 3 days,
                    minProposerVotingPower: 100_000e18 // 100k vePWN
                }),
                _epochClock: epochClock,
                _votingToken: vePWN,
                _rewardToken: pwnToken
            })
        });

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        PluginSetupProcessor.PrepareInstallationParams memory optimisticParams = PluginSetupProcessor.PrepareInstallationParams({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 1 }),
                pluginSetupRepo: optimisticPluginRepo
            }),
            data: optimisticPluginSetup.encodeInstallationParams({
                _governanceSettings: PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings({
                    minVetoRatio: 100000, // 10%
                    minDuration: 3 days
                }),
                _epochClock: epochClock,
                _votingToken: vePWN,
                _proposers: proposers
            })
        });

        // prepare plugin installation
        (address _tokenGovernance, IPluginSetup.PreparedSetupData memory tokenPreparedSetupData)
            = PluginSetupProcessor(pluginSetupProcessor).prepareInstallation({ _dao: dao, _params: tokenParams });
        (address _optimisticGovernance, IPluginSetup.PreparedSetupData memory optimisticPreparedSetupData)
            = PluginSetupProcessor(pluginSetupProcessor).prepareInstallation({ _dao: dao, _params: optimisticParams });

        tokenGovernance = PWNTokenGovernancePlugin(_tokenGovernance);
        optimisticGovernance = PWNOptimisticGovernancePlugin(_optimisticGovernance);
        rewardAssignerCondition = ProposalRewardAssignerCondition(tokenPreparedSetupData.helpers[0]);
        allowlist = DAOExecuteAllowlist(optimisticPreparedSetupData.helpers[0]);

        // apply plugin installation
        _applyInstallation(
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: tokenParams.pluginSetupRef,
                plugin: _tokenGovernance,
                permissions: tokenPreparedSetupData.permissions,
                helpersHash: hashHelpers(tokenPreparedSetupData.helpers)
            })
        );
        _applyInstallation(
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: optimisticParams.pluginSetupRef,
                plugin: _optimisticGovernance,
                permissions: optimisticPreparedSetupData.permissions,
                helpersHash: hashHelpers(optimisticPreparedSetupData.helpers)
            })
        );


        // label addresses for debugging
        vm.label(pluginRepoFactory, "Plugin Repo Factory");
        vm.label(pluginSetupProcessor, "Plugin Setup Processor");
        vm.label(dao, "DAO");
        vm.label(address(pwnToken), "PWN Token");
        vm.label(epochClock, "Epoch Clock");
        vm.label(address(vePWN), "Vote Escrowed PWN");
        vm.label(proposer, "Proposer");
        vm.label(voter, "Voter");
    }


    function _applyInstallation(PluginSetupProcessor.ApplyInstallationParams memory params) internal {
        _executePluginSetupProcessorActionWithRootPermission(
            abi.encodeWithSelector(PluginSetupProcessor.applyInstallation.selector, dao, params)
        );
    }

    function _applyUninstallation(PluginSetupProcessor.ApplyUninstallationParams memory params) internal {
        _executePluginSetupProcessorActionWithRootPermission(
            abi.encodeWithSelector(PluginSetupProcessor.applyUninstallation.selector, dao, params)
        );
    }

    function _executePluginSetupProcessorActionWithRootPermission(bytes memory data) internal {
        IDAO.Action[] memory _actions = new IDAO.Action[](3);
        _actions[0] = IDAO.Action({
            to: dao, value: 0, data: abi.encodeWithSignature(
                "grant(address,address,bytes32)", dao, pluginSetupProcessor, ROOT_PERMISSION_ID
            )
        });
        _actions[1] = IDAO.Action({ to: pluginSetupProcessor, value: 0, data: data });
        _actions[2] = IDAO.Action({
            to: dao, value: 0, data: abi.encodeWithSignature(
                "revoke(address,address,bytes32)", dao, pluginSetupProcessor, ROOT_PERMISSION_ID
            )
        });

        vm.prank(multisigGovernancePlugin);
        IDAO(dao).execute({
            _callId: bytes32(0),
            _actions: _actions,
            _allowFailureMap: 0
        });
    }




    function testFork_shouldInstallPlugins() external {
        assertTrue(IDAO(dao).hasPermission(dao, address(tokenGovernance), EXECUTE_PERMISSION_ID, ""));
        assertTrue(IDAO(dao).hasPermission(dao, address(optimisticGovernance), EXECUTE_PERMISSION_ID, ""));
    }

    function testFork_shouldExecute_whenSuccessfulTokenProposal() external {
        actions.push(IDAO.Action({ to: pwnToken, value: 0, data: abi.encodeWithSignature("mint(uint256)", 100) }));
        actions.push(IDAO.Action({
            to: pwnToken, value: 0, data: abi.encodeWithSignature(
                "assignProposalReward(address,uint256)", address(tokenGovernance), tokenGovernance.proposalCount()
            )
        }));

        // create a proposal
        vm.prank(proposer);
        uint256 proposalId = tokenGovernance.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Abstain,
            _tryEarlyExecution: false
        });

        // vote on the proposal
        vm.prank(voter);
        tokenGovernance.vote(proposalId, IPWNTokenGovernance.VoteOption.Yes, false);

        // execute the proposal
        vm.expectCall(pwnToken, abi.encodeWithSignature("mint(uint256)", 100));
        vm.expectCall(pwnToken, abi.encodeWithSignature(
            "assignProposalReward(address,uint256)", address(tokenGovernance), proposalId
        ));

        vm.warp(block.timestamp + 4 days);
        tokenGovernance.execute(proposalId);

        // check if the proposal was executed
        (bool open, bool executed,,,,) = tokenGovernance.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);
    }

    function testFork_shouldFail_whenAssigningProposalRewardToDifferentProposer() external {
        actions.push(IDAO.Action({ to: pwnToken, value: 0, data: abi.encodeWithSignature("mint(uint256)", 100) }));
        actions.push(IDAO.Action({
            to: pwnToken, value: 0, data: abi.encodeWithSignature( // assigning different proposal id
                "assignProposalReward(address,uint256)", address(tokenGovernance), tokenGovernance.proposalCount() + 1
            )
        }));

        // create a proposal
        vm.prank(proposer);
        uint256 proposalId = tokenGovernance.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0,
            _voteOption: IPWNTokenGovernance.VoteOption.Yes,
            _tryEarlyExecution: false
        });

        // fail to execute the proposal
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSelector(
            PermissionManager.Unauthorized.selector, dao, address(tokenGovernance), EXECUTE_PERMISSION_ID
        ));
        tokenGovernance.execute(proposalId);
    }

    function testFork_shouldExecute_whenSuccessfulOptimisticProposal() external {
        actions.push(IDAO.Action({ to: pwnToken, value: 0, data: abi.encodeWithSignature("mint(uint256)", 100) }));

        // allow selector
        vm.prank(dao);
        allowlist.setAllowlist(pwnToken, bytes4(abi.encodeWithSignature("mint(uint256)")), true);

        // create a proposal
        vm.prank(proposer);
        uint256 proposalId = optimisticGovernance.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0
        });

        // execute the proposal
        vm.expectCall(pwnToken, abi.encodeWithSignature("mint(uint256)", 100));

        vm.warp(block.timestamp + 4 days);
        optimisticGovernance.execute(proposalId);

        // check if the proposal was executed
        (bool open, bool executed,,,,,) = optimisticGovernance.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);
    }

    function testForkFuzz_shouldFail_whenCallingNotAllowedSelector(address _contract, bytes4 _selector)
        external
        checkAddress(_contract)
    {
        actions.push(IDAO.Action({ to: _contract, value: 0, data: abi.encodeWithSelector(_selector) }));

        // allow selector
        vm.prank(dao);
        allowlist.setAllowlist(_contract, bytes4(abi.encodeWithSelector(_selector)), false);

        // create a proposal
        vm.prank(proposer);
        uint256 proposalId = optimisticGovernance.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0,
            _endDate: 0
        });

        // fial to execute the proposal
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSelector(
            PermissionManager.Unauthorized.selector, dao, address(optimisticGovernance), EXECUTE_PERMISSION_ID
        ));
        optimisticGovernance.execute(proposalId);
    }

    function testFork_shouldUninstallPlugins() external {
        vm.roll(block.number + 1); // cannot install & uninstall plugin in the same block

        PluginRepo.Tag memory tag = PluginRepo.Tag({ release: 1, build: 1 });
        address[] memory helpers = new address[](1);

        helpers[0] = address(rewardAssignerCondition);
        _applyUninstallation(
            PluginSetupProcessor.ApplyUninstallationParams({
                plugin: address(tokenGovernance),
                pluginSetupRef: PluginSetupRef({ versionTag: tag, pluginSetupRepo: tokenPluginRepo }),
                permissions: PluginSetupProcessor(pluginSetupProcessor).prepareUninstallation({
                    _dao: dao,
                    _params: PluginSetupProcessor.PrepareUninstallationParams({
                        pluginSetupRef: PluginSetupRef({ versionTag: tag, pluginSetupRepo: tokenPluginRepo }),
                        setupPayload: IPluginSetup.SetupPayload({
                            plugin: address(tokenGovernance),
                            currentHelpers: helpers,
                            data: ""
                        })
                    })
                })
            })
        );

        helpers[0] = address(allowlist);
        _applyUninstallation(
            PluginSetupProcessor.ApplyUninstallationParams({
                plugin: address(optimisticGovernance),
                pluginSetupRef: PluginSetupRef({ versionTag: tag, pluginSetupRepo: optimisticPluginRepo }),
                permissions: PluginSetupProcessor(pluginSetupProcessor).prepareUninstallation({
                    _dao: dao,
                    _params: PluginSetupProcessor.PrepareUninstallationParams({
                        pluginSetupRef: PluginSetupRef({ versionTag: tag, pluginSetupRepo: optimisticPluginRepo }),
                        setupPayload: IPluginSetup.SetupPayload({
                            plugin: address(optimisticGovernance),
                            currentHelpers: helpers,
                            data: ""
                        })
                    })
                })
            })
        );


        assertFalse(IDAO(dao).hasPermission(dao, address(tokenGovernance), EXECUTE_PERMISSION_ID, ""));
        assertFalse(IDAO(dao).hasPermission(dao, address(optimisticGovernance), EXECUTE_PERMISSION_ID, ""));
    }

}
