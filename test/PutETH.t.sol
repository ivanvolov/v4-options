// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {Morpho} from "morpho-blue/Morpho.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {AggregatorV3Interface} from "morpho-blue-oracles/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol";

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

import {HookEnabledSwapRouter} from "./libraries/HookEnabledSwapRouter.sol";
import {PutETH} from "../src/PutETH.sol";
import {PerpMath} from "../src/libraries/PerpMath.sol";

import "forge-std/console.sol";

contract PutETHTest is Test, Deployers {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using TestAccountLib for TestAccount;

    PutETH hook;

    TestAccount alice;
    TestAccount swapper;
    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    TestERC20 WSTETH;
    TestERC20 USDC;
    TestERC20 OSQTH;
    TestERC20 WETH;

    function setUp() public {
        deployFreshManagerAndRouters();

        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        WSTETH = TestERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        vm.label(address(WSTETH), "WSTETH");
        USDC = TestERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.label(address(USDC), "USDC");
        OSQTH = TestERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);
        vm.label(address(OSQTH), "OSQTH");
        WETH = TestERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vm.label(address(WETH), "WETH");

        create_and_seed_morpho_market();
        init_hook();

        vm.startPrank(alice.addr);
        WSTETH.approve(address(hook), type(uint256).max);
        USDC.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        WSTETH.approve(address(router), type(uint256).max);
        USDC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_osqth_operations() public {}

    function test_deposit() public {
        uint256 amountToDeposit = 10000 * 1e6;
        deal(address(USDC), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        uint256 optionId = hook.deposit(key, amountToDeposit, alice.addr);
        (uint128 liquidity, , ) = hook.getOptionPosition(key, optionId);
        assertEq(liquidity, 254863304324955);
        assertEq(WSTETH.balanceOf(alice.addr), 0);
        assertEq(USDC.balanceOf(alice.addr), 0);
        assertEq(WSTETH.balanceOf(address(hook)), 0);
        assertEq(USDC.balanceOf(address(hook)), 0);
        MorphoPosition memory p = morpho.position(marketId, address(hook));
        assertEq(p.borrowShares, 0);
        assertApproxEqAbs(p.collateral, amountToDeposit / 2, 10000);
    }

    function test_deposit_withdraw_not_option_owner_revert() public {
        test_deposit();

        vm.expectRevert(PutETH.NotAnOptionOwner.selector);
        hook.withdraw(key, 0, alice.addr);
    }

    function test_swap_price_up_revert() public {
        test_deposit();

        deal(address(USDC), address(swapper.addr), 10000 * 1e6);
        vm.prank(swapper.addr);
        vm.expectRevert(PutETH.NoSwapWillOccur.selector);
        router.swap(
            key,
            IPoolManager.SwapParams(
                false, // USDC -> WSTETH
                int256(1 ether),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function test_swap_price_down() public {
        test_deposit();

        deal(address(WSTETH), address(swapper.addr), 1362396734796578497);
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                true, // WSTETH -> USDC
                4500 * 1e6,
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
        assertApproxEqAbs(WSTETH.balanceOf(swapper.addr), 0, 10);
        assertApproxEqAbs(USDC.balanceOf(swapper.addr), 4500 * 1e6, 10);

        // assertApproxEqAbs(USDC.balanceOf(address(hook)), 0, 10);
        // assertApproxEqAbs(
        //     OSQTH.balanceOf(address(hook)),
        //     16851686274526807531,
        //     10
        // );

        // MorphoPosition memory p = morpho.position(marketId, address(hook));
        // assertEq(p.borrowShares, 4513632092000000);
        // assertApproxEqAbs(p.collateral, 50 ether, 10000);
    }

    // -- Helpers --

    HookEnabledSwapRouter router;

    Id marketId;

    bytes32 targetMarketId =
        0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc;

    IMorpho morpho;

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("PutETH.sol", abi.encode(manager, marketId), hookAddress);
        hook = PutETH(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);

        (key, ) = initPool(
            Currency.wrap(address(WSTETH)),
            Currency.wrap(address(USDC)),
            hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );
    }

    function create_and_seed_morpho_market() internal {
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");

        morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(targetMarketId)
        );
        marketParams.loanToken = address(WSTETH);
        marketParams.collateralToken = address(USDC);
        marketParams.lltv = 915000000000000000;

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);

        marketId = MarketParamsLib.id(marketParams);
        MarketParams memory marketParamsOut = morpho.idToMarketParams(marketId);

        assertEq(marketParamsOut.loanToken, marketParams.loanToken);
        assertEq(marketParamsOut.collateralToken, marketParams.collateralToken);
        assertEq(marketParamsOut.oracle, marketParams.oracle);
        assertEq(marketParamsOut.irm, marketParams.irm);
        assertEq(marketParamsOut.lltv, marketParams.lltv);

        // uint256 collateralPrice = IOracle(marketParams.oracle).price();
        // console.log("> collateralPrice", collateralPrice);

        // ** Deposit liquidity
        vm.startPrank(morphoLpProvider.addr);
        deal(address(WSTETH), morphoLpProvider.addr, 100 * 1e18);

        WSTETH.approve(address(morpho), type(uint256).max);
        (, uint256 shares) = morpho.supply(
            morpho.idToMarketParams(marketId),
            100 * 1e18,
            0,
            morphoLpProvider.addr,
            ""
        );

        MorphoPosition memory p = morpho.position(
            marketId,
            morphoLpProvider.addr
        );
        assertEq(p.supplyShares, shares);
        assertEq(p.borrowShares, 0);
        assertEq(p.collateral, 0);
        assertEq(WETH.balanceOf(morphoLpProvider.addr), 0);
        vm.stopPrank();
    }
}
