// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IPWNOptimisticGovernance } from "src/governance/optimistic/IPWNOptimisticGovernance.sol";
import {
    PWNOptimisticGovernancePlugin,
    PWNOptimisticGovernancePluginSetup,
    PermissionLib,
    IPluginSetup,
    DAOExecuteAllowlist
} from "src/governance/optimistic/PWNOptimisticGovernancePluginSetup.sol";

import { Base_Test, Vm, console2 } from "../Base.t.sol";

abstract contract PWNOptimisticGovernancePluginSetup_Test is Base_Test {

    address public dao = makeAddr("dao");
    address public epochClock = makeAddr("epochClock");
    address public votingToken = makeAddr("votingToken");
    bytes32 public DUMMY_EXECUTE_PERMISSION_ID = keccak256("DUMMY_EXECUTE_PERMISSION_ID");

    PWNOptimisticGovernancePluginSetup public pluginSetup;
    PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings public governanceSettings;
    address[] public proposers;

    function setUp() public virtual {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        pluginSetup = new PWNOptimisticGovernancePluginSetup();

        governanceSettings = PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings({
            minVetoRatio: 1,
            minDuration: 4 days
        });

        proposers.push(makeAddr("proposer1"));
        proposers.push(makeAddr("proposer2"));
        proposers.push(makeAddr("proposer3"));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePluginSetup_Constructor_Test is PWNOptimisticGovernancePluginSetup_Test {

    function test_shouldDeployOptimisticGovernancePluginBase() external {
        pluginSetup = new PWNOptimisticGovernancePluginSetup();

        assertNotEq(pluginSetup.implementation(), address(0));
    }

}


/*----------------------------------------------------------*|
|*  # PREPARE INSTALLATION                                  *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePluginSetup_PrepareInstallation_Test is PWNOptimisticGovernancePluginSetup_Test {

    bytes public installParameters;

    function setUp() public override {
        super.setUp();

        installParameters = pluginSetup.encodeInstallationParams(
            governanceSettings, epochClock, votingToken, proposers
        );
    }


    function test_shouldFail_whenNoProposers() external {
        installParameters = pluginSetup.encodeInstallationParams(
            governanceSettings, epochClock, votingToken, new address[](0)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNOptimisticGovernancePluginSetup.NoProposers.selector));
        pluginSetup.prepareInstallation(dao, installParameters);
    }

    function test_shouldReturnNewlyDeployedAndInitializedPluginClone() external {
        vm.recordLogs();
        (address plugin, ) = pluginSetup.prepareInstallation(dao, installParameters);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log = logs[1];
        assertEq(log.topics[0], keccak256("OptimisticGovernanceSettingsUpdated(uint32,uint64)"));
        assertEq(
            keccak256(log.data),
            keccak256(
                abi.encode(
                    governanceSettings.minVetoRatio,
                    governanceSettings.minDuration
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

    function test_shouldGrantPermission_UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID_wherePlugin_whoDAO() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[0];
        bytes32 permissionId = PWNOptimisticGovernancePlugin(plugin).UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID();
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
        bytes32 permissionId = PWNOptimisticGovernancePlugin(plugin).UPGRADE_PLUGIN_PERMISSION_ID();
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
        assertEq( // check that the condition is the DAOExecuteAllowlist contract with the correct DAO address
            preparedSetupData.helpers[0].codehash,
            address(new DAOExecuteAllowlist(dao)).codehash
        );
    }

    function test_shouldGrantPermission_PROPOSER_PERMISSION_ID_wherePlugin_whoProposers() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        for (uint256 i; i < proposers.length; ++i) {
            PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[3 + (i * 2)];
            bytes32 permissionId = PWNOptimisticGovernancePlugin(plugin).PROPOSER_PERMISSION_ID();
            assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Grant));
            assertEq(permission.where, plugin);
            assertEq(permission.who, proposers[i]);
            assertEq(permission.condition, PermissionLib.NO_CONDITION);
            assertEq(permission.permissionId, permissionId);
        }
    }

    function test_shouldGrantPermission_CANCELLER_PERMISSION_ID_wherePlugin_whoProposers() external {
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = pluginSetup.prepareInstallation(dao, installParameters);

        for (uint256 i; i < proposers.length; ++i) {
            PermissionLib.MultiTargetPermission memory permission = preparedSetupData.permissions[3 + (i * 2) + 1];
            bytes32 permissionId = PWNOptimisticGovernancePlugin(plugin).CANCELLER_PERMISSION_ID();
            assertEq(uint8(permission.operation), uint8(PermissionLib.Operation.Grant));
            assertEq(permission.where, plugin);
            assertEq(permission.who, proposers[i]);
            assertEq(permission.condition, PermissionLib.NO_CONDITION);
            assertEq(permission.permissionId, permissionId);
        }
    }

}


/*----------------------------------------------------------*|
|*  # PREPARE UNINSTALLATION                                *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePluginSetup_PrepareUninstallation_Test is PWNOptimisticGovernancePluginSetup_Test {

    address public plugin = makeAddr("plugin");
    address public allowlist = makeAddr("allowlist");
    IPluginSetup.SetupPayload public setupPayload;

    function setUp() public override {
        super.setUp();

        setupPayload = IPluginSetup.SetupPayload({
            plugin: plugin,
            currentHelpers: new address[](1),
            data: new bytes(0)
        });
        setupPayload.currentHelpers[0] = allowlist;
    }


    function test_shouldRevokePermission_UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID_wherePlugin_whoDAO() external {
        PermissionLib.MultiTargetPermission[] memory permissions
            = pluginSetup.prepareUninstallation(dao, setupPayload);

        PermissionLib.MultiTargetPermission memory permission = permissions[0];
        bytes32 permissionId = PWNOptimisticGovernancePlugin(pluginSetup.implementation())
            .UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID();
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
        bytes32 permissionId = PWNOptimisticGovernancePlugin(pluginSetup.implementation())
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
        assertEq(permission.condition, allowlist);
        assertEq(permission.permissionId, permissionId);
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE INSTALLATION PARAMS                            *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePluginSetup_EncodeInstallationParams_Test is PWNOptimisticGovernancePluginSetup_Test {

    function testFuzz_shouldReturnEncodedParams(
        uint32 _minVetoRatio,
        uint64 _minDuration,
        address _epochClock,
        address _votingToken
    ) external {
        governanceSettings.minVetoRatio = _minVetoRatio;
        governanceSettings.minDuration = _minDuration;

        bytes memory encodedParams = pluginSetup.encodeInstallationParams(
            governanceSettings,
            _epochClock,
            _votingToken,
            proposers
        );

        assertEq(
            keccak256(encodedParams),
            keccak256(abi.encode(governanceSettings, _epochClock, _votingToken, proposers))
        );
    }

}


/*----------------------------------------------------------*|
|*  # DECODE INSTALLATION PARAMS                            *|
|*----------------------------------------------------------*/

contract PWNOptimisticGovernancePluginSetup_DecodeInstallationParams_Test is PWNOptimisticGovernancePluginSetup_Test {

    function testFuzz_shouldReturnDecodedParams(
        uint32 _minVetoRatio,
        uint64 _minDuration,
        address _epochClock,
        address _votingToken
    ) external {
        governanceSettings.minVetoRatio = _minVetoRatio;
        governanceSettings.minDuration = _minDuration;
        bytes memory encodedParams = abi.encode(governanceSettings, _epochClock, _votingToken, proposers);

        (
            PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings memory decodedGovernanceSettings,
            address decodedEpochClock,
            address decodedVotingToken,
            address[] memory decodedProposers
        ) = pluginSetup.decodeInstallationParams(encodedParams);

        assertEq(decodedGovernanceSettings.minVetoRatio, _minVetoRatio);
        assertEq(decodedGovernanceSettings.minDuration, _minDuration);
        assertEq(decodedEpochClock, _epochClock);
        assertEq(decodedVotingToken, _votingToken);
        assertEq(decodedProposers.length, proposers.length);
        for (uint256 i; i < decodedProposers.length; ++i) {
            assertEq(decodedProposers[i], proposers[i]);
        }
    }

}
