// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {PWNFeeCollector, IPWNHub} from "../../src/PWNFeeCollector.sol";
import {PWNEpochClock} from "../../src/PWNEpochClock.sol";

import {SlotComputingLib} from "../utils/SlotComputingLib.sol";
import {MockWallet} from "../mock/MockWallet.sol";
import {BasePWNTest} from "../BasePWNTest.t.sol";


abstract contract PWNFeeCollectorTest is BasePWNTest {
    using SlotComputingLib for bytes32;

    bytes32 public constant CLAIMED_FEES_SLOT = bytes32(uint256(0));
    bytes32 public constant COLLECTED_FEES_SLOT = bytes32(uint256(1));

    PWNFeeCollector public collector;

    address public claimController = makeAddr("claimController");
    address public clock = makeAddr("clock");
    address public hub = makeAddr("hub");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        collector = new PWNFeeCollector(claimController, clock, hub);

        vm.etch(claimController, bytes("data"));
        vm.etch(clock, bytes("data"));
        vm.etch(hub, bytes("data"));

        vm.mockCall(
            clock,
            abi.encodeWithSelector(PWNEpochClock.currentEpoch.selector),
            abi.encode(currentEpoch)
        );
    }


    function _collectedFeesSlot(uint256 epoch, address asset) internal pure returns (bytes32) {
        return COLLECTED_FEES_SLOT.withMappingKey(epoch).withMappingKey(asset);
    }

    function _claimedFeesSlot(address staker, uint256 epoch, address asset) internal pure returns (bytes32) {
        return CLAIMED_FEES_SLOT.withMappingKey(staker).withMappingKey(epoch).withMappingKey(asset);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNFeeCollector_Constructor_Test is PWNFeeCollectorTest {

    function testFuzz_shouldStoreConstructorArgs(address _claimController, address _clock, address _hub) external {
        collector = new PWNFeeCollector(_claimController, _clock, _hub);

        assertEq(collector.claimController(), _claimController);
        assertEq(address(collector.epochClock()), _clock);
        assertEq(address(collector.hub()), _hub);
    }

}


/*----------------------------------------------------------*|
|*  # COLLECT FEES HOOK                                     *|
|*----------------------------------------------------------*/

contract PWNFeeCollector_CollectFeesHook_Test is PWNFeeCollectorTest {

    address public feeDistributor = makeAddr("feeDistributor");

    event FeeCollected(uint256 indexed epoch, address indexed asset, uint256 amount);

    function setUp() public override {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSelector(IPWNHub.hasTag.selector),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSelector(IPWNHub.hasTag.selector, feeDistributor, collector.FEE_DISTRIBUTOR_TAG()),
            abi.encode(true)
        );
    }


    function testFuzz_shouldFail_whenCallerNotFeeDistributor(address caller) external {
        vm.assume(caller != feeDistributor && caller != address(0));
        vm.expectRevert("PWNFeeCollector: caller is not fee distributor");
        vm.prank(caller);
        collector.collectFeesHook(makeAddr("asset"), 420);
    }

    function testFuzz_shouldIncreaseAssetAmount(
        uint256 epoch, address asset, uint256 prevAmount, uint256 amount
    ) external {
        amount = bound(amount, 0, type(uint256).max - prevAmount);

        vm.mockCall(
            clock,
            abi.encodeWithSelector(PWNEpochClock.currentEpoch.selector),
            abi.encode(epoch)
        );

        vm.store(
            address(collector),
            _collectedFeesSlot(epoch, asset),
            bytes32(prevAmount)
        );

        vm.prank(feeDistributor);
        collector.collectFeesHook(asset, amount);

        assertEq(collector.collectedFees(epoch, asset), prevAmount + amount);
    }

    function testFuzz_shouldEmit_FeeCollected(uint256 epoch, address asset, uint256 amount) external {
        vm.mockCall(
            clock,
            abi.encodeWithSelector(PWNEpochClock.currentEpoch.selector),
            abi.encode(epoch)
        );

        vm.expectEmit();
        emit FeeCollected(epoch, asset, amount);

        vm.prank(feeDistributor);
        collector.collectFeesHook(asset, amount);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM FEES                                            *|
|*----------------------------------------------------------*/

contract PWNFeeCollector_ClaimFees_Test is PWNFeeCollectorTest {

    address[] public assets = new address[](1);

    event FeeClaimed(uint256 indexed epoch, address indexed caller, address indexed asset, uint256 amount);

    // # MODIFIERS

    modifier mockAsset(address asset, uint256 amount) {
        assumeAddressIsNot(asset, AddressType.Precompile, AddressType.ForgeAddress);

        if (asset == address(0)) {
            vm.deal(address(collector), amount);
        } else {
            _mockERC20Asset(asset);
        }
        _;
    }

    modifier mockCollectedFees(uint256 epoch, address asset, uint256 amount) {
        _mockCollectedFees(epoch, asset, amount);
        _;
    }

    // # HELPERS

    function _checkAddress(address addr, bool allowZero) internal override {
        super._checkAddress(addr, allowZero);
        vm.assume(addr != address(collector) && addr != claimController && addr != clock && addr != hub);
    }

    function _boundEpoch(uint256 epoch) internal view returns (uint256) {
        return bound(epoch, 0, currentEpoch - 1);
    }

    function _mockCollectedFees(uint256 epoch, address asset, uint256 amount) internal {
        vm.store(address(collector), _collectedFeesSlot(epoch, asset), bytes32(amount));
    }

    function _mockERC20Asset(address asset) internal {
        vm.etch(asset, bytes("data"));
            vm.mockCall(
                asset,
                abi.encodeWithSignature("transfer(address,uint256)"),
                abi.encode(true)
            );
    }

    // # TESTS

    function testFuzz_shouldFail_whenCallerNotClaimController(address caller) external {
        vm.assume(caller != claimController && caller != address(0));

        vm.expectRevert("PWNFeeCollector: caller is not claim controller");
        vm.prank(caller);
        collector.claimFees({
            staker: makeAddr("staker"),
            epoch: currentEpoch - 1,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shoudlFail_whenEpochNotFinished(uint256 epoch) external {
        epoch = bound(epoch, currentEpoch, type(uint256).max);

        vm.expectRevert("PWNFeeCollector: epoch not finished");
        vm.prank(claimController);
        collector.claimFees({
            staker: makeAddr("staker"),
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldFail_whenAssetInEpochAlreadyClaimed(address staker, uint256 epoch, address asset) external
        checkAddress(staker)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = asset;

        vm.store(
            address(collector),
            _claimedFeesSlot(staker, epoch, asset),
            bytes32(uint256(1))
        );

        vm.expectRevert("PWNFeeCollector: asset already claimed");
        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldStoreClaimedAssetInEpoch(address staker, uint256 epoch, address asset, uint256 amount) external
        checkAddress(staker)
        checkAddress(asset)
        mockCollectedFees(_boundEpoch(epoch), asset, amount)
        mockAsset(asset, amount)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = asset;

        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });

        bytes32 claimedValue = vm.load(
            address(collector),
            _claimedFeesSlot(staker, epoch, asset)
        );
        assertEq(claimedValue, bytes32(uint256(1)));
    }

    function testFuzz_shouldClaimETH(address staker, uint256 epoch, uint256 amount) external
        checkAddress(staker)
        mockCollectedFees(_boundEpoch(epoch), address(0), amount)
        mockAsset(address(0), amount)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = address(0);

        uint256 prevBalance = staker.balance;

        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });

        assertEq(staker.balance, prevBalance + amount);
    }

    function testFuzz_shouldFail_whenETHTransferFails(uint256 epoch, uint256 amount) external
        mockCollectedFees(_boundEpoch(epoch), address(0), amount)
        mockAsset(address(0), amount)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = address(0);

        MockWallet staker = new MockWallet();

        vm.expectRevert("PWNFeeCollector: ETH transfer failed");
        vm.prank(claimController);
        collector.claimFees({
            staker: address(staker),
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldClaimERC20(address staker, uint256 epoch, address asset, uint256 amount) external
        checkAddress(staker)
        checkAddress(asset)
        mockCollectedFees(_boundEpoch(epoch), asset, amount)
        mockAsset(asset, amount)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = asset;

        vm.expectCall(
            asset, abi.encodeWithSignature("transfer(address,uint256)", staker, amount)
        );

        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldFail_whenERC20TransferFails(
        address staker, uint256 epoch, address asset, uint256 amount
    ) external
        checkAddress(staker)
        checkAddress(asset)
        mockCollectedFees(_boundEpoch(epoch), asset, amount)
        // don't mock asset
    {
        epoch = _boundEpoch(epoch);
        assets[0] = asset;

        vm.etch(asset, bytes("data"));
        vm.mockCall(
            asset,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(false)
        );

        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldEmit_FeeClaimed(address staker, uint256 epoch, address asset, uint256 amount) external
        checkAddress(staker)
        checkAddressAllowZero(asset)
        mockCollectedFees(_boundEpoch(epoch), asset, amount)
        mockAsset(asset, amount)
    {
        epoch = _boundEpoch(epoch);
        assets[0] = asset;

        vm.expectEmit();
        emit FeeClaimed(epoch, staker, asset, amount);

        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldFail_whenDupliciteAssets(address staker, uint256 epoch, address asset, uint256 amount) external
        checkAddress(staker)
        checkAddressAllowZero(asset)
        mockCollectedFees(_boundEpoch(epoch), asset, amount)
        mockAsset(asset, amount)
    {
        epoch = _boundEpoch(epoch);
        assets = new address[](2);
        assets[0] = asset;
        assets[1] = asset;

        vm.expectRevert("PWNFeeCollector: asset already claimed");
        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: epoch,
            assets: assets,
            stakerPower: 1,
            totalPower: 1
        });
    }

    function testFuzz_shouldClaimCorrectAmount(uint256 stakerPower, uint256 totalPower) external {
        // total supply with max multiplier after claiming all 1000 voting rewards
        uint256 maxStakerPower = 100_000_000e18 * 3.5 * 7;
        stakerPower = bound(stakerPower, 1, maxStakerPower);
        totalPower = bound(totalPower, stakerPower, type(uint256).max);

        address staker = makeAddr("staker");
        address asset = makeAddr("asset");
        uint256 amount = 1e18;

        assets[0] = asset;
        _mockCollectedFees(currentEpoch - 1, asset, amount);
        _mockERC20Asset(asset);

        vm.expectCall(
            asset, abi.encodeWithSignature("transfer(address,uint256)", staker, amount * stakerPower / totalPower)
        );

        vm.prank(claimController);
        collector.claimFees({
            staker: staker,
            epoch: currentEpoch - 1,
            assets: assets,
            stakerPower: stakerPower,
            totalPower: totalPower
        });
    }

}
