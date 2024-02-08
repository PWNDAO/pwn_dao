// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IPWNTokenGovernance } from "src/governance/token/IPWNTokenGovernance.sol";
import {
    PWNTokenGovernancePlugin,
    PWNTokenGovernancePluginSetup,
    PermissionLib,
    IPluginSetup,
    ProposalRewardAssignerCondition
} from "src/governance/token/PWNTokenGovernancePluginSetup.sol";

import { Base_Test, Vm } from "../Base.t.sol";

abstract contract PWNTokenGovernancePluginSetup_Test is Base_Test {

    address public dao = makeAddr("dao");
    address public epochClock = makeAddr("epochClock");
    address public votingToken = makeAddr("votingToken"); // vePWN
    address public rewardToken = makeAddr("rewardToken"); // PWN
    bytes32 public DUMMY_EXECUTE_PERMISSION_ID = keccak256("DUMMY_EXECUTE_PERMISSION_ID");

    PWNTokenGovernancePluginSetup public pluginSetup;
    PWNTokenGovernancePlugin.TokenGovernanceSettings public governanceSettings;

    function setUp() public virtual {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        pluginSetup = new PWNTokenGovernancePluginSetup();

        governanceSettings = PWNTokenGovernancePlugin.TokenGovernanceSettings({
            votingMode: IPWNTokenGovernance.VotingMode.Standard,
            supportThreshold: 0,
            minParticipation: 0,
            minDuration: 1 hours,
            minProposerVotingPower: 0
        });
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePluginSetup_Constructor_Test is PWNTokenGovernancePluginSetup_Test {

    function test_shouldDeployTokenGovernancePluginBase() external {
        pluginSetup = new PWNTokenGovernancePluginSetup();

        assertNotEq(pluginSetup.implementation(), address(0));
    }

}


/*----------------------------------------------------------*|
|*  # PREPARE INSTALLATION                                  *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePluginSetup_PrepareInstallation_Test is PWNTokenGovernancePluginSetup_Test {

    bytes public installParameters;

    function setUp() public override {
        super.setUp();

        installParameters = pluginSetup.encodeInstallationParams(
            governanceSettings, epochClock, votingToken, rewardToken
        );
    }


    function test_shouldReturnNewlyDeployedAndInitializedPluginClone() external {
        vm.recordLogs();
        (address plugin, ) = pluginSetup.prepareInstallation(dao, installParameters);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log = logs[1];
        assertEq(log.topics[0], keccak256("TokenGovernanceSettingsUpdated(uint8,uint32,uint32,uint64,uint256)"));
        assertEq(
            keccak256(log.data),
            keccak256(
                abi.encode(
                    uint8(governanceSettings.votingMode),
                    governanceSettings.supportThreshold,
                    governanceSettings.minParticipation,
                    governanceSettings.minDuration,
                    governanceSettings.minProposerVotingPower
                )
            )
        );
        assertEq(log.emitter, plugin);

        log = logs[2];
        assertEq(log.topics[0], keccak256("MembershipContractAnnounced(address)"));
        assertEq(log.topics[1], bytes32(uint256(uint160(votingToken))));
        assertEq(log.emitter, plugin);

        log = logs[3];
        assertEq(log.topics[0], keccak256("Initialized(uint8)"));
        assertEq(uint256(bytes32(log.data)), 1);
        assertEq(log.emitter, plugin);
    }

    function test_shouldGrantPermission_UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID_wherePlugin_whoDAO() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[0];
        bytes32 permissionId = PWNTokenGovernancePlugin(plugin).UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID();
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Grant));
        assertEq(permission.where, plugin);
        assertEq(permission.who, dao);
        assertEq(permission.condition, PermissionLib.NO_CONDITION);
        assertEq(permission.permissionId, permissionId);
    }

    function test_shouldGrantPermission_UPGRADE_PLUGIN_PERMISSION_ID_wherePlugin_whoDAO() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[1];
        bytes32 permissionId = PWNTokenGovernancePlugin(plugin).UPGRADE_PLUGIN_PERMISSION_ID();
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Grant));
        assertEq(permission.where, plugin);
        assertEq(permission.who, dao);
        assertEq(permission.condition, PermissionLib.NO_CONDITION);
        assertEq(permission.permissionId, permissionId);
    }

    function test_shouldGrantPermission_EXECUTE_PERMISSION_ID_whereDAO_whoPlugin() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[2];
        bytes32 permissionId = DUMMY_EXECUTE_PERMISSION_ID;
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.GrantWithCondition));
        assertEq(permission.where, dao);
        assertEq(permission.who, plugin);
        assertEq(permission.condition, preparedSetupData.helpers[0]);
        assertEq(permission.permissionId, permissionId);
    }

    function test_shouldReturnHelpersArrayWithAssignerCondition() external {
        (, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        assertEq(preparedSetupData.helpers.length, 1);
        ProposalRewardAssignerCondition assignerCondition
            = ProposalRewardAssignerCondition(preparedSetupData.helpers[0]);
        assertEq(
            address(assignerCondition).codehash,
            address(new ProposalRewardAssignerCondition(dao, rewardToken)).codehash
        );
        assertEq(assignerCondition.dao(), dao);
        assertEq(assignerCondition.proposalReward(), rewardToken);
    }

}


/*----------------------------------------------------------*|
|*  # PREPARE UNINSTALLATION                                *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePluginSetup_PrepareUninstallation_Test is PWNTokenGovernancePluginSetup_Test {

    address public plugin = makeAddr("plugin");
    address public assignerCondition = makeAddr("assignerCondition");
    IPluginSetup.SetupPayload public setupPayload;

    function setUp() public override {
        super.setUp();

        setupPayload = IPluginSetup.SetupPayload({
            plugin: plugin,
            currentHelpers: new address[](1),
            data: new bytes(0)
        });
        setupPayload.currentHelpers[0] = assignerCondition;
    }


    function test_shouldFail_whenHelpersArrayLengthIsNotOne() external {
        setupPayload.currentHelpers = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(PWNTokenGovernancePluginSetup.WrongHelpersArrayLength.selector, 0)
        );
        pluginSetup.prepareUninstallation(dao, setupPayload);
    }

    function test_shouldRevokePermission_UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID_wherePlugin_whoDAO() external {
        PermissionLib.MultiTargetPermission[] memory permissions
            = pluginSetup.prepareUninstallation(dao, setupPayload);

        PermissionLib.MultiTargetPermission memory permission = permissions[0];
        bytes32 permissionId = PWNTokenGovernancePlugin(pluginSetup.implementation())
            .UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID();
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Revoke));
        assertEq(permission.where, plugin);
        assertEq(permission.who, dao);
        assertEq(permission.condition, PermissionLib.NO_CONDITION);
        assertEq(permission.permissionId, permissionId);
    }

    function test_shouldRevokePermission_UPGRADE_PLUGIN_PERMISSION_ID_wherePlugin_whoDAO() external {
        PermissionLib.MultiTargetPermission[] memory permissions
            = pluginSetup.prepareUninstallation(dao, setupPayload);

        PermissionLib.MultiTargetPermission memory permission = permissions[1];
        bytes32 permissionId = PWNTokenGovernancePlugin(pluginSetup.implementation())
            .UPGRADE_PLUGIN_PERMISSION_ID();
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Revoke));
        assertEq(permission.where, plugin);
        assertEq(permission.who, dao);
        assertEq(permission.condition, PermissionLib.NO_CONDITION);
        assertEq(permission.permissionId, permissionId);
    }

    function test_shouldRevokePermission_EXECUTE_PERMISSION_ID_whereDAO_whoPlugin() external {
        PermissionLib.MultiTargetPermission[] memory permissions
            = pluginSetup.prepareUninstallation(dao, setupPayload);

        PermissionLib.MultiTargetPermission memory permission = permissions[2];
        bytes32 permissionId = DUMMY_EXECUTE_PERMISSION_ID;
        assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Revoke));
        assertEq(permission.where, dao);
        assertEq(permission.who, plugin);
        assertEq(permission.condition, assignerCondition);
        assertEq(permission.permissionId, permissionId);
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE INSTALLATION PARAMS                            *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePluginSetup_EncodeInstallationParams_Test is PWNTokenGovernancePluginSetup_Test {

    function testFuzz_shouldReturnEncodedParams(
        uint8 _votingMode,
        uint32 _supportThreshold,
        uint32 _minParticipation,
        uint64 _minDuration,
        uint256 _minProposerVotingPower,
        address _epochClock,
        address _votingToken,
        address _rewardToken
    ) external {
        governanceSettings.votingMode = IPWNTokenGovernance.VotingMode(_votingMode % 3);
        governanceSettings.supportThreshold = _supportThreshold;
        governanceSettings.minParticipation = _minParticipation;
        governanceSettings.minDuration = _minDuration;
        governanceSettings.minProposerVotingPower = _minProposerVotingPower;

        bytes memory encodedParams = pluginSetup.encodeInstallationParams(
            governanceSettings, _epochClock, _votingToken, _rewardToken
        );

        assertEq(
            keccak256(encodedParams),
            keccak256(abi.encode(governanceSettings, _epochClock, _votingToken, _rewardToken))
        );
    }

}


/*----------------------------------------------------------*|
|*  # DECODE INSTALLATION PARAMS                            *|
|*----------------------------------------------------------*/

contract PWNTokenGovernancePluginSetup_DecodeInstallationParams_Test is PWNTokenGovernancePluginSetup_Test {

    function testFuzz_shouldReturnDecodedParams(
        uint8 _votingMode,
        uint32 _supportThreshold,
        uint32 _minParticipation,
        uint64 _minDuration,
        uint256 _minProposerVotingPower,
        address _epochClock,
        address _votingToken,
        address _rewardToken
    ) external {
        governanceSettings.votingMode = IPWNTokenGovernance.VotingMode(_votingMode % 3);
        governanceSettings.supportThreshold = _supportThreshold;
        governanceSettings.minParticipation = _minParticipation;
        governanceSettings.minDuration = _minDuration;
        governanceSettings.minProposerVotingPower = _minProposerVotingPower;
        bytes memory encodedParams = abi.encode(governanceSettings, _epochClock, _votingToken, _rewardToken);

        (
            PWNTokenGovernancePlugin.TokenGovernanceSettings memory decodedGovernanceSettings,
            address decodedEpochClock,
            address decodedVotingToken,
            address decodedRewardToken
        ) = pluginSetup.decodeInstallationParams(encodedParams);

        assertEq(uint8(decodedGovernanceSettings.votingMode), _votingMode % 3);
        assertEq(decodedGovernanceSettings.supportThreshold, _supportThreshold);
        assertEq(decodedGovernanceSettings.minParticipation, _minParticipation);
        assertEq(decodedGovernanceSettings.minDuration, _minDuration);
        assertEq(decodedGovernanceSettings.minProposerVotingPower, _minProposerVotingPower);
        assertEq(decodedEpochClock, _epochClock);
        assertEq(decodedVotingToken, _votingToken);
        assertEq(decodedRewardToken, _rewardToken);
    }

}
