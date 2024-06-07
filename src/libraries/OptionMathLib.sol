// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import "./math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import "forge-std/console.sol";

library OptionMathLib {
    using FixedPointMathLib for uint256;

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        return (sqrtPriceX96.div(2 ** 96)).mul(sqrtPriceX96.div(2 ** 96));
    }

    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return
            MathHelpersLib.toInt24(
                (
                    (int256(PRBMathUD60x18.ln(price * 1e18)) -
                        int256(41446531673892820000))
                ) / 99995000333297
            );
    }

    function tickRoundDown(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function getAssetsBuyShares(
        uint256 borrowShares,
        uint256 totalBorrowShares,
        uint256 totalBorrowAssets
    ) internal pure returns (uint256) {
        return
            totalBorrowAssets == 0
                ? 0
                : borrowShares.mul(totalBorrowAssets).div(totalBorrowShares);
    }
}
