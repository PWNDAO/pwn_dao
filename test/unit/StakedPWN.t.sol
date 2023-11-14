// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { StakedPWN } from "../../src/StakedPWN.sol";

import { BasePWNTest } from "../BasePWNTest.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";


abstract contract StakedPWNTest is BasePWNTest {
    using SlotComputingLib for bytes32;

    bytes32 public constant OWNERS_SLOT = bytes32(uint256(2));
    bytes32 public constant BALANCES_SLOT = bytes32(uint256(3));
    bytes4 public constant ON_ERC721_RECEIVED_SELECTOR = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    StakedPWN public stakedPWN;

    address public stakingContract = makeAddr("stakingContract");

    function setUp() virtual public {
        stakedPWN = new StakedPWN(stakingContract);

        vm.mockCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)"),
            abi.encode("")
        );
    }


    function _mockToken(address owner, uint256 tokenId) internal {
        vm.store(
            address(stakedPWN), OWNERS_SLOT.withMappingKey(tokenId), bytes32(uint256(uint160(owner)))
        );
        vm.store(
            address(stakedPWN), BALANCES_SLOT.withMappingKey(owner), bytes32(uint256(1))
        );
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract StakedPWN_Constructor_Test is StakedPWNTest {

    function testFuzz_shouldSetInitialParams(address stakingContract) external {
        stakedPWN = new StakedPWN(stakingContract);

        assertEq(address(stakedPWN.stakingContract()), stakingContract);
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
        stakedPWN.mint(caller, 420);
    }

    function testFuzz_shouldMintStakedPWNToken(address to, uint256 tokenId) external checkAddress(to) {
        vm.assume(to.code.length == 0);
        vm.expectCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)", address(0), to, tokenId)
        );

        vm.prank(stakingContract);
        stakedPWN.mint(to, tokenId);

        assertEq(stakedPWN.ownerOf(tokenId), to);
    }

    function testFuzz_shouldCallSafeCallback_whenCallerIsContract(address to, uint256 tokenId) external checkAddress(to) {
        vm.mockCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR),
            abi.encode(ON_ERC721_RECEIVED_SELECTOR)
        );

        vm.expectCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR, stakingContract, address(0), tokenId, bytes(""))
        );

        vm.prank(stakingContract);
        stakedPWN.mint(to, tokenId);
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
        stakedPWN.burn(420);
    }

    function testFuzz_shouldBurnStakedPWNToken(address from, uint256 tokenId) external checkAddress(from) {
        _mockToken(from, tokenId);
        vm.expectCall(
            stakingContract,
            abi.encodeWithSignature("transferStake(address,address,uint256)", from, address(0), tokenId)
        );

        vm.prank(stakingContract);
        stakedPWN.burn(tokenId);

        vm.expectRevert();
        stakedPWN.ownerOf(tokenId);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER CALLBACK                                     *|
|*----------------------------------------------------------*/

contract StakedPWN_TransferCallback_Test is StakedPWNTest {

    function testFuzz_shouldCallCallback_whenTransferFrom(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        _mockToken(from, tokenId);

        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 1
        });

        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);
    }

    function testFuzz_shouldNotCallCallback_whenTransferFromFails(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 0
        });

        vm.expectRevert();
        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);
    }

    function testFuzz_shouldCallCallback_whenSafeTransferFrom(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        _mockToken(from, tokenId);
        vm.mockCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR),
            abi.encode(ON_ERC721_RECEIVED_SELECTOR)
        );

        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 1
        });

        vm.prank(from);
        stakedPWN.safeTransferFrom(from, to, tokenId);
    }

    function testFuzz_shouldNotCallCallback_whenSafeTransferFromFails(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.mockCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR),
            abi.encode(ON_ERC721_RECEIVED_SELECTOR)
        );

        vm.expectCall({
            callee: stakingContract,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 0
        });

        vm.expectRevert();
        vm.prank(from);
        stakedPWN.safeTransferFrom(from, to, tokenId);
    }

}
