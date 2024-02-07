// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";
import { IPermissionCondition } from "@aragon/osx/core/permission/IPermissionCondition.sol";

/// @title Proposal Reward Condition
/// @notice Permission condition that checks if a proposal is assigning a reward to itself and current proposal.
contract DAOExecuteAllowlist is IPermissionCondition {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes4 constant public ANY_SELECTOR = bytes4(0);

    // solhint-disable-next-line immutable-vars-naming
    bytes32 immutable public EXECUTE_PERMISSION_ID;

    /// @notice The DAO address.
    /// @dev Only the DAO can update the allowlist.
    address public dao;

    /// @notice Contracts and their selectors that are allowed to call via the DAO execute function.
    /// @dev if `ANY_SELECTOR` is allowed, all selectors of the contract are allowed.
    mapping(address => mapping(bytes4 => bool)) private _allowlist;


    /*----------------------------------------------------------*|
    |*  # ERRORS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Thrown when the caller is not the DAO.
    error CallerNotDAO();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _dao) {
        dao = _dao;
        EXECUTE_PERMISSION_ID = DAO(payable(_dao)).EXECUTE_PERMISSION_ID();
    }


    /*----------------------------------------------------------*|
    |*  # IS GRANTED                                            *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPermissionCondition
    /// @dev Checks if all actions are allowed to be executed via the DAO execute function.
    function isGranted(address _where, address _who, bytes32 _permissionId, bytes calldata _data)
        external
        view
        returns (bool)
    {
        _who; // silence compiler warning & keep the function parameter name

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

        // check all actions when plugin is calling the DAO execute function
        (, IDAO.Action[] memory actions, ) = abi.decode(_data[4:], (bytes32, IDAO.Action[], uint256));
        uint256 actionsLength = actions.length;
        for (uint256 i; i < actionsLength;) {
            // return false if the contract or selector is not allowed
            mapping(bytes4 => bool) storage allowlist = _allowlist[actions[i].to];
            if (!allowlist[ANY_SELECTOR]) {
                if (!allowlist[bytes4(actions[i].data)]) {
                    return false;
                }
            }

            unchecked { ++i; }
        }

        // all actions are allowed
        return true;
    }


    /*----------------------------------------------------------*|
    |*  # ALLOWLIST                                             *|
    |*----------------------------------------------------------*/

    /// @notice Update the allowlist of contracts and their selectors that are allowed to call via the DAO execute function.
    /// @dev Only the DAO can call this function. Use `ANY_SELECTOR` to allow all selectors of the contract.
    /// @param _contract The contract address.
    /// @param _selector The function selector.
    /// @param _allowed True if the contract and selector is allowed to call via the DAO execute function.
    function setAllowlist(address _contract, bytes4 _selector, bool _allowed) external {
        if (msg.sender != dao) {
            revert CallerNotDAO();
        }
        _allowlist[_contract][_selector] = _allowed;
    }

    /// @notice Returns if a contract and selector is allowed to call via the DAO execute function.
    /// @param _contract The contract address.
    /// @param _selector The function selector.
    /// @return True if the contract and selector is allowed to call via the DAO execute function.
    function isAllowed(address _contract, bytes4 _selector) external view returns (bool) {
        return _allowlist[_contract][_selector];
    }

}
