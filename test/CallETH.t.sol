// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Id, Position as MorphoPosition} from "morpho-blue/interfaces/IMorpho.sol";

import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {IMorphoChainlinkOracleV2Factory} from "morpho-blue-oracles/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2Factory.sol";
import {MorphoChainlinkOracleV2} from "morpho-blue-oracles/morpho-chainlink/MorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "morpho-blue-oracles/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol";
import {IERC4626} from "morpho-blue-oracles/morpho-chainlink/libraries/VaultLib.sol";

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

    TestERC20 token0;
    TestERC20 token1;

    TestERC20 wstETH;
    TestERC20 usdc;

    function setUp() public {
        deployFreshManagerAndRouters();

        alice = TestAccountLib.createTestAccount("alice");

        init_hook();
        init_morpho_oracle();
        create_and_seed_morpho_market();
    }

    function test_morpho_blue_market() public {
        // // ** Deposit
        // deal(address(wstETH), morphoLpProvider.addr, 1 ether);

        // vm.startPrank(morphoLpProvider.addr);
        // wstETH.approve(address(morpho), type(uint256).max);
        // (uint256 assets, uint256 shares) = morpho.supply(
        //     marketParams,
        //     1 ether,
        //     0,
        //     morphoLpProvider.addr,
        //     ""
        // );

        // MorphoPosition memory p = morpho.position(
        //     MarketParamsLib.id(marketParams),
        //     morphoLpProvider.addr
        // );
        // assertEq(p.supplyShares, shares);
        // assertEq(p.borrowShares, 0);
        // assertEq(p.collateral, 0);
        // assertEq(wstETH.balanceOf(morphoLpProvider.addr), 0);
        // vm.stopPrank();

        // ** Supply collateral
        uint256 collateralAmount = 4000 * 1e6;
        deal(address(usdc), address(alice.addr), collateralAmount);

        vm.startPrank(alice.addr);
        // console.log(usdc.balanceOf(alice.addr));
        usdc.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, collateralAmount, alice.addr, "");

        p = morpho.position(MarketParamsLib.id(marketParams), alice.addr);
        assertEq(p.supplyShares, 0);
        assertEq(p.borrowShares, 0);
        assertEq(p.collateral, collateralAmount);
        assertEq(usdc.balanceOf(alice.addr), 0);

        // ** Borrow
        uint256 borrowAmount = 1 ether / 4;
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
        assertEq(wstETH.balanceOf(alice.addr), assets);
        assertEq(p.collateral, collateralAmount);
        vm.stopPrank();
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

    // -- Helpers --

    IMorphoChainlinkOracleV2Factory morphoOracleFactory;
    MorphoChainlinkOracleV2 morphoOracle;

    MarketParams public marketParams;
    IMorpho morpho;

    function init_hook() internal {
        (currency0, currency1) = deployMintAndApprove2Currencies();

        token0 = TestERC20(Currency.unwrap(currency0));
        token1 = TestERC20(Currency.unwrap(currency1));

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

    function init_morpho_oracle() internal {
        morphoOracleFactory = IMorphoChainlinkOracleV2Factory(
            0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766
        );
        morphoOracle = morphoOracleFactory.createMorphoChainlinkOracleV2(
            IERC4626(0x0000000000000000000000000000000000000000),
            1,
            AggregatorV3Interface(0x0000000000000000000000000000000000000000),
            AggregatorV3Interface(0x0000000000000000000000000000000000000000),
            18,
            IERC4626(0x0000000000000000000000000000000000000000),
            1,
            AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46),
            AggregatorV3Interface(0x0000000000000000000000000000000000000000),
            6,
            "0x"
        );

        // console.log(oracle.price());
    }

    function create_and_seed_morpho_market() internal {
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");

        wstETH = TestERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        usdc = TestERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
        marketParams = MarketParams({
            loanToken: address(wstETH),
            collateralToken: address(usdc),
            oracle: 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2,
            irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            lltv: 945000000000000000
        });
        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        console.log("> collateralPrice", collateralPrice);
    }
}
