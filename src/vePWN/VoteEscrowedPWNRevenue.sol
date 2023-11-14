// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";


contract VoteEscrowedPWNRevenue is VoteEscrowedPWNBase {

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event DaoRevenuePortionChanged(uint256 indexed epoch, uint16 oldValue, uint16 newValue);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier checkClaimableEpoch(uint256 epoch) {
        require(epoch < epochClock.currentEpoch(), "vePWN: epoch not finished");
        require(lastCalculatedTotalPowerEpoch >= epoch, "vePWN: need to have calculated total power for the epoch");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # STAKER REVENUE                                        *|
    |*----------------------------------------------------------*/

    /// @notice Claims revenue for a caller.
    /// @dev Can be called only after the epoch has ended.
    /// @dev Can be called only total power was calculated for the epoch.
    /// @param epoch Epoch to claim revenue for.
    /// @param assets Revenue assets to claim.
    function claimRevenue(uint256 epoch, address[] calldata assets) external checkClaimableEpoch(epoch) {
        require(totalPowerAt(epoch) > 0, "vePWN: no stakers");

        feeCollector.claimFees({
            staker: msg.sender,
            epoch: epoch,
            assets: assets,
            stakerPower: stakerPower(msg.sender, epoch) * (10000 - daoRevenuePortionFor(epoch)) / 10000,
            totalPower: totalPowerAt(epoch)
        });
    }


    /*----------------------------------------------------------*|
    |*  # DAO REVENUE                                           *|
    |*----------------------------------------------------------*/

    /// @notice Claims DAO portion of revenue.
    /// @dev Can be called only by the owner.
    /// @dev Can be called only after the epoch has ended.
    /// @dev Can be called only after total power was calculated for the epoch.
    /// @param epoch Epoch to claim revenue for.
    /// @param assets Revenue assets to claim.
    function claimDaoRevenue(uint256 epoch, address[] calldata assets) external onlyOwner checkClaimableEpoch(epoch) {
        bool anyStaker = totalPowerAt(epoch) > 0;

        feeCollector.claimFees({
            staker: msg.sender,
            epoch: epoch,
            assets: assets,
            stakerPower: anyStaker ? totalPowerAt(epoch) * daoRevenuePortionFor(epoch) / 10000 : 1,
            totalPower: anyStaker ? totalPowerAt(epoch) : 1
        });
    }

    /// @notice Sets a new DAO revenue portion.
    /// @dev Can be called only by the owner.
    /// @param portion New DAO revenue portion with 2 decimals.
    function setDaoRevenuePortion(uint16 portion) external onlyOwner {
        require(portion <= 5000, "vePWN: portion must be less than or equal 50%");
        PortionCheckpoint storage checkpoint = daoRevenuePortion[daoRevenuePortion.length - 1];

        uint16 oldPortion = checkpoint.portion;
        uint16 initialEpoch = _currentEpoch() + 1;

        if (checkpoint.initialEpoch == initialEpoch)
            checkpoint.portion = portion;
        else
            _pushDaoRevenuePortionCheckpoint(initialEpoch, portion);

        emit DaoRevenuePortionChanged(initialEpoch, oldPortion, portion);
    }

    /// @notice Returns DAO revenue portion for the current epoch.
    /// @return DAO revenue portion with 2 decimals.
    function currentDaoRevenuePortion() external view returns (uint256) {
        return daoRevenuePortionFor(epochClock.currentEpoch());
    }

    /// @notice Returns DAO revenue portion for the given epoch.
    /// @param epoch Epoch to get DAO revenue portion for.
    /// @return DAO revenue portion with 2 decimals.
    function daoRevenuePortionFor(uint256 epoch) public view returns (uint256) {
        uint256 checkpoints = daoRevenuePortion.length;
        PortionCheckpoint storage checkpoint;

        while (checkpoints > 0) {
            unchecked { --checkpoints; }
            checkpoint = daoRevenuePortion[checkpoints];
            if (checkpoint.initialEpoch <= epoch)
                return uint256(checkpoint.portion);
        }

        return 0;
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    // used in `initialize` function
    function _pushDaoRevenuePortionCheckpoint(uint16 initialEpoch, uint16 portion) internal {
        PortionCheckpoint storage checkpoint = daoRevenuePortion.push();
        checkpoint.initialEpoch = initialEpoch;
        checkpoint.portion = portion;
    }

}
