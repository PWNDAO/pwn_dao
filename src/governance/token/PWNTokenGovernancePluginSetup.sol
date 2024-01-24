// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/osx/core/permission/PermissionLib.sol";
import { PluginSetup , IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import { PWNTokenGovernancePlugin } from "./PWNTokenGovernancePlugin.sol";
import { IPWNEpochClock } from "../../interfaces/IPWNEpochClock.sol";

/// @title PWNTokenGovernancePluginSetup
/// @notice The setup contract of the `PWNTokenGovernancePlugin` plugin.
contract PWNTokenGovernancePluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /// @notice The address of the `PWNTokenGovernancePlugin` base contract.
    PWNTokenGovernancePlugin private immutable tokenGovernancePluginBase;

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the plugin implementation contract to clone from.
    constructor() {
        tokenGovernancePluginBase = new PWNTokenGovernancePlugin();
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _installParameters)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `PWNTokenGovernancePlugin` plugin,
        // and the required helpers
        (
            PWNTokenGovernancePlugin.TokenGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken
        ) = decodeInstallationParams(_installParameters);

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(tokenGovernancePluginBase),
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.initialize.selector, _dao, governanceSettings, epochClock, votingToken
            )
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](3);

        // Set plugin permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.{
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

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
            permissionId: tokenGovernancePluginBase.UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(tokenGovernancePluginBase);
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams(
        PWNTokenGovernancePlugin.TokenGovernanceSettings memory _governanceSettings,
        address _epochClock,
        address _votingToken
    ) external pure returns (bytes memory) {
        return abi.encode(_governanceSettings, _epochClock, _votingToken);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (
            PWNTokenGovernancePlugin.TokenGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken
        )
    {
        (governanceSettings, epochClock, votingToken) = abi.decode(
            _data, (PWNTokenGovernancePlugin.TokenGovernanceSettings, address, address)
        );
    }

}
