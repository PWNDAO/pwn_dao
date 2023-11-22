// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNEpochClock } from "./PWNEpochClock.sol";

interface IPWNHub {
    function hasTag(address _address, bytes32 tag) external view returns (bool);
}


contract PWNFeeCollector {
    using SafeERC20 for IERC20;

    // # INVARIANTS
    // - sum of `claimedFees` <= actual balance before claim

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public constant FEE_DISTRIBUTOR_TAG = keccak256("PWN_FEE_DISTRIBUTOR");

    PWNEpochClock public immutable epochClock;
    IPWNHub public immutable hub;
    address public immutable claimController;

    // claimed fees per address per epoch per asset address
    mapping(address staker => mapping(uint256 epoch => mapping(address asset => bool claimed))) public claimedFees;
    // collected fees per epoch per asset address
    mapping(uint256 epoch => mapping(address asset => uint256 amount)) public collectedFees;

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event FeeCollected(uint256 indexed epoch, address indexed asset, uint256 amount);
    event FeeClaimed(uint256 indexed epoch, address indexed caller, address indexed asset, uint256 amount);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyFeeDistributor() {
        require(hub.hasTag(msg.sender, FEE_DISTRIBUTOR_TAG), "PWNFeeCollector: caller is not fee distributor");
        _;
    }

    modifier onlyClaimController() {
        require(msg.sender == claimController, "PWNFeeCollector: caller is not claim controller");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _claimController, address _epochClock, address _hub) {
        claimController = _claimController;
        epochClock = PWNEpochClock(_epochClock);
        hub = IPWNHub(_hub);
    }


    /*----------------------------------------------------------*|
    |*  # COLLECT FEES HOOK                                     *|
    |*----------------------------------------------------------*/

    /// @dev Fee distributor should call this function AFTER transferring fees to this contract.
    /// Use address zero for native assets (ETH, MATIC, ...).
    function collectFeesHook(address asset, uint256 amount) external onlyFeeDistributor {
        uint256 epoch = epochClock.currentEpoch();
        collectedFees[epoch][asset] += amount;

        emit FeeCollected(epoch, asset, amount);
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM FEES                                            *|
    |*----------------------------------------------------------*/

    function claimFees(
        address staker,
        uint256 epoch,
        address[] calldata assets,
        uint256 stakerPower,
        uint256 totalPower
    ) external onlyClaimController {
        // claimed epoch must be finished
        require(epoch < epochClock.currentEpoch(), "PWNFeeCollector: epoch not finished");

        address asset;
        uint256 claimableAmount;
        uint256 assetsLength = assets.length;
        for (uint256 i; i < assetsLength;) {
            asset = assets[i];

            // asset is not claimed by the caller yet
            require(claimedFees[staker][epoch][asset] == false, "PWNFeeCollector: asset already claimed");
            claimedFees[staker][epoch][asset] = true; // protects against reentrancy and duplicite assets

            claimableAmount = Math.mulDiv(collectedFees[epoch][asset], stakerPower, totalPower);

            if (asset == address(0)) {
                (bool success, ) = staker.call{value: claimableAmount}("");
                require(success, "PWNFeeCollector: ETH transfer failed");
            } else {
                IERC20(asset).safeTransfer(staker, claimableAmount);
            }

            emit FeeClaimed(epoch, staker, asset, claimableAmount);

            unchecked { ++i; }
        }
    }

}
