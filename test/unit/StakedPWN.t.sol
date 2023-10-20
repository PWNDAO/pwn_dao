// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {StakedPWN} from "../../src/StakedPWN.sol";

import {BasePWNTest} from "../BasePWNTest.t.sol";
import {SlotComputingLib} from "../utils/SlotComputingLib.sol";


abstract contract StakedPWNTest is BasePWNTest {
    using SlotComputingLib for bytes32;

    bytes32 public constant OWNERS_SLOT = bytes32(uint256(2));
    bytes32 public constant BALANCES_SLOT = bytes32(uint256(3));

    StakedPWN public stakedPwn;

    address public stakingContract = makeAddr("stakingContract");

    function setUp() virtual public {
        stakedPwn = new StakedPWN(stakingContract);

        vm.mockCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)"),
            abi.encode("")
        );
    }


    function _mockToken(address owner, uint256 tokenId) internal {
        vm.store(
            address(stakedPwn), OWNERS_SLOT.withMappingKey(tokenId), bytes32(uint256(uint160(owner)))
        );
        vm.store(
            address(stakedPwn), OWNERS_SLOT.withMappingKey(owner), bytes32(uint256(1))
        );
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract StakedPWN_Constructor_Test is StakedPWNTest {

    function testFuzz_shouldSetInitialParams(address stakingContract) external {
        stakedPwn = new StakedPWN(stakingContract);

        assertEq(address(stakedPwn.stakingContract()), stakingContract);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Mint_Test is StakedPWNTest {

    function testFuzz_shouldFail_whenCallerNotStakingContract(address caller) external {
        vm.assume(caller != stakingContract);

        vm.expectRevert("StakedPWN: caller is not staking contract");
        vm.prank(caller);
        stakedPwn.mint(caller, 420);
    }

    function testFuzz_shouldMintStakedPWNToken(address to, uint256 tokenId) external checkAddress(to) {
        vm.expectCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)", address(0), to, tokenId)
        );

        vm.prank(stakingContract);
        stakedPwn.mint(to, tokenId);

        assertEq(stakedPwn.ownerOf(tokenId), to);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Burn_Test is StakedPWNTest {

    function testFuzz_shouldFail_whenCallerNotStakingContract(address caller) external {
        vm.assume(caller != stakingContract);
        _mockToken(caller, 420);

        vm.expectRevert("StakedPWN: caller is not staking contract");
        vm.prank(caller);
        stakedPwn.burn(420);
    }

    function testFuzz_shouldBurnStakedPWNToken(address from, uint256 tokenId) external checkAddress(from) {
        _mockToken(from, tokenId);
        vm.expectCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)", from, address(0), tokenId)
        );

        vm.prank(stakingContract);
        stakedPwn.burn(tokenId);

        vm.expectRevert();
        stakedPwn.ownerOf(tokenId);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER CALLBACK                                     *|
|*----------------------------------------------------------*/

contract StakedPWN_TransferCallback_Test is StakedPWNTest {

    function test_shouldCallCallback_whenTransferFrom(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        _mockToken(from, tokenId);

        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 1
        });

        vm.prank(from);
        stakedPwn.transferFrom(from, to, tokenId);
    }

    function test_shouldNotCallCallback_whenTransferFromFails(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 0
        });

        vm.expectRevert();
        vm.prank(from);
        stakedPwn.transferFrom(from, to, tokenId);
    }

    function test_shouldCallCallback_whenSafeTransferFrom(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        _mockToken(from, tokenId);

        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 1
        });

        vm.prank(from);
        stakedPwn.safeTransferFrom(from, to, tokenId);
    }

    function test_shouldNotCallCallback_whenSafeTransferFromFails(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 0
        });

        vm.expectRevert();
        vm.prank(from);
        stakedPwn.safeTransferFrom(from, to, tokenId);
    }

}
