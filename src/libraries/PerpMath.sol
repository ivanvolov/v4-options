// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import "./math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import "forge-std/console.sol";

library PerpMath {
    using FixedPointMathLib for uint256;

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        return uint256(1e12).div((sqrtPriceX96 * sqrtPriceX96) >> (96 * 2));
    }

    function getNearestValidTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 flooredTick = (tick / tickSpacing) * tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) {
            flooredTick -= tickSpacing;
        }
        return flooredTick;
    }

    function getTickLower(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return
            MathHelpersLib.toInt24(
                int256(
                    PRBMathUD60x18.ln(uint256(1e30).div(price)).div(
                        99995000333297 * 1e18
                    )
                )
            );
    }
}
