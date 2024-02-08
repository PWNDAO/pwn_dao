// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

// This code is based on the Aragon's optimistic token voting plugin setup.
// https://github.com/aragon/optimistic-token-voting-plugin/blob/f25ea1db9b67a72b7a2e225d719577551e30ac9b/src/OptimisticTokenVotingPluginSetup.sol
// Changes:
// - Remove `GovernanceERC20` and `GovernanceWrappedERC20`
// - Grant `EXECUTE_PERMISSION_ID` with `DAOExecuteAllowlist` condition

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/osx/core/permission/PermissionLib.sol";
import { PluginSetup, IPluginSetup } from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import { PWNOptimisticGovernancePlugin } from "./PWNOptimisticGovernancePlugin.sol";
import { DAOExecuteAllowlist } from "../permission/DAOExecuteAllowlist.sol";

/// @title PWNOptimisticGovernancePluginSetup
/// @notice The setup contract of the `PWNOptimisticGovernancePlugin` plugin.
contract PWNOptimisticGovernancePluginSetup is PluginSetup {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The address of the `PWNOptimisticGovernancePlugin` base contract.
    PWNOptimisticGovernancePlugin private immutable optimisticGovernancePluginBase;


    /*----------------------------------------------------------*|
    |*  # ERRORS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Thrown when trying to prepare an installation with no proposers.
    error NoProposers();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    /// @notice The contract constructor deploying the plugin implementation contract to clone from.
    constructor() {
        optimisticGovernancePluginBase = new PWNOptimisticGovernancePlugin();
    }


    /*----------------------------------------------------------*|
    |*  # PREPARE INSTALL & UNINSTALL                           *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _installParameters)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `PWNOptimisticGovernancePlugin` plugin,
        // and the required helpers
        (
            PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken,
            address[] memory proposers
        ) = decodeInstallationParams(_installParameters);

        if (proposers.length == 0) {
            revert NoProposers();
        }

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(optimisticGovernancePluginBase),
            abi.encodeWithSelector(
                PWNOptimisticGovernancePlugin.initialize.selector, _dao, governanceSettings, epochClock, votingToken
            )
        );

        // Prepare helpers.
        address[] memory helpers = new address[](1);

        // Deploy DAOExecuteAllowlist condition.
        DAOExecuteAllowlist allowlist = new DAOExecuteAllowlist(_dao);

        helpers[0] = address(allowlist);

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions
            = new PermissionLib.MultiTargetPermission[](3 + (2 * proposers.length));

        // Request the permissions to be granted

        // The DAO can update the plugin settings
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticGovernancePluginBase.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        // The DAO can upgrade the plugin implementation
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // The plugin can make the DAO execute actions with allowlist condition
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: _dao,
            who: plugin,
            condition: address(allowlist),
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Proposers can create proposals
        for (uint256 i; i < proposers.length;) {
            permissions[3 + (i * 2)] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: plugin,
                who: proposers[i],
                condition: PermissionLib.NO_CONDITION,
                permissionId: optimisticGovernancePluginBase.PROPOSER_PERMISSION_ID()
            });

            permissions[3 + (i * 2) + 1] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: plugin,
                who: proposers[i],
                condition: PermissionLib.NO_CONDITION,
                permissionId: optimisticGovernancePluginBase.CANCELLER_PERMISSION_ID()
            });

            unchecked {
                ++i;
            }
        }

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        permissions = new PermissionLib.MultiTargetPermission[](3);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticGovernancePluginBase.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: _payload.currentHelpers[0], // DAOExecuteAllowlist
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Note: It no longer matters if proposers can still create proposals
    }


    /*----------------------------------------------------------*|
    |*  # GETTERS                                               *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(optimisticGovernancePluginBase);
    }


    /*----------------------------------------------------------*|
    |*  # EN/DECODE INSTALL PARAMS                              *|
    |*----------------------------------------------------------*/

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams(
        PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings calldata _governanceSettings,
        address _epochClock,
        address _votingToken,
        address[] calldata _proposers
    ) external pure returns (bytes memory) {
        return abi.encode(_governanceSettings, _epochClock, _votingToken, _proposers);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (
            PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken,
            address[] memory proposers
        )
    {
        (governanceSettings, epochClock, votingToken, proposers) = abi.decode(
            _data, (PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings, address, address, address[])
        );
    }

}
