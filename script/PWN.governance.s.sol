// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { IPluginSetup } from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginSetupRef, hashHelpers } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import { IPWNOptimisticGovernance } from "src/governance/optimistic/IPWNOptimisticGovernance.sol";
import { PWNOptimisticGovernancePlugin } from "src/governance/optimistic/PWNOptimisticGovernancePlugin.sol";
import { PWNOptimisticGovernancePluginSetup } from "src/governance/optimistic/PWNOptimisticGovernancePluginSetup.sol";
import { IPWNTokenGovernance } from "src/governance/token/IPWNTokenGovernance.sol";
import { PWNTokenGovernancePlugin } from "src/governance/token/PWNTokenGovernancePlugin.sol";
import { PWNTokenGovernancePluginSetup } from "src/governance/token/PWNTokenGovernancePluginSetup.sol";

contract Deploy is Script {

    // Ethereum addresses
    address internal constant DAO = 0x1B8383D2726E7e18189205337424a2631A2102F4;
    address internal constant DAO_SAFE = 0xd56635c0E91D31F88B89F195D3993a9e34516e59;
    address internal constant PLUGIN_REPO_FACTORY = 0xaac9E9cdb8C1eb42d881ADd59Ee9c53847a3a4f3;
    address internal constant PLUGIN_SETUP_PROCESSOR = 0xE978942c691e43f65c1B7c7F8f1dc8cDF061B13f;
    address internal constant EPOCH_CLOCK = 0xc9E94453d182c50984A2a4afdD60796D25B027Aa;
    address internal constant PWN_TOKEN = 0xd65404695a101B4FD476f4F2222F68917f96b911;
    address internal constant VEPWN_TOKEN = 0x2277c872A63FA7b2759173cdcfF693435532B4e4;

/*
forge script script/PWN.governance.s.sol:Deploy \
--sig "deployTokenGovernancePlugin()" \
--rpc-url $TENDERLY_URL_2 \
--private-key $PRIVATE_KEY_TESTNET \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    function deployTokenGovernancePlugin() external {
        vm.startBroadcast();

        // deploy plugin setup contract
        PWNTokenGovernancePluginSetup pluginSetup = new PWNTokenGovernancePluginSetup();

        // todo: update metadata to ipfs

        // create plugin repo
        PluginRepo pluginRepo = PluginRepoFactory(PLUGIN_REPO_FACTORY).createPluginRepoWithFirstVersion({
            _subdomain: "pwn-token-governance-plugin",
            _pluginSetup: address(pluginSetup),
            _maintainer: DAO_SAFE,
            _releaseMetadata: "dummy", // todo: add metadata for mainnet release
            _buildMetadata: "" // todo: add metadata for mainnet release
        });

        // prepare plugin installation
        PluginSetupProcessor.PrepareInstallationParams memory params = PluginSetupProcessor.PrepareInstallationParams({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 1 }),
                pluginSetupRepo: pluginRepo
            }),
            data: pluginSetup.encodeInstallationParams({
                _governanceSettings: PWNTokenGovernancePlugin.TokenGovernanceSettings({
                    votingMode: IPWNTokenGovernance.VotingMode.Standard,
                    supportThreshold: 500000, // 50%
                    minParticipation: 200000, // 20%
                    minDuration: 7 days,
                    minProposerVotingPower: 100_000e18 // 100k vePWN
                }),
                _epochClock: EPOCH_CLOCK,
                _votingToken: VEPWN_TOKEN,
                _rewardToken: PWN_TOKEN
            })
        });
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = PluginSetupProcessor(PLUGIN_SETUP_PROCESSOR).prepareInstallation({ _dao: DAO, _params: params });

        vm.stopBroadcast();

        console2.log("PWNTokenGovernancePlugin:", plugin);
        console2.log("Plugin repo:", address(pluginRepo));
        console2.log("Helpers hash:");
        console2.logBytes32(hashHelpers(preparedSetupData.helpers));
        console2.log("Permissions:", preparedSetupData.permissions.length);
        for (uint256 i; i < preparedSetupData.permissions.length; i++) {
            console2.log("-> Operation:", uint8(preparedSetupData.permissions[i].operation));
            console2.log("-> Where:", preparedSetupData.permissions[i].where);
            console2.log("-> Who:", preparedSetupData.permissions[i].who);
            console2.log("-> Condition:", preparedSetupData.permissions[i].condition);
            console2.log("-> Permission ID:");
            console2.logBytes32(preparedSetupData.permissions[i].permissionId);
            console2.log("------------------");
        }

        _consoleEncodeApplyInstallationExecuteCall(
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: params.pluginSetupRef,
                plugin: plugin,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );
    }

/*
forge script script/PWN.governance.s.sol:Deploy \
--sig "deployOptimisticGovernancePlugin()" \
--rpc-url $TENDERLY_URL_2 \
--private-key $PRIVATE_KEY_TESTNET \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    function deployOptimisticGovernancePlugin() external {
        vm.startBroadcast();

        // deploy plugin setup contract
        PWNOptimisticGovernancePluginSetup pluginSetup = new PWNOptimisticGovernancePluginSetup();

        // todo: update metadata to ipfs

        // create plugin repo
        PluginRepo pluginRepo = PluginRepoFactory(PLUGIN_REPO_FACTORY).createPluginRepoWithFirstVersion({
            _subdomain: "pwn-optimistic-governance-plugin",
            _pluginSetup: address(pluginSetup),
            _maintainer: DAO_SAFE,
            _releaseMetadata: "dummy", // todo: add metadata for mainnet release
            _buildMetadata: "" // todo: add metadata for mainnet release
        });

        // prepare plugin installation
        address[] memory proposers = new address[](1);
        proposers[0] = DAO_SAFE;
        PluginSetupProcessor.PrepareInstallationParams memory params = PluginSetupProcessor.PrepareInstallationParams({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 1 }),
                pluginSetupRepo: pluginRepo
            }),
            data: pluginSetup.encodeInstallationParams({
                _governanceSettings: PWNOptimisticGovernancePlugin.OptimisticGovernanceSettings({
                    minVetoRatio: 100000, // 10%
                    minDuration: 7 days
                }),
                _epochClock: EPOCH_CLOCK,
                _votingToken: VEPWN_TOKEN,
                _proposers: proposers
            })
        });
        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData)
            = PluginSetupProcessor(PLUGIN_SETUP_PROCESSOR).prepareInstallation({ _dao: DAO, _params: params });

        vm.stopBroadcast();

        console2.log("PWNOptimisticGovernancePlugin:", plugin);
        console2.log("Plugin repo:", address(pluginRepo));
        console2.log("Helpers hash:");
        console2.logBytes32(hashHelpers(preparedSetupData.helpers));
        console2.log("Permissions:", preparedSetupData.permissions.length);
        for (uint256 i; i < preparedSetupData.permissions.length; i++) {
            console2.log("-> Operation:", uint8(preparedSetupData.permissions[i].operation));
            console2.log("-> Where:", preparedSetupData.permissions[i].where);
            console2.log("-> Who:", preparedSetupData.permissions[i].who);
            console2.log("-> Condition:", preparedSetupData.permissions[i].condition);
            console2.log("-> Permission ID:");
            console2.logBytes32(preparedSetupData.permissions[i].permissionId);
            console2.log("------------------");
        }

        _consoleEncodeApplyInstallationExecuteCall(
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: params.pluginSetupRef,
                plugin: plugin,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );
    }


    // used for Tenderly simulations
    function _consoleEncodeApplyInstallationExecuteCall(
        PluginSetupProcessor.ApplyInstallationParams memory installationParams
    ) private pure {
        IDAO.Action[] memory actions = new IDAO.Action[](3);
        actions[0] = IDAO.Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)", DAO, PLUGIN_SETUP_PROCESSOR, keccak256("ROOT_PERMISSION")
            )
        });
        actions[1] = IDAO.Action({
            to: PLUGIN_SETUP_PROCESSOR,
            value: 0,
            data: abi.encodeWithSelector(
                PluginSetupProcessor.applyInstallation.selector, DAO, installationParams
            )
        });
        actions[2] = IDAO.Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "revoke(address,address,bytes32)", DAO, PLUGIN_SETUP_PROCESSOR, keccak256("ROOT_PERMISSION")
            )
        });

        console2.log("Proposal calldata:");
        console2.logBytes(abi.encodeWithSelector(IDAO.execute.selector, bytes32(0), actions, 0));
    }

}
