// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { BasePWNTest } from "../BasePWNTest.t.sol";


contract VoteEscrowedPWN_BaseExposed is VoteEscrowedPWN {

    function exposed_powerChangeFor(address staker, uint256 epoch) external pure returns (PowerChange memory pch) {
        return _powerChangeFor(staker, epoch);
    }

    struct StakerPowerInput {
        address staker;
        uint256 epoch;
    }
    StakerPowerInput public stakerPowerInput;
    uint256 public stakerPowerReturn;
    function stakerPower(address staker, uint256 epoch) virtual public view override returns (uint256) {
        require(stakerPowerInput.staker == staker, "stakerPower: staker");
        require(stakerPowerInput.epoch == epoch, "stakerPower: epoch");
        return stakerPowerReturn;
    }

    struct TotalPowerAtInput {
        uint256 epoch;
    }
    TotalPowerAtInput public totalPowerAtInput;
    uint256 public totalPowerAtReturn;
    function totalPowerAt(uint256 epoch) virtual public view override returns (uint256) {
        require(totalPowerAtInput.epoch == epoch, "totalPowerAt: epoch");
        return totalPowerAtReturn;
    }


    // helpers

    function _setStakerPowerInput(StakerPowerInput memory input) external {
        stakerPowerInput = input;
    }

    function _setStakerPowerReturn(uint256 value) external {
        stakerPowerReturn = value;
    }

    function _setTotalPowerAtInput(TotalPowerAtInput memory input) external {
        totalPowerAtInput = input;
    }

    function _setTotalPowerAtReturn(uint256 value) external {
        totalPowerAtReturn = value;
    }

}

abstract contract VoteEscrowedPWN_Base_Test is BasePWNTest {

    bytes32 public constant STAKERS_NAMESPACE = bytes32(uint256(keccak256("vePWN.stakers_namespace")) - 1);

    VoteEscrowedPWN_BaseExposed public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public feeCollector = makeAddr("feeCollector");
    address public owner = makeAddr("owner");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(
            epochClock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );

        vePWN = new VoteEscrowedPWN_BaseExposed();
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock,
            _feeCollector: feeCollector,
            _owner: owner
        });
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED FUNCTIONS                                      *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_Exposed_Test is VoteEscrowedPWN_Base_Test {
    using SlotComputingLib for bytes32;

    function testFuzz_shouldReturnCorrectPowerChange(address staker, uint256 epoch, int104 power) external {
        epoch = bound(epoch, 0, type(uint16).max);
        vm.store(
            address(vePWN),
            STAKERS_NAMESPACE.withMappingKey(staker).withArrayIndex(epoch),
            bytes32(uint256(uint104(power)))
        );

        assertEq(vePWN.exposed_powerChangeFor(staker, epoch).power, power);
    }

}


/*----------------------------------------------------------*|
|*  # IERC20                                                *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_IERC20_Test is VoteEscrowedPWN_Base_Test {

    function test_shouldReturnCorrectMetadata() external {
        assertEq(vePWN.name(), "Vote-escrowed PWN");
        assertEq(vePWN.symbol(), "vePWN");
        assertEq(vePWN.decimals(), 18);
    }

    function testFuzz_shouldReturnTotalPower_forTotalSupply(uint256 _totalSupply) external {
        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_BaseExposed.TotalPowerAtInput({ epoch: currentEpoch }));
        vePWN._setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.totalSupply();

        assertEq(totalSupply, _totalSupply);
    }

    function testFuzz_shouldReturnStakerPower_forBalanceOf(address holder, uint256 power) external {
        vePWN._setStakerPowerInput(VoteEscrowedPWN_BaseExposed.StakerPowerInput({ staker: holder, epoch: currentEpoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 balance = vePWN.balanceOf(holder);

        assertEq(balance, power);
    }

    function test_shouldHaveDisabledTransfer() external {
        address from = makeAddr("from");
        address to = makeAddr("to");
        uint256 amount = 420;

        vm.expectRevert("vePWN: transfer is disabled");
        vePWN.transfer(to, amount);

        vm.expectRevert("vePWN: transferFrom is disabled");
        vePWN.transferFrom(from, to, amount);

        vm.expectRevert("vePWN: approve is disabled");
        vePWN.approve(to, amount);

        uint256 allowance = vePWN.allowance(from, to);
        assertEq(allowance, 0);
    }

}


/*----------------------------------------------------------*|
|*  # VOTES                                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_Votes_Test is VoteEscrowedPWN_Base_Test {

    function testFuzz_shouldReturnStakerPower_forGetVotes(address voter, uint256 power) external {
        vePWN._setStakerPowerInput(VoteEscrowedPWN_BaseExposed.StakerPowerInput({ staker: voter, epoch: currentEpoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 votes = vePWN.getVotes(voter);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnStakerPower_forGetPastVotes(address voter, uint256 power, uint256 timepoint, uint16 epoch) external {
        vm.expectCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint));
        vm.mockCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint), abi.encode(epoch));

        vePWN._setStakerPowerInput(VoteEscrowedPWN_BaseExposed.StakerPowerInput({ staker: voter, epoch: epoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 votes = vePWN.getPastVotes(voter, timepoint);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnTotalPower_forGetPastTotalSupply(uint256 _totalSupply, uint256 timepoint, uint16 epoch) external {
        vm.expectCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint));
        vm.mockCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint), abi.encode(epoch));

        vePWN._setTotalPowerAtInput(VoteEscrowedPWN_BaseExposed.TotalPowerAtInput({ epoch: epoch }));
        vePWN._setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.getPastTotalSupply(timepoint);

        assertEq(totalSupply, _totalSupply);
    }

    function test_shouldHaveDisabledDelegation() external {
        address delegatee = makeAddr("delegatee");

        assertEq(vePWN.delegates(delegatee), address(0));

        vm.expectRevert("vePWN: delegate is disabled");
        vePWN.delegate(delegatee);

        vm.expectRevert("vePWN: delegateBySig is disabled");
        vePWN.delegateBySig(delegatee, 0, 0, 0, 0, 0);
    }

}
