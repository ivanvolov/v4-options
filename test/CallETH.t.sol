// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Id, Position as MorphoPosition} from "morpho-blue/interfaces/IMorpho.sol";

import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {MorphoChainlinkOracleV2} from "morpho-blue/oracles/MorphoChainlinkOracleV2.sol";

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
    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    address constant MORPHO_MAINNET =
        0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    IMorpho morpho;

    // The two currencies (tokens) from the pool
    TestERC20 token0;
    TestERC20 token1;

    TestERC20 weth;
    TestERC20 usdc;

    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        morpho = IMorpho(MORPHO_MAINNET);

        token0 = TestERC20(Currency.unwrap(currency0));
        token1 = TestERC20(Currency.unwrap(currency1));
        weth = TestERC20(WETH_ADDRESS);
        usdc = TestERC20(USDC_ADDRESS);

        alice = TestAccountLib.createTestAccount("alice");
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");

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

    function test_deloy_morpho_oracle() public {
        0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766
    }

    function test_morpho_blue_market() public {
        // Create market
        MarketParams memory marketParams = MarketParams({
            loanToken: address(weth),
            collateralToken: address(usdc),
            oracle: 0x2a01EB9496094dA03c4E364Def50f5aD1280AD72,
            irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            lltv: 945000000000000000
        });
        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        console.log("> collateralPrice", collateralPrice);

        // ** Deposit
        deal(address(weth), morphoLpProvider.addr, 1 ether);

        vm.startPrank(morphoLpProvider.addr);
        weth.approve(MORPHO_MAINNET, type(uint256).max);
        (uint256 assets, uint256 shares) = morpho.supply(
            marketParams,
            1 ether,
            0,
            morphoLpProvider.addr,
            ""
        );
        vm.stopPrank();

        MorphoPosition memory p = morpho.position(
            MarketParamsLib.id(marketParams),
            morphoLpProvider.addr
        );
        assertEq(p.supplyShares, shares);
        assertEq(p.borrowShares, 0);
        assertEq(p.collateral, 0);
        assertEq(weth.balanceOf(morphoLpProvider.addr), 0);

        // ** Supply collateral
        uint256 collateralAmount = 2000 * 1e6;
        deal(address(usdc), address(alice.addr), collateralAmount);

        vm.startPrank(alice.addr);
        console.log(usdc.balanceOf(alice.addr));
        usdc.approve(MORPHO_MAINNET, type(uint256).max);
        morpho.supplyCollateral(marketParams, collateralAmount, alice.addr, "");
        vm.stopPrank();

        p = morpho.position(MarketParamsLib.id(marketParams), alice.addr);
        assertEq(p.supplyShares, 0);
        assertEq(p.borrowShares, 0);
        assertEq(p.collateral, collateralAmount);
        assertEq(usdc.balanceOf(alice.addr), 0);

        // ** Borrow
        uint256 borrowAmount = 10;
        vm.prank(alice.addr);
        (assets, shares) = morpho.borrow(
            marketParams,
            borrowAmount,
            0,
            alice.addr,
            alice.addr
        );

        p = morpho.position(MarketParamsLib.id(marketParams), alice.addr);
        assertEq(p.supplyShares, 0);
        assertEq(p.borrowShares, shares);
        assertEq(weth.balanceOf(alice.addr), assets);
        assertEq(p.collateral, collateralAmount);
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
