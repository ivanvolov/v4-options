// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TestAccount, TestAccountLib} from "./libraries/TestAccountLib.t.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";

import {CallETH} from "../src/CallETH.sol";

contract CallETHTest is Test, Deployers {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using TestAccountLib for TestAccount;

    CallETH hook;

    TestAccount alice;

    // The two currencies (tokens) from the pool
    TestERC20 token0;
    TestERC20 token1;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        token0 = TestERC20(Currency.unwrap(currency0));
        token1 = TestERC20(Currency.unwrap(currency1));

        alice = TestAccountLib.createTestAccount("alice");

        address hookAddress = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("CallETH.sol", abi.encode(manager), hookAddress);
        hook = CallETH(hookAddress);

        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            200, //TODO: set here zero fees somehow?
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        // // Approve our hook address to spend these tokens as well
        // IERC20Minimal(Currency.unwrap(currency0)).approve(
        //     address(hook),
        //     type(uint256).max
        // );
        // IERC20Minimal(Currency.unwrap(currency1)).approve(
        //     address(hook),
        //     type(uint256).max
        // );

        // // So let's only have our own liquidity
        // // Some liquidity from -60 to +60 tick range
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: -60,
        //         tickUpper: 60,
        //         liquidityDelta: 10 ether,
        //         salt: ""
        //     }),
        //     ZERO_BYTES
        // );
        // // some liquidity for full range
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: TickMath.minUsableTick(60),
        //         tickUpper: TickMath.maxUsableTick(60),
        //         liquidityDelta: 10 ether,
        //         salt: ""
        //     }),
        //     ZERO_BYTES
        // );
    }

    function test_deposit() public {
        deal(Currency.unwrap(currency0), address(alice.addr), 1 ether);

        vm.startPrank(alice.addr);
        token0.approve(address(hook), type(uint256).max);
        hook.deposit(key, 1 ether);
        vm.stopPrank();

        int24 currentTick = hook.getTick(key);

        Position.Info memory positionInfo = StateLibrary.getPosition(
            manager,
            PoolIdLibrary.toId(key),
            address(hook),
            currentTick,
            currentTick + key.tickSpacing * 3,
            ""
        );
        assertEq(positionInfo.liquidity, 1 ether);
    }
}
