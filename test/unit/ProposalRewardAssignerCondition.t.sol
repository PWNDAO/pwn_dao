// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";

import { ProposalRewardAssignerCondition } from "src/governance/permission/ProposalRewardAssignerCondition.sol";
import { IProposalReward } from "src/interfaces/IProposalReward.sol";

import { Base_Test } from "../Base.t.sol";

abstract contract ProposalRewardAssignerCondition_Test is Base_Test {

    address public dao = makeAddr("dao");
    address public proposalReward = makeAddr("proposalReward");
    address public who = makeAddr("who");
    bytes32 public DUMMY_EXECUTE_PERMISSION_ID = keccak256("DUMMY_EXECUTE_PERMISSION_ID");

    ProposalRewardAssignerCondition public condition;

    function setUp() external {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        condition = new ProposalRewardAssignerCondition(dao, proposalReward);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract ProposalRewardAssignerCondition_Constructor_Test is ProposalRewardAssignerCondition_Test {

    function testFuzz_shouldStoreConstructorArguments(address _dao, address _proposalReward)
        external
        checkAddress(_dao)
        checkAddress(_proposalReward)
    {
        vm.mockCall(
            _dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        condition = new ProposalRewardAssignerCondition(_dao, _proposalReward);

        assertEq(condition.dao(), _dao);
        assertEq(condition.proposalReward(), _proposalReward);
    }

    function testFuzz_shouldGetExecutePermissionIdFromDAO(bytes32 _permission) external {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(_permission)
        );

        condition = new ProposalRewardAssignerCondition(dao, proposalReward);

        assertEq(condition.EXECUTE_PERMISSION_ID(), _permission);
    }

}


/*----------------------------------------------------------*|
|*  # IS GRANTED                                            *|
|*----------------------------------------------------------*/

contract ProposalRewardAssignerCondition_IsGranted_Test is ProposalRewardAssignerCondition_Test {

    IDAO.Action[] public actions;

    function testFuzz_shouldReturnTrue_whenWhereIsNotDAO(address _where) external {
        vm.assume(_where != dao);

        bool isGranted = condition.isGranted({
            _where: _where,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: ""
        });

        assertTrue(isGranted);
    }

    function testFuzz_shouldReturnTrue_whenPermissionIsNotExecute(bytes32 permission) external {
        vm.assume(permission != DUMMY_EXECUTE_PERMISSION_ID);

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: permission,
            _data: ""
        });

        assertTrue(isGranted);
    }

    function testFuzz_shouldReturnTrue_whenDataLengthIsLessThan4(bytes memory data) external {
        vm.assume(data.length < 4);

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: data
        });

        assertTrue(isGranted);
    }

    function testFuzz_shouldReturnTrue_whenSelectorIsNotExecute(bytes4 selector) external {
        vm.assume(selector != IDAO.execute.selector);

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodePacked(selector)
        });

        assertTrue(isGranted);
    }

    function test_shouldReturnTrue_whenActionsNotContainProposalReward() external {
        actions.push(IDAO.Action({
            to: makeAddr("to"),
            value: 1,
            data: ""
        }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeWithSelector(IDAO.execute.selector, bytes32(0), actions, 0)
        });

        assertTrue(isGranted);
    }

    function test_shouldReturnTrue_whenActionsContainProposalReward_whenSettingsCorrectValues() external {
        uint256 proposalId = 420;
        actions.push(IDAO.Action({
            to: makeAddr("to"),
            value: 1,
            data: ""
        }));
        actions.push(IDAO.Action({
            to: proposalReward,
            value: 0,
            data: abi.encodeWithSelector(IProposalReward.assignProposalReward.selector, who, proposalId)
        }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeWithSelector(IDAO.execute.selector, bytes32(proposalId), actions, 0)
        });

        assertTrue(isGranted);
    }

    function testFuzz_shouldReturnFalse_whenActionsContainProposalReward_whenSettingsWrongVotingContract(
        address votingContract
    ) external {
        vm.assume(votingContract != who);

        uint256 proposalId = 420;
        actions.push(IDAO.Action({
            to: proposalReward,
            value: 0,
            data: abi.encodeWithSelector(IProposalReward.assignProposalReward.selector, votingContract, proposalId)
        }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeWithSelector(IDAO.execute.selector, bytes32(proposalId), actions, 0)
        });

        assertFalse(isGranted);
    }

    function testFuzz_shouldReturnFalse_whenActionsContainProposalReward_whenSettingsWrongProposalId(
        uint256 setProposalId
    ) external {
        uint256 proposalId = 420;
        vm.assume(setProposalId != proposalId);

        actions.push(IDAO.Action({
            to: proposalReward,
            value: 0,
            data: abi.encodeWithSelector(IProposalReward.assignProposalReward.selector, who, setProposalId)
        }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeWithSelector(IDAO.execute.selector, bytes32(proposalId), actions, 0)
        });

        assertFalse(isGranted);
    }

}
