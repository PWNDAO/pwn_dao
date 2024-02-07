// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { IPermissionCondition } from "@aragon/osx/core/permission/IPermissionCondition.sol";
import { PermissionCondition } from "@aragon/osx/core/permission/PermissionCondition.sol";

import { IProposalReward } from "../../interfaces/IProposalReward.sol";

/// @title Proposal Reward Condition
/// @notice Permission condition that checks if a proposal is assigning a reward to itself and current proposal.
contract ProposalRewardAssignerCondition is PermissionCondition {

    // solhint-disable-next-line immutable-vars-naming
    bytes32 immutable public EXECUTE_PERMISSION_ID;

    /// @notice The DAO address.
    address immutable public dao;
    /// @notice The proposal reward contract address (PWN token).
    address immutable public proposalReward;

    constructor(address _dao, address _proposalReward) {
        dao = _dao;
        proposalReward = _proposalReward;
        EXECUTE_PERMISSION_ID = DAO(payable(_dao)).EXECUTE_PERMISSION_ID();
    }

    /// @inheritdoc IPermissionCondition
    /// @dev Checks if a proposal is assigning a reward to itself and current proposal.
    function isGranted(address _where, address _who, bytes32 _permissionId, bytes calldata _data)
        external
        view
        returns (bool)
    {
        // when plugin is calling the DAO execute function
        if (_where != dao) {
            return true;
        }
        if (_permissionId != EXECUTE_PERMISSION_ID) {
            return true;
        }
        if (_data.length < 4) {
            return true;
        }
        if (bytes4(_data[:4]) != IDAO.execute.selector) {
            return true;
        }

        (bytes32 proposalId, IDAO.Action[] memory actions, ) = abi.decode(_data[4:], (bytes32, IDAO.Action[], uint256));
        // check if the proposal is assigning a reward
        uint256 actionsLength = actions.length;
        for (uint256 i; i < actionsLength;) {
            if (
                actions[i].to == proposalReward &&
                bytes4(actions[i].data) == IProposalReward.assignProposalReward.selector
            ) {
                // check if the proposal is assigning a reward for itself and for current proposal
                // need to append 28 zero bytes to the data to make selector 32 bytes long
                bytes memory normalizedData = abi.encodePacked(bytes28(0), actions[i].data);
                (, address _votingContract, uint256 _proposalId)
                    = abi.decode(normalizedData, (bytes32, address, uint256));
                if (_who != _votingContract || uint256(proposalId) != _proposalId) {
                    return false;
                }
            }

            unchecked { ++i; }
        }

        return true;
    }

}
