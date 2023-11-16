// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";

abstract contract VoteEscrowedPWNRevenue is VoteEscrowedPWNBase {

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event DaoRevenueShareChanged(uint256 indexed epoch, uint16 oldValue, uint16 newValue);


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
            stakerPower: stakerPower(msg.sender, epoch) * (10000 - daoRevenueShareFor(epoch)) / 10000,
            totalPower: totalPowerAt(epoch)
        });
    }


    /*----------------------------------------------------------*|
    |*  # DAO REVENUE                                           *|
    |*----------------------------------------------------------*/

    /// @notice Claims DAOs share of revenue.
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
            stakerPower: anyStaker ? totalPowerAt(epoch) * daoRevenueShareFor(epoch) / 10000 : 1,
            totalPower: anyStaker ? totalPowerAt(epoch) : 1
        });
    }

    /// @notice Sets a new DAO revenue share.
    /// @dev Can be called only by the owner.
    /// @param share New DAO revenue share with 2 decimals.
    function setDaoRevenueShare(uint16 share) external onlyOwner {
        require(share <= 5000, "vePWN: share must be less than or equal 50%");
        RevenueShareCheckpoint storage checkpoint = daoRevenueShares[daoRevenueShares.length - 1];

        uint16 oldShare = checkpoint.share;
        require(share != oldShare, "vePWN: share already set");

        uint16 initialEpoch = _currentEpoch() + 1;
        if (checkpoint.initialEpoch == initialEpoch) {
            checkpoint.share = share;
        } else {
            _pushDaoRevenueShareCheckpoint(initialEpoch, share);
        }

        emit DaoRevenueShareChanged(initialEpoch, oldShare, share);
    }

    /// @notice Returns DAO revenue share for the current epoch.
    /// @return DAO revenue share with 2 decimals.
    function currentDaoRevenueShare() external view returns (uint256) {
        return daoRevenueShareFor(epochClock.currentEpoch());
    }

    /// @notice Returns DAO revenue share for the given epoch.
    /// @param epoch Epoch to get DAO revenue share for.
    /// @return DAO revenue share with 2 decimals.
    function daoRevenueShareFor(uint256 epoch) public view returns (uint256) {
        uint256 checkpoints = daoRevenueShares.length;
        RevenueShareCheckpoint storage checkpoint;

        while (checkpoints > 0) {
            unchecked { --checkpoints; }
            checkpoint = daoRevenueShares[checkpoints];
            if (checkpoint.initialEpoch <= epoch)
                return uint256(checkpoint.share);
        }

        return 0;
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    // used in `initialize` function
    function _pushDaoRevenueShareCheckpoint(uint16 initialEpoch, uint16 share) internal {
        RevenueShareCheckpoint storage checkpoint = daoRevenueShares.push();
        checkpoint.initialEpoch = initialEpoch;
        checkpoint.share = share;
    }

}
