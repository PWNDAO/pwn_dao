// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "src/lib/Error.sol";
import { StakedPWN } from "src/StakedPWN.sol";

import { Base_Test } from "../Base.t.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";

abstract contract StakedPWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant OWNER_SLOT = bytes32(uint256(0));
    bytes32 public constant OWNERS_SLOT = bytes32(uint256(4));
    bytes32 public constant BALANCES_SLOT = bytes32(uint256(5));
    bytes32 public constant TRANSFERS_ENABLED_SLOT = bytes32(uint256(8));
    bytes4 public constant ON_ERC721_RECEIVED_SELECTOR
        = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    StakedPWN public stakedPWN;

    address public owner = makeAddr("owner");
    address public supplyManager = makeAddr("supplyManager");

    function setUp() virtual public {
        stakedPWN = new StakedPWN(owner, supplyManager);

        vm.mockCall(
            supplyManager,
            abi.encodeWithSignature("transferStake(address,address,uint256)"),
            abi.encode("")
        );
    }


    function _mockToken(address _owner, uint256 tokenId) internal {
        vm.store(
            address(stakedPWN), OWNERS_SLOT.withMappingKey(tokenId), bytes32(uint256(uint160(_owner)))
        );
        vm.store(
            address(stakedPWN), BALANCES_SLOT.withMappingKey(_owner), bytes32(uint256(1))
        );
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract StakedPWN_Constructor_Test is StakedPWN_Test {

    function testFuzz_shouldSetInitialParams(address _supplyManager) external {
        stakedPWN = new StakedPWN(owner, _supplyManager);

        assertEq(address(stakedPWN.owner()), owner);
        assertEq(address(stakedPWN.supplyManager()), _supplyManager);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Mint_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotVoteEscrowedPWN(address caller) external {
        vm.assume(caller != supplyManager);

        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotSupplyManager.selector));
        vm.prank(caller);
        stakedPWN.mint(caller, 420);
    }

    function testFuzz_shouldMintStakedPWNToken(address to, uint256 tokenId) external checkAddress(to) {
        vm.assume(to.code.length == 0);
        vm.expectCall(
            supplyManager,
            abi.encodeWithSignature("transferStake(address,address,uint256)", address(0), to, tokenId)
        );

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);

        assertEq(stakedPWN.ownerOf(tokenId), to);
    }

    function testFuzz_shouldCallSafeCallback_whenCallerIsContract(
        address to, uint256 tokenId
    ) external checkAddress(to) {
        vm.mockCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR),
            abi.encode(ON_ERC721_RECEIVED_SELECTOR)
        );

        vm.expectCall(
            to,
            abi.encodeWithSelector(ON_ERC721_RECEIVED_SELECTOR, supplyManager, address(0), tokenId, bytes(""))
        );

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Burn_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotVoteEscrowedPWN(address caller) external {
        vm.assume(caller != supplyManager);
        _mockToken(caller, 420);

        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotSupplyManager.selector));
        vm.prank(caller);
        stakedPWN.burn(420);
    }

    function testFuzz_shouldBurnStakedPWNToken(address from, uint256 tokenId) external checkAddress(from) {
        _mockToken(from, tokenId);
        vm.expectCall(
            supplyManager,
            abi.encodeWithSignature("transferStake(address,address,uint256)", from, address(0), tokenId)
        );

        vm.prank(supplyManager);
        stakedPWN.burn(tokenId);

        vm.expectRevert();
        stakedPWN.ownerOf(tokenId);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER SWITCH                                       *|
|*----------------------------------------------------------*/

contract StakedPWN_EnableTransfer_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        stakedPWN.enableTransfers();
    }

    function test_shouldFail_whenTransfersEnabled() external {
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersAlreadyEnabled.selector));
        vm.prank(owner);
        stakedPWN.enableTransfers();
    }

    function test_shouldEnableTransfers() external {
        vm.prank(owner);
        stakedPWN.enableTransfers();

        bytes32 transfersEnabledValue = vm.load(address(stakedPWN), TRANSFERS_ENABLED_SLOT);
        assertEq(uint256(transfersEnabledValue), 1);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER CALLBACK                                     *|
|*----------------------------------------------------------*/

contract StakedPWN_TransferCallback_Test is StakedPWN_Test {

    function setUp() override public {
        super.setUp();
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(uint256(1)));
    }

    function testFuzz_shouldFail_whenTransfersNotEnabled(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(0));
        _mockToken(from, tokenId);

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersDisabled.selector));
        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);
    }

    function testFuzz_shouldCallCallback_whenTransferFrom(
        address from, address to, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        _mockToken(from, tokenId);

        vm.expectCall({
            callee: supplyManager,
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
            callee: supplyManager,
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
            callee: supplyManager,
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
            callee: supplyManager,
            data: abi.encodeWithSignature("transferStake(address,address,uint256)", from, to, tokenId),
            count: 0
        });

        vm.expectRevert();
        vm.prank(from);
        stakedPWN.safeTransferFrom(from, to, tokenId);
    }

}
