// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;
// solhint-disable quotes

import { Base64 } from "openzeppelin-contracts/contracts/utils/Base64.sol";
import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";

import { IStakedPWNSupplyManager } from "src/interfaces/IStakedPWNSupplyManager.sol";
import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";

/// @title VoteEscrowedPWNStakeMetadata.
/// @notice Contract for generating metadata for staked PWN NFTs.
abstract contract VoteEscrowedPWNStakeMetadata is VoteEscrowedPWNBase, IStakedPWNSupplyManager {
    using Strings for address;
    using Strings for uint256;

    struct MetadataAttributes {
        StakedAmount stakedAmount;
        uint256 stakedAmountFormatted;
        uint256 currentPower;
        uint256 initialTimestamp;
        uint256 lockUpDuration;
        uint256 unlockTimestamp;
        string multiplier;
        address stakeOwner;
        PowerChange[] powerChanges;
    }

    struct PowerChange {
        uint256 timestamp;
        uint256 power;
        string multiplier;
    }

    struct StakedAmount {
        uint256 amount;
        uint256 decimals;
        address pwnTokenAddress;
    }

    /*----------------------------------------------------------*|
    |*  # STAKED PWN METADATA                                   *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IStakedPWNSupplyManager
    function stakeMetadata(uint256 stakeId) external view returns (string memory) {
        string memory json = string.concat(
            '{"name":', _makeName(stakeId), ',',
            '"external_url":', _makeExternalUrl(stakeId), ',',
            '"image":', _makeApiUriWith(stakeId, "thumbnail"), ',',
            '"animation_url":', _makeApiUriWith(stakeId, "animation"), ',',
            '"attributes":', _makeAttributes(stakeId), ',',
            '"description":', _makeDescription(), '}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    function _makeName(uint256 stakeId) internal pure returns (string memory) {
        return string.concat('"PWN DAO Stake #', stakeId.toString(), '"');
    }

    function _makeExternalUrl(uint256 stakeId) internal view returns (string memory) {
        return string.concat(
            '"https://app.pwn.xyz/#/asset/', block.chainid.toString(), '/',
            address(this).toHexString(), '/',
            stakeId.toString(), '"'
        );
    }

    function _makeApiUriWith(uint256 stakeId, string memory path) internal view returns (string memory) {
        return string.concat(
            '"https://api-dao.pwn.xyz/stpwn/', block.chainid.toString(), '/',
            address(this).toHexString(), '/',
            stakeId.toString(), '/', path, '"'
        );
    }

    function _makeDescription() internal pure returns (string memory) {
        // solhint-disable-next-line max-line-length
        return '"This NFT is a representation of a PWN DAO stake. Stake ownership grants its owner power in the PWN DAO. The power is determined by the amount of PWN tokens staked and the remaining lockup period. The power decreases over time until the lockup is over."';
    }

    function _makeAttributes(uint256 stakeId) internal view returns (string memory) {
        MetadataAttributes memory attributes = _computeAttributes(stakeId);
        // solhint-disable max-line-length
        return string.concat(
            '[{"trait_type":"Staked $PWN formatted","display_type":"number","value":', attributes.stakedAmountFormatted.toString(), '},',
            '{"trait_type":"Staked $PWN","display_type":"object","value":', _makeStakedAmount(attributes.stakedAmount), '},',
            '{"trait_type":"Power","display_type":"number","value":', attributes.currentPower.toString(), '},',
            '{"trait_type":"Stake Start","display_type":"date","value":', attributes.initialTimestamp.toString(), '},',
            '{"trait_type":"Lock Up Duration","display_type":"number","value":', attributes.lockUpDuration.toString(), '},',
            '{"trait_type":"Unlock Date","display_type":"date","value":', attributes.unlockTimestamp.toString(), '},',
            '{"trait_type":"Current Multiplier","display_type":"string","value":', attributes.multiplier ,'},',
            '{"trait_type":"Power Changes","display_type":"object","value":', _makePowerChanges(attributes.powerChanges) ,'},',
            '{"trait_type":"Owner","display_type":"string","value":"', attributes.stakeOwner.toHexString(), '"}]'
        );
        // solhint-enable max-line-length
    }

    function _computeAttributes(uint256 stakeId) internal view returns (MetadataAttributes memory attributes) {
        attributes.stakeOwner = stakedPWN.ownerOf(stakeId);

        Stake memory stake = stakes[stakeId];
        int104 amount104 = int104(stake.amount);
        attributes.stakedAmount.amount = uint256(uint104(amount104));
        attributes.stakedAmount.decimals = 18;
        attributes.stakedAmount.pwnTokenAddress = address(pwnToken);
        attributes.stakedAmountFormatted = attributes.stakedAmount.amount / 1e18;
        attributes.lockUpDuration = uint256(stake.lockUpEpochs) * 28;

        // power changes
        uint256 count = 7;
        if (stake.lockUpEpochs <= 65) {
            count = stake.lockUpEpochs / EPOCHS_IN_YEAR;
            count += stake.lockUpEpochs % EPOCHS_IN_YEAR > 0 ? 2 : 1;
        }
        attributes.powerChanges = new PowerChange[](count);
        uint16 epoch = stake.initialEpoch;
        uint8 remainingLockup = stake.lockUpEpochs;
        uint256 currentPowerChangeIndex; // find current power change index
        uint256 secondsInEpoch = epochClock.SECONDS_IN_EPOCH();
        uint256 initialEpochTimestamp = epochClock.INITIAL_EPOCH_TIMESTAMP();
        for (uint256 i; i < count; ++i) {
            bool lastLoop = i == count - 1;
            attributes.powerChanges[i].timestamp = initialEpochTimestamp + (epoch - 1) * secondsInEpoch;
            attributes.powerChanges[i].power = lastLoop ? 0 : uint256(int256(_power(amount104, remainingLockup)));
            attributes.powerChanges[i].multiplier = lastLoop ? '"0x"' : _makeMultiplier(remainingLockup);

            if (attributes.powerChanges[i].timestamp <= block.timestamp) {
                currentPowerChangeIndex = i;
            }
            if (!lastLoop) {
                uint8 toNextEpoch = _epochsToNextPowerChange(remainingLockup);
                epoch += toNextEpoch;
                remainingLockup -= toNextEpoch;
            }
        }

        attributes.initialTimestamp = attributes.powerChanges[0].timestamp;
        attributes.unlockTimestamp = attributes.powerChanges[count - 1].timestamp;

        // stakes before initial epoch have 0 power and multiplier
        if (block.timestamp < attributes.powerChanges[0].timestamp) {
            attributes.currentPower = 0;
            attributes.multiplier = '"0x"';
        } else {
            attributes.currentPower = attributes.powerChanges[currentPowerChangeIndex].power;
            attributes.multiplier = attributes.powerChanges[currentPowerChangeIndex].multiplier;
        }
    }

    function _makeMultiplier(uint8 lockUpEpochs) internal pure returns (string memory) {
        if (lockUpEpochs <= EPOCHS_IN_YEAR) return '"1.0x"';
        else if (lockUpEpochs <= EPOCHS_IN_YEAR * 2) return '"1.15x"';
        else if (lockUpEpochs <= EPOCHS_IN_YEAR * 3) return '"1.3x"';
        else if (lockUpEpochs <= EPOCHS_IN_YEAR * 4) return '"1.5x"';
        else if (lockUpEpochs <= EPOCHS_IN_YEAR * 5) return '"1.75x"';
        else return '"3.5x"';
    }

    function _makeStakedAmount(StakedAmount memory stakedAmount) internal pure returns (string memory) {
        return string.concat(
            '{"amount":', stakedAmount.amount.toString(), ',',
            '"decimals":', stakedAmount.decimals.toString(), ',',
            '"pwn_token_address":"', stakedAmount.pwnTokenAddress.toHexString(), '"}'
        );
    }

    function _makePowerChanges(PowerChange[] memory powerChanges) internal pure returns (string memory pChs) {
        pChs = "[";
        for (uint256 i; i < powerChanges.length; ++i) {
            if (i > 0) {
                pChs = string.concat(pChs, ',');
            }
            pChs = string.concat(
                pChs,
                '{"start_date":', powerChanges[i].timestamp.toString(),
                ',"power":', powerChanges[i].power.toString(),
                ',"multiplier":', powerChanges[i].multiplier, '}'
            );
        }
        pChs = string.concat(pChs, ']');
    }

}
