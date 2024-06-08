// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {OptionBaseLib} from "@src/libraries/OptionBaseLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "@forks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH} from "@forks/IWETH.sol";
import {IMorpho, Id} from "@forks/morpho/IMorpho.sol";
import {IOption} from "@src/interfaces/IOption.sol";

// TODO: check internal external functions
abstract contract BaseOptionHook is BaseHook, IOption {
    using CurrencySettleTake for Currency;

    IERC20 WSTETH = IERC20(OptionBaseLib.WSTETH);
    IWETH WETH = IWETH(OptionBaseLib.WETH);
    IERC20 USDC = IERC20(OptionBaseLib.USDC);
    IERC20 OSQTH = IERC20(OptionBaseLib.OSQTH);

    Id public immutable morphoMarketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    struct OptionInfo {
        uint256 amount;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
    }

    mapping(PoolId => int24) public lastTick;
    uint256 public optionIdCounter = 0;
    mapping(uint256 => OptionInfo) public optionInfo;

    function getTickLast(PoolId poolId) public view returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) internal {
        lastTick[poolId] = _tick;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getCurrentTick(
        PoolId poolId
    ) public view override returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }

    function getOptionPosition(
        PoolKey memory key,
        uint256 optionId
    ) public view override returns (uint128, int24, int24) {
        OptionInfo memory info = optionInfo[optionId];

        Position.Info memory positionInfo = StateLibrary.getPosition(
            poolManager,
            PoolIdLibrary.toId(key),
            address(this),
            info.tickLower,
            info.tickUpper,
            bytes32(ZERO_BYTES)
        );
        return (positionInfo.liquidity, info.tickLower, info.tickUpper);
    }

    function unlockModifyPosition(
        PoolKey calldata key,
        int128 liquidity,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockModifyPosition");

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: bytes32(ZERO_BYTES)
            }),
            ZERO_BYTES
        );

        if (delta.amount0() < 0) {
            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount0() > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }

        if (delta.amount1() > 0) {
            key.currency1.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount1())),
                false
            );
        }
        return ZERO_BYTES;
    }

    //TODO: remove in production
    function logBalances() internal view {
        console.log("> hook balances");
        if (WSTETH.balanceOf(address(this)) > 0)
            console.log("WSTETH", WSTETH.balanceOf(address(this)));
        if (OSQTH.balanceOf(address(this)) > 0)
            console.log("OSQTH ", OSQTH.balanceOf(address(this)));
        if (USDC.balanceOf(address(this)) > 0)
            console.log("USDC  ", USDC.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0)
            console.log("WETH  ", WETH.balanceOf(address(this)));
    }

    // --- Morpho Wrappers ---

    function morphoBorrow(uint256 amount, uint256 shares) internal {
        morpho.borrow(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            address(this)
        );
    }

    function morphoReplay(uint256 amount, uint256 shares) internal {
        morpho.repay(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoWithdrawCollateral(uint256 amount) internal {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            address(this)
        );
    }

    function morphoSupplyCollateral(uint256 amount) internal {
        morpho.supplyCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoSync() internal {
        morpho.accrueInterest(morpho.idToMarketParams(morphoMarketId)); //TODO: is this sync morpho here or not?
    }
}
