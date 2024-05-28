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
import {PerpMath} from "../src/libraries/PerpMath.sol";

import "forge-std/console.sol";

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

        console.log("> initialPrice SQRT");
        int24 initialTick = PerpMath.getNearestValidTick(
            PerpMath.getTickFromPrice(2000 ether),
            4
        );
        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(initialTick);

        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );
    }

    function test_deposit() public {
        deal(Currency.unwrap(currency1), address(alice.addr), 1 ether);

        vm.startPrank(alice.addr);
        token1.approve(address(hook), type(uint256).max);
        (int24 tickLower, int24 tickUpper) = hook.deposit(key, 1 ether);
        vm.stopPrank();

        Position.Info memory positionInfo = StateLibrary.getPosition(
            manager,
            PoolIdLibrary.toId(key),
            address(hook),
            tickLower,
            tickUpper,
            ""
        );
        assertEq(positionInfo.liquidity, 76354683210186);
        assertEq(token1.balanceOf(alice.addr), 0);
        assertEq(token1.balanceOf(address(hook)), 500000000000004110);
    }
}
