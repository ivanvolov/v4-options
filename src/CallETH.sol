// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "morpho-blue/interfaces/IMorpho.sol";

import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {BaseHook} from "./forks/BaseHook.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import "forge-std/console.sol";

contract CallETH is BaseHook {
    using CurrencySettleTake for Currency;
    using PoolIdLibrary for PoolKey;

    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    bytes internal constant ZERO_BYTES = bytes("");

    Id public immutable marketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    mapping(PoolId => int24) public lastTick;

    function getTickLast(PoolId poolId) public view returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) private {
        lastTick[poolId] = _tick;
    }

    constructor(IPoolManager poolManager, Id _marketId) BaseHook(poolManager) {
        marketId = _marketId;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log("> afterInitialize");
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(
            address(morpho),
            type(uint256).max
        );
        setTickLast(key.toId(), tick);

        return CallETH.afterInitialize.selector;
    }

    function getCurrentTick(PoolId poolId) public view returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }

    // Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount
    ) external returns (int24 tickLower, int24 tickUpper) {
        console.log("> deposit");
        if (amount == 0) revert ZeroLiquidity();
        IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        tickLower = getCurrentTick(key.toId());
        // console.log("Price from tick %s", PerpMath.getPriceFromTick(tickLower));
        tickUpper = PerpMath.tickRoundDown(
            PerpMath.getTickFromPrice(PerpMath.getPriceFromTick(tickLower) * 2),
            key.tickSpacing
        );
        // console.logInt(tickUpper);
        // tickUpper = -185296;
        console.log("> Ticks, lower/upper");
        console.logInt(tickLower);
        console.logInt(tickUpper);

        poolManager.unlock(
            abi.encodeCall(
                this.unlockDepositPlace,
                (key, amount / 2, tickLower, tickUpper)
            )
        );

        morpho.supplyCollateral(
            morpho.idToMarketParams(marketId),
            IERC20Minimal(Currency.unwrap(key.currency0)).balanceOf(
                address(this)
            ),
            address(this),
            ""
        );
    }

    function unlockDepositPlace(
        PoolKey calldata key,
        uint256 amount,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockDepositPlace");
        // console.log(amount);
        // console.logInt(tickLower);
        // console.logInt(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtPriceAtTick(tickUpper),
            TickMath.getSqrtPriceAtTick(tickLower),
            amount
        );
        // console.log("liquidity %s", uint256(liquidity));

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(liquidity),
                salt: ""
            }),
            ZERO_BYTES
        );

        // console.log("> delta");
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());

        if (delta.amount0() < 0) {
            if (delta.amount1() != 0) revert InRange();

            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            if (delta.amount0() != 0) revert InRange();

            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }
        return bytes("");
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta deltas,
        bytes calldata
    ) external virtual override returns (bytes4, int128) {
        console.log("> afterSwap");

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            console.log(">> price go brrrrrrr!");
            console.logInt(deltas.amount0());
            console.logInt(deltas.amount1());

            morpho.borrow(
                morpho.idToMarketParams(marketId),
                uint256(int256(-deltas.amount1())),
                0,
                address(this),
                address(this)
            );
        }

        // (int24 tickLower, int24 lower, int24 upper) = _getCrossedTicks(
        //     key.toId(),
        //     key.tickSpacing
        // );
        // console.logInt(tickLower);
        // console.logInt(lower);
        // console.logInt(upper);
        // // if (lower > upper) return (LimitOrder.afterSwap.selector, 0);

        setTickLast(key.toId(), tick);
        return (CallETH.afterSwap.selector, 0);
    }
}
