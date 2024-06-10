// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IOption {
    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnOptionOwner();

    error NoSwapWillOccur();

    struct OptionInfo {
        uint256 amount;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
        uint256 fee;
    }

    function getOptionInfo(
        uint256 optionId
    ) external view returns (OptionInfo memory);

    function priceScalingFactor() external view returns (uint256);

    function cRatio() external view returns (uint256);

    function weight() external view returns (uint256);

    function getTickLast(PoolId poolId) external view returns (int24);

    function deposit(
        PoolKey calldata key,
        uint256 amount,
        address to
    ) external returns (uint256 optionId);

    function withdraw(
        PoolKey calldata key,
        uint256 optionId,
        address to
    ) external;

    function getCurrentTick(PoolId poolId) external view returns (int24);

    function getOptionPosition(
        PoolKey memory key,
        uint256 optionId
    ) external view returns (uint128, int24, int24);
}
