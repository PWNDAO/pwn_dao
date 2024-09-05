// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { Error } from "src/lib/Error.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";

import { Base_Test } from "test/Base.t.sol";

abstract contract StakedPWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant OWNER_SLOT = bytes32(uint256(0));
    bytes32 public constant OWNERS_SLOT = bytes32(uint256(4));
    bytes32 public constant BALANCES_SLOT = bytes32(uint256(5));
    bytes32 public constant TRANSFERS_ENABLED_SLOT = bytes32(uint256(8));
    bytes32 public constant OWNED_TOKENS_IN_EPOCHS = bytes32(uint256(9));

    StakedPWN public stakedPWN;

    address public owner = makeAddr("owner");
    address public epochClock = makeAddr("epochClock");
    address public supplyManager = makeAddr("supplyManager");
    uint16 public currentEpoch = 42;

    function setUp() virtual public {
        stakedPWN = new StakedPWN(owner, epochClock, supplyManager);

        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );
    }


    function _mockToken(address _owner, uint256 tokenId) internal {
        _mockToken(_owner, tokenId, 1);
    }

    function _mockToken(address _owner, uint256 tokenId, uint256 balance) internal {
        vm.store(address(stakedPWN), OWNERS_SLOT.withMappingKey(tokenId), bytes32(uint256(uint160(_owner))));
        vm.store(address(stakedPWN), BALANCES_SLOT.withMappingKey(_owner), bytes32(balance));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract StakedPWN_Constructor_Test is StakedPWN_Test {

    function testFuzz_shouldSetInitialParams(address _owner, address _epochClock, address _supplyManager) external {
        stakedPWN = new StakedPWN(_owner, _epochClock, _supplyManager);

        assertEq(address(stakedPWN.owner()), _owner);
        assertEq(address(stakedPWN.epochClock()), _epochClock);
        assertEq(address(stakedPWN.supplyManager()), _supplyManager);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Mint_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotSupplyManager(address caller) external {
        vm.assume(caller != supplyManager);

        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotSupplyManager.selector));
        vm.prank(caller);
        stakedPWN.mint(caller, 420);
    }

    function testFuzz_shouldMintStakedPWNToken(address to, uint256 tokenId) external checkAddress(to) {
        vm.assume(to.code.length == 0);

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);

        assertEq(stakedPWN.ownerOf(tokenId), to);
    }

    function testFuzz_shouldMintStakedPWNToken_whenTransfersDisabled(address to, uint256 tokenId)
        external
        checkAddress(to)
    {
        vm.assume(to.code.length == 0);
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(0));

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);

        assertEq(stakedPWN.ownerOf(tokenId), to);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Burn_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotSupplyManager(address caller) external {
        uint256 tokenId = 420;
        vm.assume(caller != supplyManager);
        _mockToken(caller, tokenId);

        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotSupplyManager.selector));
        vm.prank(caller);
        stakedPWN.burn(tokenId);
    }

    function testFuzz_shouldBurnStakedPWNToken(address from, uint256 tokenId) external checkAddress(from) {
        _mockToken(from, tokenId);

        vm.prank(supplyManager);
        stakedPWN.burn(tokenId);

        vm.expectRevert();
        stakedPWN.ownerOf(tokenId);
    }

    function test_shouldBurnStakedPWNToken_whenTransfersDisabled(address from, uint256 tokenId)
        external
        checkAddress(from)
    {
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(0));
        _mockToken(from, tokenId);

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
|*  # METADATA                                              *|
|*----------------------------------------------------------*/

contract StakedPWN_Metadata_Test is StakedPWN_Test {

    function testFuzz_shouldReturnMetadataURI(uint256 tokenId, string memory metadata) external {
        vm.mockCall(
            supplyManager,
            abi.encodeWithSignature("stakeMetadata(uint256)", tokenId),
            abi.encode(metadata)
        );
        vm.expectCall(supplyManager, abi.encodeWithSignature("stakeMetadata(uint256)", tokenId));

        assertEq(stakedPWN.tokenURI(tokenId), metadata);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER                                              *|
|*----------------------------------------------------------*/

contract StakedPWN_Transfer_Test is StakedPWN_Test {

    function setUp() override public {
        super.setUp();
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(uint256(1)));
    }

    function testFuzz_shouldFail_whenTransfersNotEnabled(address from, address to, uint256 tokenId)
        external
        checkAddress(from)
        checkAddress(to)
    {
        vm.store(address(stakedPWN), TRANSFERS_ENABLED_SLOT, bytes32(0));
        _mockToken(from, tokenId);

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersDisabled.selector));
        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);
    }

}
