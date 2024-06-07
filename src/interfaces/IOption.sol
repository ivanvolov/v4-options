// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IOption {
    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnOptionOwner();

    error NoSwapWillOccur();

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
