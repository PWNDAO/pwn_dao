// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IVotingContract } from "src/interfaces/IVotingContract.sol";
import { PWN } from "src/PWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";
import { StakedPWN } from "src/StakedPWN.sol";
import { VoteEscrowedPWN } from "src/VoteEscrowedPWN.sol";

import "./Base.t.sol";

contract UseCases is Base_Test {

    uint256 public constant EPOCHS_IN_YEAR = 13;

    PWN public pwnToken;
    PWNEpochClock public epochClock;
    StakedPWN public stPWN;
    VoteEscrowedPWN public vePWN;

    address public dao = makeAddr("dao");
    address public staker = makeAddr("staker");
    address public votingContract = makeAddr("votingContract");

    uint256 public amount = 100 ether;
    uint256[] public lockUpEpochsList;


    /// After setup:
    /// - the contracts are deployed and initialized
    /// - the staker address has 1,000 PWN tokens
    /// - the dao address owns the PWN contract
    /// - the dao is admin of the vePWN contract
    function setUp() external {
        // deploy contracts
        epochClock = new PWNEpochClock(block.timestamp);
        pwnToken = new PWN(dao);
        vePWN = new VoteEscrowedPWN();
        stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock), dao);

        vm.prank(dao);
        stPWN.enableTransfers();

        // fund staker address
        _fundStaker(staker, 1000 ether);
        vm.prank(staker);
        pwnToken.approve(address(vePWN), 1000 ether);

        // label addresses for debugging
        vm.label(address(pwnToken), "PWN Token");
        vm.label(address(epochClock), "PWN Epoch Clock");
        vm.label(address(stPWN), "Staked PWN");
        vm.label(address(vePWN), "Vote Escrowed PWN");
        vm.label(staker, "Staker");
        vm.label(dao, "DAO");

        // setup helper variables
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 1);
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 2);
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 3);
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 4);
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 5);
        lockUpEpochsList.push(EPOCHS_IN_YEAR * 10);
    }


    function _fundStaker(address _staker, uint256 _amount) internal {
        vm.startPrank(dao);
        pwnToken.mint(_amount);
        pwnToken.transfer(_staker, _amount);
        vm.stopPrank();
    }

    function _warpEpochs(uint256 epochs) internal {
        vm.warp(block.timestamp + epochs * epochClock.SECONDS_IN_EPOCH());
    }


    /// Create 10 stakes with the given lockup period one epoch apart
    function _createAllStakes(uint256 lockupEpochs) private {
        for (uint256 i; i < 10; ++i) {
            (, uint256 gasUsed) = _createStake(lockupEpochs);
            _warpEpochs(1);
            console2.log("Create stake (existing %s, lockup %s) gas used:", i, lockupEpochs, gasUsed);
        }
    }

    /// create a stake and return the gas used
    function _createStake(uint256 lockUpEpochs) private returns (uint256 tokenId, uint256 gasUsed) {
        uint256 gasLeft = gasleft();
        vm.prank(staker);
        tokenId = vePWN.createStake(amount, lockUpEpochs);
        gasUsed = gasLeft - gasleft();
    }

    function testUseCase_createStake_1Year() external { _createAllStakes(EPOCHS_IN_YEAR * 1); }
    function testUseCase_createStake_2Year() external { _createAllStakes(EPOCHS_IN_YEAR * 2); }
    function testUseCase_createStake_3Year() external { _createAllStakes(EPOCHS_IN_YEAR * 3); }
    function testUseCase_createStake_4Year() external { _createAllStakes(EPOCHS_IN_YEAR * 4); }
    function testUseCase_createStake_5Year() external { _createAllStakes(EPOCHS_IN_YEAR * 5); }
    function testUseCase_createStake_10Year() external { _createAllStakes(EPOCHS_IN_YEAR * 10); }


    address to = makeAddr("to");
    /// Create 10 stakes with the given lockup period one epoch apart and transfer each one to the `to` address
    function _transferAllStakes(uint256 lockUpEpochs) private {
        uint256 tokenId;
        for (uint256 i; i < 10; ++i) {
            (tokenId, ) = _createStake(lockUpEpochs);
            // mesure
            uint256 gasLeft = gasleft();
            vm.prank(staker);
            stPWN.transferFrom(staker, to, tokenId);
            uint256 gasUsed = gasLeft - gasleft();
            console2.log("Transfer stake (existing %s, lockup %s) gas used:", i + 1, lockUpEpochs, gasUsed);
            // clean
            vm.prank(to);
            stPWN.transferFrom(to, staker, tokenId);
            _warpEpochs(1);
        }
    }

    function testUseCase_transferStake_1Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 1); }
    function testUseCase_transferStake_2Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 2); }
    function testUseCase_transferStake_3Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 3); }
    function testUseCase_transferStake_4Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 4); }
    function testUseCase_transferStake_5Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 5); }
    function testUseCase_transferStake_10Year() external { _transferAllStakes(EPOCHS_IN_YEAR * 10); }


    function _getEpochPower(uint256 numberOfStakes) private {
        for (uint256 i; i < numberOfStakes; ++i) {
            _createStake(5 * EPOCHS_IN_YEAR);
            _warpEpochs(1);
        }

        uint256 gasLeft = gasleft();
        vePWN.stakerPowerAt(staker, 30);
        uint256 gasUsed = gasLeft - gasleft();
        console2.log("Get stakers power (stakes %s) gas used:", numberOfStakes, gasUsed);
    }

    function testUseCase_getEpochPower_1Stake() external { _getEpochPower(1); }
    function testUseCase_getEpochPower_2Stake() external { _getEpochPower(2); }
    function testUseCase_getEpochPower_3Stake() external { _getEpochPower(3); }
    function testUseCase_getEpochPower_4Stake() external { _getEpochPower(4); }
    function testUseCase_getEpochPower_5Stake() external { _getEpochPower(5); }
    function testUseCase_getEpochPower_6Stake() external { _getEpochPower(6); }
    function testUseCase_getEpochPower_7Stake() external { _getEpochPower(7); }
    function testUseCase_getEpochPower_8Stake() external { _getEpochPower(8); }
    function testUseCase_getEpochPower_9Stake() external { _getEpochPower(9); }
    function testUseCase_getEpochPower_10Stake() external { _getEpochPower(10); }

}
