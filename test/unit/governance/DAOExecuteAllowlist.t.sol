// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";

import { DAOExecuteAllowlist } from "src/governance/permission/DAOExecuteAllowlist.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";

import { Base_Test } from "test/Base.t.sol";

abstract contract DAOExecuteAllowlist_Test is Base_Test {

    bytes32 constant public ALLOWLIST_SLOT = bytes32(uint256(0));

    address public dao = makeAddr("dao");
    address public who = makeAddr("who");
    bytes32 public DUMMY_EXECUTE_PERMISSION_ID = keccak256("DUMMY_EXECUTE_PERMISSION_ID");
    bytes4 public ANY_SELECTOR;

    DAOExecuteAllowlist public condition;

    function setUp() external {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        condition = new DAOExecuteAllowlist(dao);

        ANY_SELECTOR = condition.ANY_SELECTOR();
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract DAOExecuteAllowlist_Constructor_Test is DAOExecuteAllowlist_Test {

    function testFuzz_shouldStoreConstructorArguments(address _dao) external checkAddress(_dao) {
        vm.etch(_dao, "data");
        vm.mockCall(
            _dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(DUMMY_EXECUTE_PERMISSION_ID)
        );

        condition = new DAOExecuteAllowlist(_dao);

        assertEq(condition.dao(), _dao);
    }

    function testFuzz_shouldGetExecutePermissionIdFromDAO(bytes32 _permission) external {
        vm.mockCall(
            dao,
            abi.encodeWithSignature("EXECUTE_PERMISSION_ID()"),
            abi.encode(_permission)
        );

        condition = new DAOExecuteAllowlist(dao);

        assertEq(condition.EXECUTE_PERMISSION_ID(), _permission);
    }

}


/*----------------------------------------------------------*|
|*  # IS GRANTED                                            *|
|*----------------------------------------------------------*/

contract DAOExecuteAllowlist_IsGranted_Test is DAOExecuteAllowlist_Test {

    address _contract = makeAddr("contract");
    bytes4 _selector = bytes4(keccak256("selector"));
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

    function test_shouldReturnFalse_whenSelectorNotAllowed() external {
        vm.prank(dao);
        condition.setAllowlist(_contract, _selector, false);

        actions.push(IDAO.Action({ to: _contract, value: 0, data: abi.encodePacked(_selector) }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeCall(IDAO.execute, (0, actions, 0))
        });

        assertFalse(isGranted);
    }

    function test_shouldReturnTrue_whenSelectorAllowed() external {
        vm.prank(dao);
        condition.setAllowlist(_contract, _selector, true);

        actions.push(IDAO.Action({ to: _contract, value: 0, data: abi.encodePacked(_selector) }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeCall(IDAO.execute, (0, actions, 0))
        });

        assertTrue(isGranted);
    }

    function test_shouldReturnTrue_whenAnySelectorAllowed() external {
        vm.prank(dao);
        condition.setAllowlist(_contract, ANY_SELECTOR, true);

        actions.push(IDAO.Action({ to: _contract, value: 0, data: abi.encodePacked(_selector) }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeCall(IDAO.execute, (0, actions, 0))
        });

        assertTrue(isGranted);
    }

    function test_shouldReturnTrue_whenAllActionsAllowed() external {
        address _contract1 = makeAddr("contract1");
        address _contract2 = makeAddr("contract2");

        vm.startPrank(dao);
        condition.setAllowlist(_contract1, ANY_SELECTOR, true);
        condition.setAllowlist(_contract2, ANY_SELECTOR, true);
        vm.stopPrank();

        actions.push(IDAO.Action({ to: _contract1, value: 0, data: abi.encodePacked(keccak256("selector1")) }));
        actions.push(IDAO.Action({ to: _contract2, value: 0, data: abi.encodePacked(keccak256("selector2")) }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeCall(IDAO.execute, (0, actions, 0))
        });

        assertTrue(isGranted);
    }

    function test_shouldReturnFalse_whenAnyActionNotAllowed() external {
        address _contract1 = makeAddr("contract1");
        address _contract2 = makeAddr("contract2");

        vm.startPrank(dao);
        condition.setAllowlist(_contract1, ANY_SELECTOR, true);
        condition.setAllowlist(_contract2, ANY_SELECTOR, false);
        vm.stopPrank();

        actions.push(IDAO.Action({ to: _contract1, value: 0, data: abi.encodePacked(keccak256("selector1")) }));
        actions.push(IDAO.Action({ to: _contract2, value: 0, data: abi.encodePacked(keccak256("selector2")) }));

        bool isGranted = condition.isGranted({
            _where: dao,
            _who: who,
            _permissionId: DUMMY_EXECUTE_PERMISSION_ID,
            _data: abi.encodeCall(IDAO.execute, (0, actions, 0))
        });

        assertFalse(isGranted);
    }

}


/*----------------------------------------------------------*|
|*  # SET ALLOWLIST                                         *|
|*----------------------------------------------------------*/

contract DAOExecuteAllowlist_SetAllowlist_Test is DAOExecuteAllowlist_Test {

    function testFuzz_shouldFail_whenCallerIsNotDAO(address caller) external checkAddress(caller) {
        vm.assume(caller != dao);

        vm.expectRevert(abi.encodeWithSelector(DAOExecuteAllowlist.CallerNotDAO.selector));
        vm.prank(caller);
        condition.setAllowlist(address(0), 0, true);
    }

    function testFuzz_shouldStoreAllowlistValue(address _contract, bytes4 _selector) external {
        vm.prank(dao);
        condition.setAllowlist(_contract, _selector, true);
        assertTrue(condition.isAllowed(_contract, _selector));

        vm.prank(dao);
        condition.setAllowlist(_contract, _selector, false);
        assertFalse(condition.isAllowed(_contract, _selector));
    }

}


/*----------------------------------------------------------*|
|*  # IS ALLOWED                                            *|
|*----------------------------------------------------------*/

contract DAOExecuteAllowlist_IsAllowed_Test is DAOExecuteAllowlist_Test {
    using SlotComputingLib for bytes32;

    function testFuzz_shouldReturnStoredValue(address _contract, bytes4 _selector) external {
        assertFalse(condition.isAllowed(_contract, _selector));

        vm.store(
            address(condition),
            ALLOWLIST_SLOT.withMappingKey(_contract).withMappingKey(_selector),
            bytes32(uint256(1))
        );
        assertTrue(condition.isAllowed(_contract, _selector));
    }

}
