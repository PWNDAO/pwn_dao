// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/osx/core/permission/PermissionLib.sol";
import { PluginSetup, IPluginSetup } from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import { PWNOptimisticGovernancePlugin } from "./PWNOptimisticGovernancePlugin.sol";
import { IPWNEpochClock } from "../../interfaces/IPWNEpochClock.sol";

/// @title PWNOptimisticGovernancePluginSetup
/// @notice The setup contract of the `PWNOptimisticGovernancePlugin` plugin.
contract PWNOptimisticGovernancePluginSetup is PluginSetup {

    /// @notice The address of the `PWNOptimisticGovernancePlugin` base contract.
    PWNOptimisticGovernancePlugin private immutable optimisticGovernancePluginBase;

    /// @notice Thrown when trying to prepare an installation with no proposers.
    error NoProposers();

    /// @notice The contract constructor deploying the plugin implementation contract and receiving the governance token base contracts to clone from.
    constructor() {
        optimisticGovernancePluginBase = new PWNOptimisticGovernancePlugin();
    }

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

        // Prepare helpers.
        // todo: Q: Why is this needed?
        address[] memory helpers = new address[](1);
        helpers[0] = votingToken;

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(optimisticGovernancePluginBase),
            abi.encodeCall(
                PWNOptimisticGovernancePlugin.initialize,
                (IDAO(_dao), governanceSettings, IPWNEpochClock(epochClock), IVotesUpgradeable(votingToken))
            )
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](
            3 + proposers.length
        );

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

        // The plugin can make the DAO execute actions
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION, // todo: add condition
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Proposers can create proposals
        for (uint256 i; i < proposers.length; ) {
            permissions[3 + i] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: plugin,
                who: proposers[i],
                condition: PermissionLib.NO_CONDITION,
                permissionId: optimisticGovernancePluginBase.PROPOSER_PERMISSION_ID()
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
            condition: PermissionLib.NO_CONDITION, // todo: add condition
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Note: It no longer matters if proposers can still create proposals
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(optimisticGovernancePluginBase);
    }

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
