// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IController} from "@forks/squeeth-monorepo/core/IController.sol";
import {StrategyMath} from "@forks/squeeth-monorepo/core/StrategyMath.sol";
import {IOracle} from "@forks/squeeth-monorepo/IOracle.sol";
// import {Power2Base} from "@forks/squeeth-monorepo/Power2Base.sol";

import "forge-std/console.sol";

library OsqthHelper {
    using StrategyMath for uint256;

    IController constant powerTokenController =
        IController(0x64187ae08781B09368e6253F9E94951243A493D5);

    IOracle constant oracle =
        IOracle(0x65D66c76447ccB45dAf1e8044e918fA786A483A1);

    address constant ethWSqueethPool =
        0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev twap period to use for hedge calculations
    uint32 constant hedgingTwapPeriod = 420 seconds;

    // function calcWsqueethToMint(
    //     uint256 _depositedAmount,
    //     uint256 _strategyDebtAmount,
    //     uint256 _strategyCollateralAmount
    // ) internal view returns (uint256, uint256) {
    //     uint256 wSqueethToMint;
    //     address wPowerPerp = powerTokenController.wPowerPerp();
    //     uint256 feeAdjustment = _calcFeeAdjustment();

    //     if (_strategyDebtAmount == 0 && _strategyCollateralAmount == 0) {
    //         uint256 wSqueethEthPrice = IOracle(oracle).getTwap(
    //             ethWSqueethPool,
    //             wPowerPerp,
    //             WETH,
    //             hedgingTwapPeriod,
    //             true
    //         );
    //         uint256 squeethDelta = wSqueethEthPrice.wmul(2e18);
    //         wSqueethToMint = _depositedAmount.wdiv(
    //             squeethDelta.add(feeAdjustment)
    //         );
    //     } else {
    //         wSqueethToMint = _depositedAmount.wmul(_strategyDebtAmount).wdiv(
    //             _strategyCollateralAmount.add(
    //                 _strategyDebtAmount.wmul(feeAdjustment)
    //             )
    //         );
    //     }

    //     return (wSqueethToMint);
    // }

    // /**
    //  * @notice calculate the fee adjustment factor, which is the amount of ETH owed per 1 wSqueeth minted
    //  * @dev the fee is a based off the index value of squeeth and uses a twap scaled down by the PowerPerp's INDEX_SCALE
    //  * @return the fee adjustment factor
    //  */
    // function _calcFeeAdjustment() internal view returns (uint256) {
    //     uint256 wSqueethEthPrice = Power2Base._getTwap(
    //         oracle,
    //         ethWSqueethPool,
    //         wPowerPerp,
    //         weth,
    //         POWER_PERP_PERIOD,
    //         false
    //     );
    //     uint256 feeRate = IController(powerTokenController).feeRate();
    //     return wSqueethEthPrice.mul(feeRate).div(10000);
    // }
}
