// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolTestBase} from "v4-core/test/PoolTestBase.sol";
import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";

contract HookEnabledSwapRouter is PoolTestBase {
    using CurrencyLibrary for Currency;
    using CurrencySettleTake for Currency;

    error NoSwapOccurred();

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData(
                        msg.sender,
                        testSettings,
                        key,
                        params,
                        hookData
                    )
                )
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0)
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        // console.log("> amount0", uint256(int256(delta.amount0())));
        // console.log("> amount1", uint256(int256(delta.amount1())));

        // Make sure you ve added liquidity to the test pool!
        if (BalanceDelta.unwrap(delta) == 0) revert NoSwapOccurred();

        if (data.params.zeroForOne) {
            // console.log(
            //     "> I want to get from user",
            //     Currency.unwrap(data.key.currency0)
            // );
            // console.log(uint256(int256(-delta.amount0())));
            data.key.currency0.settle(
                manager,
                data.sender,
                uint256(int256(-delta.amount0())),
                data.testSettings.settleUsingBurn
            );
            if (delta.amount1() > 0) {
                // console.log(
                //     "> I want to give to user",
                //     Currency.unwrap(data.key.currency1)
                // );
                // console.log(uint256(int256(delta.amount1())));
                data.key.currency1.take(
                    manager,
                    data.sender,
                    uint256(int256(delta.amount1())),
                    data.testSettings.takeClaims
                );
            }
        } else {
            // console.log(
            //     "> I want to get from user",
            //     Currency.unwrap(data.key.currency1)
            // );
            // console.log(uint256(int256(-delta.amount1())));
            data.key.currency1.settle(
                manager,
                data.sender,
                uint256(int256(-delta.amount1())),
                data.testSettings.settleUsingBurn
            );

            // console.log(
            //     "> I want to give to user",
            //     Currency.unwrap(data.key.currency0)
            // );
            // console.log(uint256(int256(delta.amount0())));
            if (delta.amount0() > 0) {
                data.key.currency0.take(
                    manager,
                    data.sender,
                    uint256(int256(delta.amount0())),
                    data.testSettings.takeClaims
                );
            }
        }

        return abi.encode(delta);
    }
}
