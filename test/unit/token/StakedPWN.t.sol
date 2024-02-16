// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "src/lib/Error.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";

import { StakedPWNHarness } from "test/harness/StakedPWNHarness.sol";
import { Base_Test } from "test/Base.t.sol";

abstract contract StakedPWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant OWNER_SLOT = bytes32(uint256(0));
    bytes32 public constant OWNERS_SLOT = bytes32(uint256(4));
    bytes32 public constant BALANCES_SLOT = bytes32(uint256(5));
    bytes32 public constant TRANSFERS_ENABLED_SLOT = bytes32(uint256(8));
    bytes32 public constant OWNED_TOKENS_IN_EPOCHS = bytes32(uint256(9));

    StakedPWNHarness public stakedPWN;

    address public owner = makeAddr("owner");
    address public epochClock = makeAddr("epochClock");
    address public supplyManager = makeAddr("supplyManager");
    uint16 public currentEpoch = 42;

    function setUp() virtual public {
        stakedPWN = new StakedPWNHarness(owner, epochClock, supplyManager);

        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );
    }


    function _mockToken(address _owner, uint256 tokenId, uint16 epoch) internal {
        _mockToken(_owner, tokenId, epoch, 1);
    }

    function _mockToken(address _owner, uint256 tokenId, uint16 epoch, uint256 balance) internal {
        vm.store(address(stakedPWN), OWNERS_SLOT.withMappingKey(tokenId), bytes32(uint256(uint160(_owner))));
        vm.store(address(stakedPWN), BALANCES_SLOT.withMappingKey(_owner), bytes32(balance));
        stakedPWN.exposed_addIdToList(_owner, tokenId, epoch);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract StakedPWN_Constructor_Test is StakedPWN_Test {

    function testFuzz_shouldSetInitialParams(address _owner, address _epochClock, address _supplyManager) external {
        stakedPWN = new StakedPWNHarness(_owner, _epochClock, _supplyManager);

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

    function testFuzz_shouldUpdateOwnedTokens_whenSameEpoch(address to, uint256 seed) external checkAddress(to) {
        vm.assume(to.code.length == 0);
        uint256 length = bound(seed, 0, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(to, i + 1, currentEpoch + 1, i + 1);
        }
        uint256 tokenId = length + 1;

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);

        uint256[] memory ownedTokens = stakedPWN.ownedTokenIdsAt(to, currentEpoch + 1);
        assertEq(ownedTokens.length, length + 1);
        assertEq(ownedTokens.length, stakedPWN.balanceOf(to));
        for (uint256 i; i < ownedTokens.length; ++i) {
            assertEq(ownedTokens[i], i + 1);
        }
    }

    function testFuzz_shouldUpdateOwnedTokens_whenNotSameEpoch(
        address to, uint256 seed, uint256 epoch
    ) external checkAddress(to) {
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        vm.assume(to.code.length == 0);
        uint256 length = bound(seed, 0, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(to, i + 1, _epoch, i + 1);
        }
        uint256 tokenId = length + 1;

        vm.prank(supplyManager);
        stakedPWN.mint(to, tokenId);

        // updated list
        uint256[] memory updatedOwnedTokens = stakedPWN.ownedTokenIdsAt(to, currentEpoch + 1);
        assertEq(updatedOwnedTokens.length, length + 1);
        assertEq(updatedOwnedTokens.length, stakedPWN.balanceOf(to));
        for (uint256 i; i < updatedOwnedTokens.length; ++i) {
            assertEq(updatedOwnedTokens[i], i + 1);
        }

        // original list
        uint256[] memory originalOwnedTokens = stakedPWN.ownedTokenIdsAt(to, _epoch);
        assertEq(originalOwnedTokens.length, length);
        for (uint256 i; i < originalOwnedTokens.length; ++i) {
            assertEq(originalOwnedTokens[i], i + 1);
        }
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract StakedPWN_Burn_Test is StakedPWN_Test {

    function testFuzz_shouldFail_whenCallerNotSupplyManager(address caller) external {
        uint256 tokenId = 420;
        vm.assume(caller != supplyManager);
        _mockToken(caller, tokenId, currentEpoch);

        vm.expectRevert(abi.encodeWithSelector(Error.CallerNotSupplyManager.selector));
        vm.prank(caller);
        stakedPWN.burn(tokenId);
    }

    function testFuzz_shouldBurnStakedPWNToken(address from, uint256 tokenId) external checkAddress(from) {
        _mockToken(from, tokenId, currentEpoch);

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
        _mockToken(from, tokenId, currentEpoch);

        vm.prank(supplyManager);
        stakedPWN.burn(tokenId);

        vm.expectRevert();
        stakedPWN.ownerOf(tokenId);
    }

    function testFuzz_shouldUpdateOwnedTokens_whenSameEpoch(address from, uint256 seed, uint256 tokenId)
        external
        checkAddress(from)
    {
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(from, i + 1, currentEpoch + 1, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(supplyManager);
        stakedPWN.burn(tokenId);

        uint256[] memory ownedTokens = stakedPWN.ownedTokenIdsAt(from, currentEpoch + 1);
        assertEq(ownedTokens.length, length - 1);
        assertEq(ownedTokens.length, stakedPWN.balanceOf(from));
        for (uint256 i; i < ownedTokens.length; ++i) {
            assertNotEq(ownedTokens[i], tokenId);
        }
    }

    function testFuzz_shouldUpdateOwnedTokens_whenNotSameEpoch(
        address from, uint256 seed, uint256 tokenId, uint256 epoch
    ) external checkAddress(from) {
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(from, i + 1, _epoch, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(supplyManager);
        stakedPWN.burn(tokenId);

        // updated list
        uint256[] memory updatedOwnedTokens = stakedPWN.ownedTokenIdsAt(from, currentEpoch + 1);
        assertEq(updatedOwnedTokens.length, length - 1);
        assertEq(updatedOwnedTokens.length, stakedPWN.balanceOf(from));
        for (uint256 i; i < updatedOwnedTokens.length; ++i) {
            assertNotEq(updatedOwnedTokens[i], tokenId);
        }

        // original list
        uint256[] memory originalOwnedTokens = stakedPWN.ownedTokenIdsAt(from, _epoch);
        assertEq(originalOwnedTokens.length, length);
        for (uint256 i; i < originalOwnedTokens.length; ++i) {
            assertEq(originalOwnedTokens[i], i + 1);
        }
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
|*  # OWNED TOKENS IN EPOCHS                                *|
|*----------------------------------------------------------*/

contract StakedPWN_OwnedTokensInEpochs_Test is StakedPWN_Test {

    address public staker = makeAddr("staker");

    function testFuzz_shouldReturnListOfOwnedTokens(uint256 epochs, uint256 seed) external {
        epochs = bound(epochs, 1, 10);
        seed = bound(seed, 0, type(uint256).max - epochs);
        uint256 tokenId;
        for (uint256 i; i < epochs; ++i) {
            uint16 epoch = uint16(i + 1);
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            uint256 length = bound(iSeed, 1, 10);
            for (uint256 j; j < length; ++j) {
                _mockToken(staker, ++tokenId, epoch);
            }
        }

        StakedPWN.OwnedTokensInEpoch[] memory ownedTokenIds = stakedPWN.ownedTokensInEpochs(staker);

        assertEq(ownedTokenIds.length, epochs);
        uint256 totalLength;
        for (uint256 i; i < epochs; ++i) {
            uint256 iSeed = uint256(keccak256(abi.encode(seed + i)));
            totalLength += bound(iSeed, 1, 10);
            assertEq(ownedTokenIds[i].epoch, uint16(i + 1));
            assertEq(ownedTokenIds[i].ids.length, totalLength);
            for (uint256 j; j < totalLength; ++j) {
                assertEq(ownedTokenIds[i].ids[j], j + 1);
            }
        }
    }

}


/*----------------------------------------------------------*|
|*  # OWNED TOKEN IDS AT                                    *|
|*----------------------------------------------------------*/

contract StakedPWN_OwnedTokenIdsAt_Test is StakedPWN_Test {

    address public staker = makeAddr("staker");

    function testFuzz_shouldReturnEmpty_whenNoOwnedTokens(uint16 epoch) external {
        // don't mock tokens

        uint256[] memory ids = stakedPWN.ownedTokenIdsAt(staker, epoch);

        assertEq(ids.length, 0);
    }

    function testFuzz_shouldReturnEmpty_whenEpochBeforeFirstOwnedTokens(uint256 epoch) external {
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        _mockToken(staker, 1, _epoch);

        uint256[] memory ids = stakedPWN.ownedTokenIdsAt(staker, _epoch - 1);

        assertEq(ids.length, 0);
    }

    function test_shouldReturnListOfOwnedTokenIdsForEpoch() external {
        uint16[] memory epochs = new uint16[](3);
        epochs[0] = 1;
        epochs[1] = 10;
        epochs[2] = 20;

        _mockToken(staker, 1, epochs[0]);
        _mockToken(staker, 2, epochs[1]);
        _mockToken(staker, 3, epochs[2]);

        uint256[] memory ids = stakedPWN.ownedTokenIdsAt(staker, 1);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        ids = stakedPWN.ownedTokenIdsAt(staker, 9);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        ids = stakedPWN.ownedTokenIdsAt(staker, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);

        ids = stakedPWN.ownedTokenIdsAt(staker, 14);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);

        ids = stakedPWN.ownedTokenIdsAt(staker, 21);
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
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
        _mockToken(from, tokenId, currentEpoch);

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersDisabled.selector));
        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);
    }

    function testFuzz_shouldUpdateOwnedTokens_whenSameEpoch_whenDifferentSenderAndReceiver(
        address from, address to, uint256 seed, uint256 tokenId
    ) external checkAddress(from) checkAddress(to) {
        vm.assume(from != to);
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(from, i + 1, currentEpoch + 1, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);

        uint256[] memory fromOwnedTokens = stakedPWN.ownedTokenIdsAt(from, currentEpoch + 1);
        assertEq(fromOwnedTokens.length, length - 1);
        assertEq(fromOwnedTokens.length, stakedPWN.balanceOf(from));
        for (uint256 i; i < fromOwnedTokens.length; ++i) {
            assertNotEq(fromOwnedTokens[i], tokenId);
        }

        uint256[] memory toOwnedTokens = stakedPWN.ownedTokenIdsAt(to, currentEpoch + 1);
        assertEq(toOwnedTokens.length, 1);
        assertEq(toOwnedTokens.length, stakedPWN.balanceOf(to));
        assertEq(toOwnedTokens[0], tokenId);
    }

    function testFuzz_shouldUpdateOwnedTokens_whenSameEpoch_whenSameSenderAndReceiver(
        address sender, uint256 seed, uint256 tokenId
    ) external checkAddress(sender) {
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(sender, i + 1, currentEpoch + 1, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(sender);
        stakedPWN.transferFrom(sender, sender, tokenId);

        uint256[] memory fromOwnedTokens = stakedPWN.ownedTokenIdsAt(sender, currentEpoch + 1);
        assertEq(fromOwnedTokens.length, length);
        assertEq(fromOwnedTokens.length, stakedPWN.balanceOf(sender));
        // check that all ids are included
        for (uint256 i; i < length; ++i) {
            uint256 j;
            while (fromOwnedTokens[j] != i + 1) {
                if (j >= length) { assert(false); }
                ++j;
            }
        }
    }

    function testFuzz_shouldUpdateOwnedTokens_whenDifferentEpoch_whenDifferentSenderAndReceiver(
        address from, address to, uint256 seed, uint256 tokenId, uint256 epoch
    ) external checkAddress(from) checkAddress(to) {
        vm.assume(from != to);
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(from, i + 1, _epoch, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(from);
        stakedPWN.transferFrom(from, to, tokenId);

        uint256[] memory fromUpdatedOwnedTokens = stakedPWN.ownedTokenIdsAt(from, currentEpoch + 1);
        assertEq(fromUpdatedOwnedTokens.length, length - 1);
        assertEq(fromUpdatedOwnedTokens.length, stakedPWN.balanceOf(from));
        for (uint256 i; i < fromUpdatedOwnedTokens.length; ++i) {
            assertNotEq(fromUpdatedOwnedTokens[i], tokenId);
        }

        uint256[] memory fromOriginalOwnedTokens = stakedPWN.ownedTokenIdsAt(from, _epoch);
        assertEq(fromOriginalOwnedTokens.length, length);
        for (uint256 i; i < fromOriginalOwnedTokens.length; ++i) {
            assertEq(fromOriginalOwnedTokens[i], i + 1);
        }

        uint256[] memory toUpdatedOwnedTokens = stakedPWN.ownedTokenIdsAt(to, currentEpoch + 1);
        assertEq(toUpdatedOwnedTokens.length, 1);
        assertEq(toUpdatedOwnedTokens.length, stakedPWN.balanceOf(to));
        assertEq(toUpdatedOwnedTokens[0], tokenId);

        uint256[] memory toOriginalOwnedTokens = stakedPWN.ownedTokenIdsAt(to, _epoch);
        assertEq(toOriginalOwnedTokens.length, 0);
    }

    function testFuzz_shouldUpdateOwnedTokens_whenDifferentEpoch_whenSameSenderAndReceiver(
        address sender, uint256 seed, uint256 tokenId, uint256 epoch
    ) external checkAddress(sender) {
        uint16 _epoch = uint16(bound(epoch, 1, currentEpoch));
        uint256 length = bound(seed, 1, 10);
        for (uint256 i; i < length; ++i) {
            _mockToken(sender, i + 1, _epoch, i + 1);
        }
        tokenId = bound(tokenId, 1, length);

        vm.prank(sender);
        stakedPWN.transferFrom(sender, sender, tokenId);

        uint256[] memory senderUpdatedOwnedTokens = stakedPWN.ownedTokenIdsAt(sender, currentEpoch + 1);
        assertEq(senderUpdatedOwnedTokens.length, length);
        assertEq(senderUpdatedOwnedTokens.length, stakedPWN.balanceOf(sender));
        // check that all ids are included
        for (uint256 i; i < length; ++i) {
            uint256 j;
            while (senderUpdatedOwnedTokens[j] != i + 1) {
                if (j >= length) { assert(false); }
                ++j;
            }
        }

        uint256[] memory senderOriginalOwnedTokens = stakedPWN.ownedTokenIdsAt(sender, _epoch);
        assertEq(senderOriginalOwnedTokens.length, length);
        for (uint256 i; i < senderOriginalOwnedTokens.length; ++i) {
            assertEq(senderOriginalOwnedTokens[i], i + 1);
        }
    }

}
