// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import "./math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import "forge-std/console.sol";

library PerpMath {
    using FixedPointMathLib for uint256;

    // function getLiquidityForValue(
    //     uint256 v,
    //     uint256 p,
    //     int24 tickLower,
    //     int24 tickUpper
    // ) internal view returns (int128) {
    //     return
    //         int128(
    //             getLiquidityForValue(
    //                 v.mul(p),
    //                 p,
    //                 getTickFromPriceFormatted(tickLower),
    //                 getTickFromPriceFormatted(tickUpper)
    //             )
    //         );
    // }

    // function getLiquidityForValue(
    //     uint256 v,
    //     uint256 p,
    //     uint256 pH,
    //     uint256 pL
    // ) internal view returns (uint128) {
    //     // console.log("> getLiquidityForValue");
    //     // console.log("> v", v);
    //     // console.log("> p", p);
    //     // console.log("> pH", pH);
    //     // console.log("> pL", pL);
    //     // console.log((p.sqrt() * 2));
    //     // console.log(pL.sqrt());
    //     // console.log(p / (pH.sqrt()));
    //     // console.log(p.sqrt());
    //     // console.log(p);
    //     // console.log(p.sqrt() * 2 - pL.sqrt() - p / (pH.sqrt()));
    //     return
    //         MathHelpersLib.toUint128(
    //             (v * 1e3) / ((p.sqrt()) * 2 - pL.sqrt() - p / (pH.sqrt()))
    //         );
    // }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        return (sqrtPriceX96 * sqrtPriceX96) >> (96 * 2);
    }

    function getTickFromPriceFormatted(
        int24 tick
    ) internal pure returns (uint256) {
        return uint256(1e12).div(getPriceFromTick(tick));
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

    function getTickFromPrice(uint256 price) internal view returns (int24) {
        // console.log("> getTickFromPrice");
        // console.log("> price", price);
        // console.log(uint256(1e30).div(price));
        // console.log(PRBMathUD60x18.ln(uint256(1e30).div(price)));
        // console.log(
        //     PRBMathUD60x18.ln(uint256(1e30).div(price)).div(99995000333297)
        // );
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
