// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {OptionTestBase} from "@test/libraries/OptionTestBase.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PutETH} from "@src/PutETH.sol";
import {HedgehogLoyaltyMock} from "@test/libraries/HedgehogLoyaltyMock.sol";

import {IController, Vault} from "@forks/squeeth-monorepo/IController.sol";
import {IOption} from "@src/interfaces/IOption.sol";

contract PutETHTest is OptionTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    function setUp() public {
        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_market();
        init_hook();
        create_and_approve_accounts();
    }

    function test_morpho_blue_market() public {
        vm.startPrank(alice.addr);

        // ** Supply collateral
        deal(address(USDC), address(alice.addr), 10000 * 1e6);
        morpho.supplyCollateral(
            morpho.idToMarketParams(marketId),
            10000 * 1e6,
            alice.addr,
            ""
        );

        assertEqMorphoState(alice.addr, 0, 0, 10000 * 1e6);
        assertEq(USDC.balanceOf(alice.addr), 0);

        // ** Borrow
        (, uint256 shares) = morpho.borrow(
            morpho.idToMarketParams(marketId),
            2 ether,
            0,
            alice.addr,
            alice.addr
        );

        assertEqMorphoState(alice.addr, 0, shares, 10000 * 1e6);
        assertEq(WSTETH.balanceOf(alice.addr), 2 ether);
        vm.stopPrank();
    }

    function test_osqth_operations() public {
        IController powerTokenController = IController(
            0x64187ae08781B09368e6253F9E94951243A493D5
        );
        vm.startPrank(alice.addr);

        // ** Deposit OSQTH
        assertEqBalanceStateZero(alice.addr);
        deal(alice.addr, 100 ether);

        uint256 vaultId = powerTokenController.mintWPowerPerpAmount(0, 0, 0);
        powerTokenController.deposit{value: 10 ether}(vaultId);
        powerTokenController.mintPowerPerpAmount(vaultId, 10 ether / 2, 0);

        console.log("> OSQTH price", getETH_OSQTHPriceV3() / 1e18);
        console.log("> ETH price", (1e12 * 1e18) / getETH_USDCPriceV3());

        assertEqBalanceState(
            alice.addr,
            0,
            0,
            0,
            28606797160868548091,
            90 ether
        );

        Vault memory vault = powerTokenController.vaults(vaultId);
        assertEq(vault.collateralAmount, 10 ether);
        assertEq(vault.shortAmount, OSQTH.balanceOf(alice.addr));

        // ** Withdraw OSQTH
        powerTokenController.burnWPowerPerpAmount(
            vaultId,
            OSQTH.balanceOf(alice.addr),
            vault.collateralAmount
        );

        assertEqBalanceState(alice.addr, 0, 0, 0, 0, 100 ether);
        vm.stopPrank();
    }

    function test_deposit() public {
        uint256 amountToDeposit = 200000 * 1e6;
        deal(address(USDC), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        optionId = hook.deposit(key, amountToDeposit, alice.addr);

        assertOptionV4PositionLiquidity(optionId, 5097266086499115);
        assertEqBalanceStateZero(alice.addr);
        assertEqMorphoState(
            address(hook),
            0,
            0,
            amountToDeposit / hook.cRatio()
        );
        IOption.OptionInfo memory info = hook.getOptionInfo(optionId);
        assertEq(info.fee, 1e16);
    }

    function test_deposit_with_loyalty() public {
        uint256 amountToDeposit = 200000 * 1e6;
        loyalty.setIsLoyal(alice.addr, uint64(block.number));

        deal(address(USDC), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        optionId = hook.deposit(key, amountToDeposit, alice.addr);
        IOption.OptionInfo memory info = hook.getOptionInfo(optionId);
        assertEq(info.fee, 0);
    }

    function test_deposit_withdraw_not_option_owner_revert() public {
        test_deposit();

        vm.expectRevert(IOption.NotAnOptionOwner.selector);
        hook.withdraw(key, 0, alice.addr);
    }

    function test_deposit_withdraw() public {
        test_deposit();

        vm.prank(alice.addr);
        hook.withdraw(key, 0, alice.addr);

        assertEqBalanceStateZero(address(hook));
        assertEqBalanceState(alice.addr, 0, 200000 * 1e6, 0, 0);
        assertOptionV4PositionLiquidity(optionId, 0);
        assertEqMorphoState(address(hook), 0, 0, 0);
    }

    function test_swap_price_up_revert() public {
        test_deposit();

        deal(address(USDC), address(swapper.addr), 10000 * 1e6);
        vm.expectRevert(IOption.NoSwapWillOccur.selector);
        swapUSDC_WSTETH_Out(1 ether);
    }

    function test_swap_price_down() public {
        test_deposit();

        deal(address(WSTETH), address(swapper.addr), 11555648042810551244);
        swapWSTETH_USDC_Out(10 * 4500 * 1e6);

        assertEqBalanceState(swapper.addr, 0, 10 * 4500 * 1e6);
        assertEqBalanceState(address(hook), 0, 10080834793);
        assertEqMorphoState(
            address(hook),
            0,
            11555648042810551244000000,
            100000000000
        );
    }

    function test_swap_price_down_then_up() public {
        test_swap_price_down();

        swapUSDC_WSTETH_Out(231112960856211000);

        assertEqBalanceState(swapper.addr, 231112960856211000, 44216245243);
        assertEqBalanceState(address(hook), 0, 9297080036);
        assertEqMorphoState(
            address(hook),
            0,
            10653418290705234894000000,
            100000000000
        );
    }

    function test_swap_price_down_then_withdraw() public {
        test_swap_price_down();

        vm.prank(alice.addr);
        hook.withdraw(key, 0, alice.addr);

        assertEqBalanceStateZero(address(hook));
        assertEqBalanceState(alice.addr, 0, 206736939618);
        assertOptionV4PositionLiquidity(optionId, 0);
        assertEqMorphoState(address(hook), 0, 0, 0);
    }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        loyalty = new HedgehogLoyaltyMock();

        address payable hookAddress = payable(
            address(
                uint160(
                    Hooks.AFTER_SWAP_FLAG |
                        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                        Hooks.AFTER_INITIALIZE_FLAG
                )
            )
        );
        deployCodeTo(
            "PutETH.sol",
            abi.encode(manager, marketId, loyalty),
            hookAddress
        );
        PutETH _hook = PutETH(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);
        (key, ) = initPool(
            Currency.wrap(address(WSTETH)),
            Currency.wrap(address(USDC)),
            _hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );
        hook = IOption(hookAddress);
    }

    function create_and_seed_morpho_market() internal {
        create_morpho_market(
            address(WSTETH),
            address(USDC),
            915000000000000000,
            222866057499442860000000000000000000000000000 //4487 usdc for eth
        );

        provideLiquidityToMorpho(address(WSTETH), 100 * 1e18);
    }
}
