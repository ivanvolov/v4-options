// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BaseHook} from "./forks/BaseHook.sol";
import "forge-std/console.sol";

contract CallETH is BaseHook {
    using CurrencySettleTake for Currency;
    using PoolIdLibrary for PoolKey;

    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    bytes internal constant ZERO_BYTES = bytes("");

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

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
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        console.log("> afterInitialize");
        // console.log(Currency.unwrap(key.currency0));
        // poolManager.sync(key.currency0);
        // poolManager.sync(key.currency1);

        return CallETH.afterInitialize.selector;
    }

    function getTick(PoolKey calldata key) public view returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(
            poolManager,
            key.toId()
        );
        return currentTick;
    }

    // Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        console.log("> beforeAddLiquidity");
        console.log("> sender");
        console.log(sender);
        console.log("> msg.sender");
        console.log(msg.sender);
        console.log("> address(this)");
        console.log(address(this));
        // revert AddLiquidityThroughHook();
        return CallETH.beforeAddLiquidity.selector;
    }

    function deposit(PoolKey calldata key, uint256 amount) external {
        if (amount == 0) revert ZeroLiquidity();
        IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount
        ); //TODO: now ETH is first currency, but...

        poolManager.unlock(
            abi.encodeCall(
                this.unlockDepositPlace,
                (key, amount / 2, msg.sender)
            )
        );

        //TODO: do Aave deposit here
    }

    function unlockDepositPlace(
        PoolKey calldata key,
        uint256 amount,
        address sender
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockDepositPlace");

        int24 currentTick = getTick(key);
        poolManager.sync(key.currency0);
        poolManager.sync(key.currency1);
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: currentTick,
                tickUpper: currentTick + key.tickSpacing * 3,
                liquidityDelta: int256(amount), //TODO: use PerpMath.getLiquidityFromValue here
                salt: ""
            }),
            ZERO_BYTES
        );

        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        if (delta.amount0() < 0) {
            if (delta.amount1() != 0) revert InRange();

            IERC20Minimal(Currency.unwrap(key.currency0)).transfer(
                address(poolManager),
                uint256(uint128(-delta.amount0()))
            );
            poolManager.settle(key.currency0);
        } else {
            if (delta.amount0() != 0) revert InRange();

            IERC20Minimal(Currency.unwrap(key.currency1)).transfer(
                address(poolManager),
                uint256(uint128(-delta.amount1()))
            );
            poolManager.settle(key.currency1);
        }
    }
}
